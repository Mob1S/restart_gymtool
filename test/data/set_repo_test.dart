import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/migrations.dart';
import 'package:gym_tracker/data/repositories/session_repo.dart';
import 'package:gym_tracker/data/repositories/set_repo.dart';

void main() {
  late FfiExecutor exec;
  late String sessionId;
  late String seId;

  setUp(() async {
    exec = await FfiExecutor.openInMemory();
    await migrate(exec);
    await exec.run(
      "INSERT INTO exercise (id, name, is_custom, is_archived, created_at) VALUES ('e1', '深蹲', 0, 0, 1)",
    );
    final s = await createSession(exec, name: null, templateId: null);
    sessionId = s.id;
    final se = await addExerciseToSession(exec, sessionId, 'e1');
    seId = se.id;
  });

  tearDown(() async => exec.close());

  test('新加的组是未完成的占位，position 从 0 起', () async {
    final a = await addSet(exec, seId, 20, 8);
    final b = await addSet(exec, seId, 20, 8);
    expect(a.isCompleted, isFalse);
    expect(a.position, 0);
    expect(b.position, 1);
    expect(a.restStartedAt, isNull);
    expect(a.completedAt, isNull);
  });

  test('listSets 含未完成的占位组，按 position 升序', () async {
    await addSet(exec, seId, 20, 8);
    final b = await addSet(exec, seId, 22.5, 8);
    await updateSetValues(exec, b.id, 25, 6);
    await completeSet(exec, b.id, 1000);
    final sets = await listSets(exec, seId);
    expect(sets, hasLength(2));
    expect(sets[0].isCompleted, isFalse);
    expect(sets[1].isCompleted, isTrue);
    expect(sets[1].weight, 25);
    expect(sets[1].reps, 6);
  });

  test('completeSet 记录 completed_at 并落盘', () async {
    final a = await addSet(exec, seId, 20, 8);
    await completeSet(exec, a.id, 1700000000000);
    final sets = await listSets(exec, seId);
    expect(sets.single.isCompleted, isTrue);
    expect(sets.single.completedAt, 1700000000000);
  });

  test('endRest 用时间戳相减算秒数，不写 rest_seconds 到别处', () async {
    final a = await addSet(exec, seId, 20, 8);
    await completeSet(exec, a.id, 1000);
    await startRest(exec, a.id, 1000000);
    await endRest(exec, a.id, 1090000); // 90 秒后

    final set = (await listSets(exec, seId)).single;
    expect(set.restSeconds, 90);
    expect(set.restStartedAt, isNull); // 休息结束，标记清掉
  });

  test('endRest 在该组本来就没在休息时静默返回，不写脏数据', () async {
    final a = await addSet(exec, seId, 20, 8);
    await completeSet(exec, a.id, 1000);
    await endRest(exec, a.id, 9999999); // 从没 startRest 过
    expect((await listSets(exec, seId)).single.restSeconds, isNull);
  });

  test('endRest 对不存在的 id 也不抛错', () async {
    await expectLater(endRest(exec, 'nope', 12345), completes);
  });

  test('cancelRest 清掉 rest_started_at，且**不写 rest_seconds**', () async {
    final a = await addSet(exec, seId, 20, 8);
    await completeSet(exec, a.id, 1000);
    await startRest(exec, a.id, 1000000);
    await cancelRest(exec, a.id);

    final set = (await listSets(exec, seId)).single;
    expect(set.restStartedAt, isNull);
    // ⭐ 关键：这段时长不是真实休息，不留下 ——
    // 否则一条 8 小时的记录会把休息建议的平均值彻底带偏
    expect(set.restSeconds, isNull);
  });

  test('getLastPerformance 从**更早的已结束**训练里取完成组', () async {
    // 上一场（已结束）
    await addSet(exec, seId, 40, 5);
    final prev = (await listSets(exec, seId)).single;
    await completeSet(exec, prev.id, 1000);
    await finishSession(exec, sessionId, 2000);

    // 这一场
    final s2 = await createSession(exec, name: null, templateId: null);
    // 计划原文这里是 `final se2 = await addExerciseToSession(...)`，
    // 但 se2 从未被使用 —— `flutter analyze` 会以 unused_local_variable 报警
    // （本 Task 的门槛是 No issues found!），故去掉赋值，保留这次调用本身。
    await addExerciseToSession(exec, s2.id, 'e1');

    final last = await getLastPerformance(exec, 'e1', s2.id);
    expect(last, hasLength(1));
    expect(last.single.weight, 40);
    expect(last.single.reps, 5);
  });

  test('getLastPerformance 排除本场自己', () async {
    final a = await addSet(exec, seId, 40, 5);
    await completeSet(exec, a.id, 1000);
    // 本场还没结束，所以它本身也不在「已结束」里；再加一场空的来确认返回值
    final last = await getLastPerformance(exec, 'e1', sessionId);
    expect(last, isEmpty);
  });

  test('getLastPerformance 从没练过时返回空数组（不是 null）', () async {
    expect(await getLastPerformance(exec, 'e1', sessionId), isEmpty);
  });

  test('getLastPerformance 只取最近一次训练，不混更早的', () async {
    // 更早的一场
    await addSet(exec, seId, 30, 5);
    final old = (await listSets(exec, seId)).single;
    await completeSet(exec, old.id, 1000);
    await finishSession(exec, sessionId, 2000);

    // 更近的一场
    final s2 = await createSession(exec, name: null, templateId: null);
    final se2 = await addExerciseToSession(exec, s2.id, 'e1');
    final b = await addSet(exec, se2.id, 50, 3);
    await completeSet(exec, b.id, 3000);
    await finishSession(exec, s2.id, 4000);

    // 这一场
    final s3 = await createSession(exec, name: null, templateId: null);

    final last = await getLastPerformance(exec, 'e1', s3.id);
    expect(last, hasLength(1));
    expect(last.single.weight, 50); // 只认最近那场，不是 30
  });

  // ⭐ 补上来的守卫（计划里没有）。`s.rowid DESC` 是 Task 8 唯一一处 rowid 兜底，
  // 而计划原有的「只取最近一次训练」那条**盖不住**它：那两场的 `started_at` 来自
  // 两次 `DateTime.now()`，通常不相等 —— 实测把 `, s.rowid DESC` 删掉后它照样通过。
  // 这条把两场候选显式设成同一毫秒，让并列成为确定事件（不是赌时钟）。
  test('两场候选同毫秒结束时按 rowid 兜底取后建的那场', () async {
    const sameMs = 1700000000000;

    // 先建的那场：30kg
    await addSet(exec, seId, 30, 5);
    final old = (await listSets(exec, seId)).single;
    await completeSet(exec, old.id, 1000);
    await finishSession(exec, sessionId, 2000);

    // 后建的那场：50kg
    final s2 = await createSession(exec, name: '后建的', templateId: null);
    final se2 = await addExerciseToSession(exec, s2.id, 'e1');
    final b = await addSet(exec, se2.id, 50, 3);
    await completeSet(exec, b.id, 3000);
    await finishSession(exec, s2.id, 4000);

    // 显式让两场候选完全并列
    await exec.run(
      'UPDATE session SET started_at = ? WHERE finished_at IS NOT NULL',
      [sameMs],
    );
    final candidates = await exec.all<Map<String, Object?>>(
      '''SELECT started_at FROM session
          WHERE finished_at IS NOT NULL
          ORDER BY rowid ASC''',
    );
    expect(candidates, hasLength(2));
    expect(candidates[0]['started_at'], candidates[1]['started_at'],
        reason: '两场必须真的并列，否则这条用例在空转');

    // 这一场（进行中）
    final s3 = await createSession(exec, name: null, templateId: null);

    final last = await getLastPerformance(exec, 'e1', s3.id);
    expect(
      last.single.weight,
      50,
      reason: '同毫秒时若没有 s.rowid DESC 兜底，SQLite 按扫描顺序返回先建的那场（30kg）—— 语义反了',
    );
  });
}
