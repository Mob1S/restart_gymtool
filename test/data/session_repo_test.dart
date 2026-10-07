import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/migrations.dart';
import 'package:gym_tracker/data/repositories/session_repo.dart';

void main() {
  late FfiExecutor exec;

  setUp(() async {
    exec = await FfiExecutor.openInMemory();
    await migrate(exec);
    await exec.run(
      "INSERT INTO exercise (id, name, is_custom, is_archived, created_at) VALUES ('e1', '深蹲', 0, 0, 1)",
    );
  });

  tearDown(() async => exec.close());

  test('新建的训练是进行中的', () async {
    final s = await createSession(exec, name: null, templateId: null);
    expect(s.finishedAt, isNull);
    expect((await getActiveSession(exec))?.id, s.id);
  });

  test('getSession 能取到进行中的那一场（不像 listSessions 会滤掉）', () async {
    final s = await createSession(exec, name: '推日', templateId: null);
    expect((await getSession(exec, s.id))?.name, '推日');
  });

  test('listSessions 只返回已结束的', () async {
    final s = await createSession(exec, name: null, templateId: null);
    expect(await listSessions(exec, 50), isEmpty);
    await finishSession(exec, s.id, DateTime.now().millisecondsSinceEpoch);
    expect(await listSessions(exec, 50), hasLength(1));
  });

  test('结束训练后不再是进行中的', () async {
    final s = await createSession(exec, name: null, templateId: null);
    await finishSession(exec, s.id, 12345);
    expect(await getActiveSession(exec), isNull);
  });

  // ⭐ 这条是 rowid 兜底的存在理由，不能删
  test('同一毫秒开始的两场，取最新时按 rowid 兜底（否则语义反了）', () async {
    const sameMs = 1700000000000;

    // 显式把两行设成同一个 started_at —— 让「并列」成为**确定事件**，
    // 而不是赌两次调用恰好落在同一毫秒（那种测试实测 20 次闪 2 次）。
    await createSession(exec, name: '先建的', templateId: null);
    await createSession(exec, name: '后建的', templateId: null);
    await exec.run('UPDATE session SET started_at = ?', [sameMs]);

    final rows = await exec.all<Map<String, Object?>>(
      'SELECT name, started_at FROM session ORDER BY started_at ASC',
    );
    // 先断言并列真的发生了，否则这条测试就在空转
    expect(rows[0]['started_at'], rows[1]['started_at']);

    final list = await listSessions(exec, 50);
    // 已结束的才进 listSessions，所以先都结束掉
    //
    // 注意：上面两次 createSession 都没结束，这里补上
    await exec.run('UPDATE session SET finished_at = ?', [sameMs + 1]);
    final finished = await listSessions(exec, 50);
    // 同毫秒时 SQLite 按扫描顺序返回（先插入的在前）——语义正好反了。
    // rowid DESC 兜底后，后建的「后建的」必须排在前。
    expect(finished.first.name, '后建的');
    expect(list, isEmpty); // 结束之前 listSessions 是空的
  });

  // ⭐ 补上来的守卫（计划里没有）。getActiveSession 的 `rowid DESC` 与上面那条
  // 是同一个坑：App 被强杀会留下两条未结束的记录，同毫秒时若无兜底，
  // 「继续上次训练」会捡起更早的那场。
  test('两条都没结束时 getActiveSession 取后建的那场（rowid 兜底）', () async {
    const sameMs = 1700000000000;

    await createSession(exec, name: '先建的', templateId: null);
    final later = await createSession(exec, name: '后建的', templateId: null);
    await exec.run('UPDATE session SET started_at = ?', [sameMs]);

    final rows = await exec.all<Map<String, Object?>>(
      'SELECT started_at FROM session ORDER BY rowid ASC',
    );
    expect(rows[0]['started_at'], rows[1]['started_at'],
        reason: '两行必须真的并列，否则这条用例在空转');

    expect(
      (await getActiveSession(exec))?.id,
      later.id,
      reason: '同毫秒时若没有 rowid DESC 兜底，SQLite 按扫描顺序返回先建的那场 —— 语义反了',
    );
  });

  // ⭐ 补上来的守卫（计划里没有）。findLastActiveSessionExerciseId 的
  // `st.rowid DESC` 是同一个坑的第三处：同毫秒完成的两组若不兜底，
  // resume 会把「练到第几个动作」定位到更早的那个动作。
  test('同毫秒完成的两组，findLastActive 取后完成的那组所属的动作', () async {
    const sameMs = 1700000000000;

    final s = await createSession(exec, name: null, templateId: null);
    final a = await addExerciseToSession(exec, s.id, 'e1');
    final b = await addExerciseToSession(exec, s.id, 'e1');

    // 直接插 set_entry：Task 7 只该依赖 session_repo，不引入 set_repo
    await exec.run(
      '''INSERT INTO set_entry
           (id, session_exercise_id, position, weight, reps, is_completed, completed_at)
         VALUES ('st-a', ?, 0, 20, 8, 1, ?)''',
      [a.id, sameMs],
    );
    await exec.run(
      '''INSERT INTO set_entry
           (id, session_exercise_id, position, weight, reps, is_completed, completed_at)
         VALUES ('st-b', ?, 0, 20, 8, 1, ?)''',
      [b.id, sameMs],
    );

    expect(
      await findLastActiveSessionExerciseId(exec, s.id),
      b.id,
      reason: '同毫秒时若没有 st.rowid DESC 兜底，SQLite 按扫描顺序返回先插入的那组',
    );
  });

  test('加入动作的 position 依次递增', () async {
    final s = await createSession(exec, name: null, templateId: null);
    final a = await addExerciseToSession(exec, s.id, 'e1');
    final b = await addExerciseToSession(exec, s.id, 'e1');
    expect(a.position, 0);
    expect(b.position, 1);
  });

  test('动作按 position 升序返回', () async {
    final s = await createSession(exec, name: null, templateId: null);
    final a = await addExerciseToSession(exec, s.id, 'e1');
    final b = await addExerciseToSession(exec, s.id, 'e1');
    final list = await listSessionExercises(exec, s.id);
    expect(list.map((e) => e.id).toList(), [a.id, b.id]);
  });

  test('没有动作时返回空数组（不是 null）', () async {
    final s = await createSession(exec, name: null, templateId: null);
    expect(await listSessionExercises(exec, s.id), isEmpty);
  });

  test('一组都没完成过时，findLastActive 返回 null', () async {
    final s = await createSession(exec, name: null, templateId: null);
    await addExerciseToSession(exec, s.id, 'e1');
    expect(await findLastActiveSessionExerciseId(exec, s.id), isNull);
  });
}
