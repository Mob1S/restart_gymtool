import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/migrations.dart';
import 'package:gym_tracker/data/repositories/exercise_repo.dart';
import 'package:gym_tracker/data/repositories/seed.dart';

void main() {
  late FfiExecutor exec;

  setUp(() async {
    exec = await FfiExecutor.openInMemory();
    await migrate(exec);
  });

  tearDown(() async => exec.close());

  test('预置动作恰好 52 个', () {
    expect(seedExercises, hasLength(52));
  });

  test('播种写入 52 个动作，is_custom 一律为 0', () async {
    await seedExercisesIfEmpty(exec);
    final all = await listExercises(exec);
    expect(all, hasLength(52));
    expect(all.every((e) => !e.isCustom), isTrue);
  });

  test('播种只在空表时发生 —— 已有动作时不再写', () async {
    await seedExercisesIfEmpty(exec);
    await seedExercisesIfEmpty(exec);
    expect(await listExercises(exec), hasLength(52));
  });

  test('用户先自建了动作，就不该再塞预置动作进去', () async {
    await createCustomExercise(exec, name: '我的动作');
    await seedExercisesIfEmpty(exec);
    final all = await listExercises(exec);
    expect(all, hasLength(1));
    expect(all.single.name, '我的动作');
  });

  test('排序：先按肌群名次（胸背腿肩手臂核心），同肌群按拼音', () async {
    await seedExercisesIfEmpty(exec);
    final all = await listExercises(exec);
    // 排第一的必须是胸组的动作
    expect(all.first.muscleGroup, '胸');
    // 同一肌群内按拼音：胸组里 "俯卧撑" (fu) 应早于 "绳索夹胸" (sheng)
    final chest = all.where((e) => e.muscleGroup == '胸').toList();
    final fu = chest.indexWhere((e) => e.name == '俯卧撑');
    final sheng = chest.indexWhere((e) => e.name == '绳索夹胸');
    expect(fu, lessThan(sheng));
  });

  test('归档的动作不出现在列表里，但仍能按 id 取到', () async {
    await seedExercisesIfEmpty(exec);
    final target = (await listExercises(exec)).first;
    await exec.run('UPDATE exercise SET is_archived = 1 WHERE id = ?', [
      target.id,
    ]);

    final visible = await listExercises(exec);
    expect(visible.any((e) => e.id == target.id), isFalse);
    // 历史记录引用着它，取不到就会显示成「未知动作」
    expect((await getExercise(exec, target.id))?.name, target.name);
  });

  test('自建动作 isCustom 为 true，且带 null 肌群时排到最后', () async {
    await seedExercisesIfEmpty(exec);
    await createCustomExercise(exec, name: '自定义动作');
    final all = await listExercises(exec);
    expect(all.last.name, '自定义动作');
    expect(all.last.isCustom, isTrue);
  });

  test('中文按拼音序而不是 UTF-8 码点序', () async {
    await createCustomExercise(exec, name: '深蹲架', muscleGroup: '腿');
    await createCustomExercise(exec, name: '保加利亚', muscleGroup: '腿');
    await createCustomExercise(exec, name: '硬拉', muscleGroup: '腿');
    final legs = (await listExercises(exec))
        .where((e) => e.muscleGroup == '腿')
        .toList();
    // 按码点序会排成「保加利亚、硬拉、深蹲架」——
    // 拼音序才是中文用户预期的「保加利亚(bao)、深蹲架(shen)、硬拉(ying)」
    final names = legs.map((e) => e.name).toList();
    expect(names.indexOf('保加利亚'), lessThan(names.indexOf('深蹲架')));
    expect(names.indexOf('深蹲架'), lessThan(names.indexOf('硬拉')));
  });

  test('⭐ 排序守卫必须能把「码点序」判红 —— 否则它是空转的', () async {
    await seedExercisesIfEmpty(exec);
    final legs = (await listExercises(exec))
        .where((e) => e.muscleGroup == '腿')
        .toList();
    final names = legs.map((e) => e.name).toList();

    // 臀推(tun, U+81C0) 与 站姿提踵(zhan, U+7AD9)：
    //   拼音序  tun < zhan           → 臀推在前
    //   码点序  U+7AD9(31449) < U+81C0(33216) → 站姿提踵在前，**方向相反**
    //
    // ⚠️ 这条断言是**补上来的**，因为上面那条「中文按拼音序」是**空转**的：
    // 它用的三个字 保 U+4FDD / 深 U+6DF1 / 硬 U+786C，**码点序恰好就是拼音序**。
    // 实测确认过：把 compareExercises 里的 pinyinKey 换成纯 name.compareTo
    // 之后，上面那条断言**依然通过** —— 也就是说将来有人删掉拼音排序，
    // 测试会全绿地放行。
    //
    // 一条永远绿的守卫等于没有守卫。这条断言在前一种实现下过、在后一种下必红。
    expect(
      names.indexOf('臀推'),
      lessThan(names.indexOf('站姿提踵')),
      reason:
          '拼音序 tun < zhan，臀推应排在站姿提踵之前；'
          '若这里红了，说明排序退回了 UTF-8 码点序',
    );
  });
}
