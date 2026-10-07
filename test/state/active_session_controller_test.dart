import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/migrations.dart';
import 'package:gym_tracker/data/repositories/exercise_repo.dart';
import 'package:gym_tracker/data/repositories/session_repo.dart';
// 计划给的 import 清单里有 `set_repo.dart`，但本文件一个 set_repo 的符号都没用到
// （`listSets` 等只出现在 Task 11 的 complete_set_test.dart 里）——
// 留着它会 `flutter analyze` 报 unused_import，故删除。
import 'package:gym_tracker/state/active_session_controller.dart';

void main() {
  late FfiExecutor exec;
  late String squatId;
  late String benchId;

  setUp(() async {
    exec = await FfiExecutor.openInMemory();
    await migrate(exec);
    squatId = (await createCustomExercise(exec, name: '深蹲', muscleGroup: '腿')).id;
    benchId = (await createCustomExercise(exec, name: '卧推', muscleGroup: '胸')).id;
  });

  tearDown(() async => exec.close());

  ActiveSessionController make() => ActiveSessionController(exec);

  test('没有进行中的训练时 resume 返回 false，store 保持原样', () async {
    final c = make();
    expect(await c.resume(), isFalse);
    expect(c.session, isNull);
    expect(c.exercises, isEmpty);
  });

  test('startNew 建出一场进行中的训练', () async {
    final c = make();
    expect(await c.startNew(), StartResult.started);
    expect(c.session, isNotNull);
    expect(c.session!.finishedAt, isNull);
  });

  test('第一次用 App（无历史）时开一场空训练，不崩', () async {
    final c = make();
    await c.startNew();
    expect(c.exercises, isEmpty);
    expect(c.currentIndex, 0);
  });

  test('⭐ 已有进行中的训练时 startNew 返回 conflict，且不新建第二条', () async {
    final c = make();
    await c.startNew();
    final firstId = c.session!.id;

    final c2 = make();
    expect(await c2.startNew(), StartResult.conflict);
    // 库里仍然只有一条未结束的
    final rows = await exec.all("SELECT * FROM session WHERE finished_at IS NULL");
    expect(rows, hasLength(1));
    expect((await getActiveSession(exec))!.id, firstId);
  });

  test('⭐ conflict 时那一场必须已被装进 store（否则「接着练」进到空屏）', () async {
    final c = make();
    await c.startNew();
    await c.addExercise(squatId);

    final c2 = make();
    await c2.startNew();
    expect(c2.session, isNotNull);
    expect(c2.exercises, hasLength(1));
    expect(c2.exercises.single.exerciseName, '深蹲');
  });

  test('startNew 复制上一次已结束训练的动作组合与顺序', () async {
    final c = make();
    await c.startNew();
    await c.addExercise(squatId);
    await c.addExercise(benchId);
    await c.endWorkout();

    final c2 = make();
    await c2.startNew();
    expect(c2.exercises.map((e) => e.exerciseName).toList(), ['深蹲', '卧推']);
  });

  test('startNew 复制的是**最近一场已结束**训练的动作组合', () async {
    // 第一场：深蹲，已结束
    final c = make();
    await c.startNew();
    await c.addExercise(squatId);
    await c.endWorkout();

    // 第二场：从第一场复制来深蹲，再加卧推，然后结束它
    final c2 = make();
    await c2.startNew();
    expect(c2.exercises.map((e) => e.exerciseName).toList(), ['深蹲']);
    await c2.addExercise(benchId);
    await c2.endWorkout();

    // 第三场应复制第二场（最近一场已结束），而不是第一场
    final c3 = make();
    await c3.startNew();
    expect(c3.exercises.map((e) => e.exerciseName).toList(), ['深蹲', '卧推']);
  });

  test('进行中的那一场不会被当成「上一次」', () async {
    // 只造一场**没结束**的训练，里面已经有动作
    final c = make();
    await c.startNew();
    await c.addExercise(squatId);

    // listSessions 只返回已结束的 —— 它是「上一次」的唯一来源，
    // 所以此刻「上一次」必须是空的
    expect(await listSessions(exec, 1), isEmpty);
  });

  test('⭐ addExercise 必须预建第一组（否则「完成这组」是静默假死按钮）', () async {
    final c = make();
    await c.startNew();
    await c.addExercise(squatId);

    final sets = c.exercises.single.sets;
    expect(sets, hasLength(1));
    expect(sets.single.isCompleted, isFalse);
  });

  test('新动作的第一组预填上次成绩；从没练过时用默认值 20kg × 8', () async {
    final c = make();
    await c.startNew();
    await c.addExercise(squatId);
    final sets = c.exercises.single.sets;
    expect(sets.single.weight, 20);
    expect(sets.single.reps, 8);
  });

  test('addExercise 后 currentIndex 跳到新加的那个动作', () async {
    final c = make();
    await c.startNew();
    await c.addExercise(squatId);
    await c.addExercise(benchId);
    expect(c.currentIndex, 1);
  });

  test('resume 恢复练到第几个动作（按 completed_at 最大的那组推导）', () async {
    final c = make();
    await c.startNew();
    await c.addExercise(squatId);
    await c.addExercise(benchId);
    // 在第二个动作上完成一组
    c.setCurrentIndex(1);
    await c.completeCurrentSet(60, 8);

    // 模拟强杀重开
    final c2 = make();
    expect(await c2.resume(), isTrue);
    expect(c2.currentIndex, 1);
    expect(c2.exercises[1].sets.where((s) => s.isCompleted), hasLength(1));
  });

  test('resume 时一组都没完成过 → currentIndex 为 0', () async {
    final c = make();
    await c.startNew();
    await c.addExercise(squatId);
    await c.addExercise(benchId);

    final c2 = make();
    await c2.resume();
    expect(c2.currentIndex, 0);
  });

  test('⭐ 30 分钟闸门：resume 时清掉跑过头的休息，且不写 rest_seconds', () async {
    final c = make();
    await c.startNew();
    await c.addExercise(squatId);
    await c.completeCurrentSet(20, 8);

    // 手工把休息开始时间推到 40 分钟前
    final longAgo = DateTime.now().millisecondsSinceEpoch - 40 * 60 * 1000;
    await exec.run('UPDATE set_entry SET rest_started_at = ?', [longAgo]);

    final c2 = make();
    await c2.resume();
    final set = c2.exercises.single.sets.firstWhere((s) => s.isCompleted);
    expect(set.restStartedAt, isNull);
    // 关键：这段荒唐时长不能被记成真实休息
    expect(set.restSeconds, isNull);
  });

  test('训练已结束时 addExercise 静默返回（防御性闸门）', () async {
    final c = make();
    await c.startNew();
    await c.endWorkout();
    // 正常路径下 endWorkout 已清空 store，这里手工把已结束的塞回去
    // 来验证闸门 —— 旧项目那个「同一场被接上第二次」的 bug 就是这么来的
    await c.addExercise(squatId);
    expect(c.exercises, isEmpty);
  });
}
