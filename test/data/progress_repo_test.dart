import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/migrations.dart';
import 'package:gym_tracker/data/repositories/progress_repo.dart';
import 'package:gym_tracker/data/repositories/session_repo.dart';
import 'package:gym_tracker/data/repositories/set_repo.dart';

/// 建一场训练、写入若干组，返回 sessionId。
/// 每组写成 `(动作id, 重量, 次数, 是否标记完成)`；同动作的组落在同一个
/// `session_exercise` 下。`finish: false` 用来造「进行中」的那一场。
Future<String> seedSession(
  FfiExecutor exec,
  List<(String, double, int, bool)> sets, {
  bool finish = true,
}) async {
  final session = await createSession(exec, name: null, templateId: null);
  final seIds = <String, String>{};

  for (final (exerciseId, weight, reps, completed) in sets) {
    var seId = seIds[exerciseId];
    if (seId == null) {
      seId = (await addExerciseToSession(exec, session.id, exerciseId)).id;
      seIds[exerciseId] = seId;
    }
    final set = await addSet(exec, seId, weight, reps);
    if (completed) {
      await completeSet(exec, set.id, 1000);
    }
  }

  if (finish) {
    await finishSession(exec, session.id, 2000);
  }
  return session.id;
}

void main() {
  late FfiExecutor exec;

  setUp(() async {
    exec = await FfiExecutor.openInMemory();
    await migrate(exec);
    await exec.run(
      "INSERT INTO exercise (id, name, is_custom, is_archived, created_at) VALUES ('e1', '深蹲', 0, 0, 1)",
    );
    await exec.run(
      "INSERT INTO exercise (id, name, is_custom, is_archived, created_at) VALUES ('e2', '卧推', 0, 0, 1)",
    );
  });

  tearDown(() async => exec.close());

  // ⭐ 这条是 `s.finished_at IS NOT NULL` 的存在理由。去掉它，这场训练
  // （组都已完成的）会立刻混进结果 —— 进步曲线在半场训练中途自己变一次样。
  test('1. 进行中的训练不进结果', () async {
    await seedSession(exec, [('e1', 20, 8, true)], finish: false);

    expect(await listAllCompletedSetFacts(exec), isEmpty);
  });

  test('2. 未完成的占位组不进结果', () async {
    // 界面上永远留着一条 `is_completed = 0` 的「下一组」，它不是做过的事实
    await seedSession(exec, [('e1', 20, 8, true), ('e1', 25, 5, false)]);

    final facts = await listAllCompletedSetFacts(exec);
    expect(facts, hasLength(1));
    expect(facts.single.weight, 20);
    expect(facts.single.reps, 8);
  });

  test('3. 一场里两个动作的组按 exerciseId 分得开，字段各自对得上', () async {
    const startedAt = 1700000000000;
    final sessionId = await seedSession(exec, [
      ('e1', 20, 8, true),
      ('e2', 100, 5, true),
    ]);
    // 开始时间来自 session 表（两条 JOIN 之一），写成确定值才断得动
    await exec.run('UPDATE session SET started_at = ? WHERE id = ?', [
      startedAt,
      sessionId,
    ]);

    final facts = await listAllCompletedSetFacts(exec);
    expect(facts, hasLength(2));

    final squat = facts.singleWhere((f) => f.exerciseId == 'e1');
    final bench = facts.singleWhere((f) => f.exerciseId == 'e2');
    expect(squat.sessionId, sessionId);
    expect(squat.sessionStartedAt, startedAt);
    expect(squat.weight, 20);
    expect(squat.reps, 8);
    expect(bench.weight, 100);
    expect(bench.reps, 5);
  });

  // 组的插入顺序与训练的插入顺序相反，才不会碰巧按同一个顺序返回。
  // 去掉 s.rowid 后，剩余 ORDER BY 的 st.rowid 会明确排成 [30, 20]，
  // 因而本用例能确定地发现训练级兜底丢失，不依赖 SQLite 选择哪种扫描计划。
  test('4. 同毫秒训练按训练 rowid 排序，即使组记录按相反顺序插入', () async {
    const sameMs = 1700000000000;

    final first = await createSession(exec);
    final second = await createSession(exec);
    for (final (session, weight) in [(second, 30.0), (first, 20.0)]) {
      final exercise = await addExerciseToSession(exec, session.id, 'e1');
      final set = await addSet(exec, exercise.id, weight, 8);
      await completeSet(exec, set.id, sameMs + 1000);
      await finishSession(exec, session.id, sameMs + 2000);
    }
    // 显式让两场并列 —— 不赌两次 DateTime.now() 恰好落在同一毫秒
    await exec.run('UPDATE session SET started_at = ?', [sameMs]);

    final rows = await exec.all<Map<String, Object?>>(
      'SELECT started_at FROM session ORDER BY rowid ASC',
    );
    expect(
      rows[0]['started_at'],
      rows[1]['started_at'],
      reason: '两场必须真的并列，否则这条用例在空转',
    );

    final facts = await listAllCompletedSetFacts(exec);
    // 重量把两场区分开：顺序万一只是碰巧对了，这里也看得见
    expect(facts.map((f) => f.weight).toList(), [20, 30]);
    expect(facts.map((f) => f.sessionId).toList(), [first.id, second.id]);
  });

  test('5. 一场都没有的库返回空表，不是异常', () async {
    expect(await listAllCompletedSetFacts(exec), isEmpty);
  });
}
