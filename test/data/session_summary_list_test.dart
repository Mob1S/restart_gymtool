import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/migrations.dart';
import 'package:gym_tracker/data/db/sql_executor.dart';
import 'package:gym_tracker/data/repositories/session_repo.dart';
import 'package:gym_tracker/domain/metrics.dart';
import 'package:gym_tracker/domain/types.dart';

/// 直接插一条组记录。
///
/// **不引入 set_repo** —— 本文件只该依赖 session_repo（同 `session_repo_test`
/// 的约定）。而且占位组（`is_completed: false`）要手工造，走仓储的「完成这组」
/// 反而没有入口 —— 那条路径只会把组标记成已完成。
Future<void> insertSet(
  SqlExecutor exec, {
  required String id,
  required String sessionExerciseId,
  required int position,
  required double weight,
  required int reps,
  required bool isCompleted,
}) => exec.run(
  '''INSERT INTO set_entry
       (id, session_exercise_id, position, weight, reps, is_completed)
     VALUES (?, ?, ?, ?, ?, ?)''',
  [id, sessionExerciseId, position, weight, reps, isCompleted ? 1 : 0],
);

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

  // ⭐ 这条是 LEFT JOIN 的存在理由：改成 JOIN 时它会红。
  // 0 组训练不是脏数据 —— 用户开了场训练、一个动作没加就结束，是真实会发生的。
  test('一个动作都没加就结束的训练仍然出现，setCount 是 0', () async {
    final s = await createSession(exec, name: '空训练', templateId: null);
    await finishSession(exec, s.id, s.startedAt + 60000);

    final rows = await listSessionSummaries(exec);

    expect(rows, hasLength(1));
    expect(rows.single.session.id, s.id);
    expect(rows.single.setCount, 0);
  });

  // ⭐ 这条是 COALESCE(SUM(...), 0) 的存在理由：去掉它时 SUM 返回 NULL，
  // 本用例会红在 [SessionSummaryRow.fromMap] 的类型转换上（不是红在 expect 上）。
  test('0 组时容量是 0 而不是 null', () async {
    final s = await createSession(exec, name: '空训练', templateId: null);
    await finishSession(exec, s.id, s.startedAt + 60000);

    final rows = await listSessionSummaries(exec);

    expect(rows.single.volumeLoad, 0);
  });

  // ⭐ 进行中的那一场不能进历史 —— 否则用户练到一半切过来，会看见一行
  // 数字还在长的记录（规格 §3.1 的同一条规矩，进步页那条 SQL 也靠它）。
  test('进行中的训练不出现（WHERE finished_at IS NOT NULL）', () async {
    final finished = await createSession(exec, name: '已结束', templateId: null);
    final se1 = await addExerciseToSession(exec, finished.id, 'e1');
    await insertSet(
      exec,
      id: 'st-done',
      sessionExerciseId: se1.id,
      position: 0,
      weight: 20,
      reps: 8,
      isCompleted: true,
    );
    await finishSession(exec, finished.id, finished.startedAt + 60000);

    // 进行中的那一场也有一组已完成 —— 保证它只可能被 WHERE 拦下，
    // 不会被别的条件顺手滤掉（否则这条测试就在空转）
    final running = await createSession(exec, name: '进行中', templateId: null);
    final se2 = await addExerciseToSession(exec, running.id, 'e1');
    await insertSet(
      exec,
      id: 'st-running',
      sessionExerciseId: se2.id,
      position: 0,
      weight: 60,
      reps: 5,
      isCompleted: true,
    );

    final rows = await listSessionSummaries(exec);

    expect(rows.map((r) => r.session.id).toList(), [finished.id]);
  });

  test('只数已完成的组 —— 占位组既不进 setCount 也不进容量', () async {
    final s = await createSession(exec, name: null, templateId: null);
    final se = await addExerciseToSession(exec, s.id, 'e1');
    await insertSet(
      exec,
      id: 'st-done',
      sessionExerciseId: se.id,
      position: 0,
      weight: 20,
      reps: 8,
      isCompleted: true,
    );
    // 占位组：记录界面为「下一组」预先建的那一条，从没被完成。
    // 重量取一个显眼的数，混进来一眼能认出来。
    await insertSet(
      exec,
      id: 'st-todo',
      sessionExerciseId: se.id,
      position: 1,
      weight: 999,
      reps: 99,
      isCompleted: false,
    );
    await finishSession(exec, s.id, s.startedAt + 60000);

    final rows = await listSessionSummaries(exec);

    expect(rows.single.setCount, 1);
    expect(rows.single.volumeLoad, 160, reason: '占位组的 999 × 99 一个字都不能进来');
  });

  test('容量口径与总结页一致：Σ(重量 × 次数)', () async {
    final s = await createSession(exec, name: null, templateId: null);
    final se = await addExerciseToSession(exec, s.id, 'e1');
    await insertSet(
      exec,
      id: 'st-a',
      sessionExerciseId: se.id,
      position: 0,
      weight: 20,
      reps: 8,
      isCompleted: true,
    );
    await insertSet(
      exec,
      id: 'st-b',
      sessionExerciseId: se.id,
      position: 1,
      weight: 30,
      reps: 10,
      isCompleted: true,
    );
    await finishSession(exec, s.id, s.startedAt + 60000);

    final row = (await listSessionSummaries(exec)).single;

    expect(row.setCount, 2);
    expect(row.volumeLoad, closeTo(460, 0.001)); // 20×8 + 30×10

    // 再与总结页用的那一份实现对照 —— 口径只有一份，分叉时这条会红
    expect(
      row.volumeLoad,
      closeTo(
        totalVolumeLoad(const [
          SetLike(weight: 20, reps: 8, isCompleted: true),
          SetLike(weight: 30, reps: 10, isCompleted: true),
        ]),
        0.001,
      ),
    );
  });

  test('最近的训练排在前面（started_at DESC）', () async {
    final older = await createSession(exec, name: '上周', templateId: null);
    final newer = await createSession(exec, name: '昨天', templateId: null);

    // 时间显式写死，**不赌**两次 createSession 落在不同毫秒 ——
    // 那种写法实测 20 次闪 2 次（`session_repo_test` 里记着这个数）
    await exec.run('UPDATE session SET started_at = ? WHERE id = ?', [
      1000,
      older.id,
    ]);
    await exec.run('UPDATE session SET started_at = ? WHERE id = ?', [
      2000,
      newer.id,
    ]);
    await finishSession(exec, older.id, 3000);
    await finishSession(exec, newer.id, 4000);

    final rows = await listSessionSummaries(exec);

    expect(rows.map((r) => r.session.name).toList(), ['昨天', '上周']);
  });

  // ⭐ `rowid DESC` 兜底的存在理由（总纲 §4.3），与 getActiveSession 同一个坑
  test('同毫秒开始的两场，rowid DESC 兜底 —— 后建的在前', () async {
    const sameMs = 1700000000000;

    await createSession(exec, name: '先建的', templateId: null);
    await createSession(exec, name: '后建的', templateId: null);
    // 把两行写成同一个 started_at —— 让「并列」成为**确定事件**，不 sleep。
    // 两场都结束掉，才进得了这条查询。
    await exec.run('UPDATE session SET started_at = ?, finished_at = ?', [
      sameMs,
      sameMs + 1,
    ]);

    // 先断言并列真的发生了，否则这条测试就在空转（同 session_repo_test 的手法）
    final raw = await exec.all<Map<String, Object?>>(
      'SELECT started_at FROM session ORDER BY rowid ASC',
    );
    expect(raw[0]['started_at'], raw[1]['started_at']);

    final rows = await listSessionSummaries(exec);

    // 同毫秒时若没有 rowid DESC，SQLite 按扫描顺序返回（先插入的在前）—— 语义反了
    expect(rows.map((r) => r.session.name).toList(), ['后建的', '先建的']);
  });

  // ⭐ 补上来的守卫（计划里没有）。时长是按总结页的算法在 Dart 里算的，
  // 不是 SQL 的一列 —— 写成 `~/ 1000`（截断）或除错数量级，这条会红。
  test('时长与总结页同一个算法：四舍五入到秒', () async {
    final s = await createSession(exec, name: null, templateId: null);
    // 90.6 秒 —— 整秒数锁不住 round 与截断的区别
    await exec.run(
      'UPDATE session SET started_at = ?, finished_at = ? WHERE id = ?',
      [1700000000000, 1700000090600, s.id],
    );

    final rows = await listSessionSummaries(exec);

    expect(rows.single.durationSeconds, 91);
  });

  // ⭐ 补上来的守卫（计划里没有）。计划给的 SELECT 只列了四列，实现补上了
  // note / template_id —— 行里内嵌的是完整的 WorkoutSession，缺列会被
  // `SessionRow.fromMap` **静默填 null**，读它的人不会收到任何提示。
  test('行里内嵌的 session 带上 note 与 template_id，不静默填 null', () async {
    final s = await createSession(exec, name: '推日', templateId: 'tpl-1');
    await exec.run(
      'UPDATE session SET note = ?, started_at = ?, finished_at = ? WHERE id = ?',
      ['状态不错', 1000, 2000, s.id],
    );

    final rows = await listSessionSummaries(exec);

    expect(rows.single.session.name, '推日');
    expect(rows.single.session.note, '状态不错');
    expect(rows.single.session.templateId, 'tpl-1');
  });
}
