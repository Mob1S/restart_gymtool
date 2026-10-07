import '../../domain/types.dart';
import '../db/sql_executor.dart';
import '../ids.dart';

/// `session` 表的原始行。布尔在库里是 0/1，转换见 [toSession]。
///
/// **字段用 camelCase，列名（map 的键）用 snake_case** —— 两者的对应关系由
/// [SessionRow.fromMap] 一处显式写出（约定见 Global Constraints）。
class SessionRow {
  final String id;
  final String? name;
  final int startedAt;
  final int? finishedAt;
  final String? note;
  final String? templateId;

  const SessionRow({
    required this.id,
    this.name,
    required this.startedAt,
    this.finishedAt,
    this.note,
    this.templateId,
  });

  factory SessionRow.fromMap(Map<String, Object?> m) => SessionRow(
        id: m['id'] as String,
        name: m['name'] as String?,
        startedAt: m['started_at'] as int,
        finishedAt: m['finished_at'] as int?,
        note: m['note'] as String?,
        templateId: m['template_id'] as String?,
      );
}

/// `session_exercise` 表的原始行。
class SessionExerciseRow {
  final String id;
  final String sessionId;
  final String exerciseId;
  final int position;
  final String? note;

  const SessionExerciseRow({
    required this.id,
    required this.sessionId,
    required this.exerciseId,
    required this.position,
    this.note,
  });

  factory SessionExerciseRow.fromMap(Map<String, Object?> m) => SessionExerciseRow(
        id: m['id'] as String,
        sessionId: m['session_id'] as String,
        exerciseId: m['exercise_id'] as String,
        position: m['position'] as int,
        note: m['note'] as String?,
      );
}

WorkoutSession toSession(SessionRow row) => WorkoutSession(
      id: row.id,
      name: row.name,
      startedAt: row.startedAt,
      finishedAt: row.finishedAt,
      note: row.note,
      templateId: row.templateId,
    );

SessionExercise toSessionExercise(SessionExerciseRow row) => SessionExercise(
      id: row.id,
      sessionId: row.sessionId,
      exerciseId: row.exerciseId,
      position: row.position,
      note: row.note,
    );

const String sessionColumns = 'id, name, started_at, finished_at, note, template_id';
const String sessionExerciseColumns = 'id, session_id, exercise_id, position, note';

/// 开一场新训练。`finishedAt` 与 `note` 一律为空 —— 新训练必然是进行中的。
///
/// 本函数**不检查是否已有进行中的训练**：「同时只可能有一场进行中」这条
/// 不变量由 `state/active_session_controller.dart` 的 `startNew` 单独把守
/// （它要先问用户「接着练还是结束它」）。绕过它直接调本函数，
/// 就会留下两场进行中的记录。
Future<WorkoutSession> createSession(
  SqlExecutor exec, {
  String? name,
  String? templateId,
}) async {
  final session = WorkoutSession(
    id: newId(),
    name: name,
    startedAt: DateTime.now().millisecondsSinceEpoch,
    finishedAt: null,
    note: null,
    templateId: templateId,
  );
  await exec.run(
    'INSERT INTO session (id, name, started_at, finished_at, note, template_id) VALUES (?, ?, ?, NULL, NULL, ?)',
    [session.id, session.name, session.startedAt, session.templateId],
  );
  return session;
}

/// 按 id 取一场训练。**进行中的那一场也能取到**（不像 [listSessions] 会滤掉）。
/// 总结页与历史详情页都走它。
Future<WorkoutSession?> getSession(SqlExecutor exec, String id) async {
  final row = await exec.first<Map<String, Object?>>(
    'SELECT $sessionColumns FROM session WHERE id = ?',
    [id],
  );
  return row == null ? null : toSession(SessionRow.fromMap(row));
}

/// 取当前进行中的训练。
///
/// 理论上同时只该有一条未结束的记录，但 App 被强杀可能留下残留，
/// 所以按开始时间倒序取最新的一条，**而不是断言唯一**。
///
/// `rowid DESC` 不能省：`started_at` 只有毫秒精度，同一毫秒建的两场会完全并列，
/// 此时 SQLite 按扫描顺序返回（先插入的在前），语义就反了。
Future<WorkoutSession?> getActiveSession(SqlExecutor exec) async {
  final row = await exec.first<Map<String, Object?>>(
    '''SELECT $sessionColumns FROM session
       WHERE finished_at IS NULL
       ORDER BY started_at DESC, rowid DESC
       LIMIT 1''',
  );
  return row == null ? null : toSession(SessionRow.fromMap(row));
}

/// 给训练写上结束时间，从此它出现在历史列表里。
///
/// 只写这一列，**不碰组记录** —— 训练结束时那些 `is_completed = 0` 的占位组
/// 就留在库里，靠这个标记被各处排除掉，不需要清理。
Future<void> finishSession(SqlExecutor exec, String id, int finishedAt) async {
  await exec.run('UPDATE session SET finished_at = ? WHERE id = ?', [finishedAt, id]);
}

/// 列出**已结束**的训练，最近的在前。
///
/// 「只列已结束」是刻意的：进行中的那一场归 [getActiveSession] 管，
/// `startNew` 复制上次动作组合时正是靠这个过滤，才不会把进行中的训练当成「上次」。
Future<List<WorkoutSession>> listSessions(SqlExecutor exec, int limit) async {
  final rows = await exec.all<Map<String, Object?>>(
    '''SELECT $sessionColumns FROM session
       WHERE finished_at IS NOT NULL
       ORDER BY started_at DESC, rowid DESC
       LIMIT ?''',
    [limit],
  );
  return rows.map((m) => toSession(SessionRow.fromMap(m))).toList();
}

/// 往训练里追加一个动作，`position` 取当前最大值 +1（第一个动作是 0）。
///
/// **不预建第一组** —— 那是 `ActiveSessionController.addExercise`（内部走
/// `_addExerciseWithFirstSet`）的职责，因为它还要顺带沿用上次的重量 / 次数。
/// 只调本函数的话，界面上的「完成这组」会因为没有待完成的组而毫无反应。
Future<SessionExercise> addExerciseToSession(
  SqlExecutor exec,
  String sessionId,
  String exerciseId,
) async {
  final row = await exec.first<Map<String, Object?>>(
    'SELECT MAX(position) + 1 AS next FROM session_exercise WHERE session_id = ?',
    [sessionId],
  );
  final position = (row?['next'] as int?) ?? 0;

  final se = SessionExercise(
    id: newId(),
    sessionId: sessionId,
    exerciseId: exerciseId,
    position: position,
    note: null,
  );

  await exec.run(
    '''INSERT INTO session_exercise (id, session_id, exercise_id, position, note)
       VALUES (?, ?, ?, ?, NULL)''',
    [se.id, sessionId, exerciseId, position],
  );

  return se;
}

/// 取一场训练里的动作，按 `position` 升序（即界面上的先后）。
Future<List<SessionExercise>> listSessionExercises(
  SqlExecutor exec,
  String sessionId,
) async {
  final rows = await exec.all<Map<String, Object?>>(
    '''SELECT $sessionExerciseColumns FROM session_exercise
       WHERE session_id = ?
       ORDER BY position ASC''',
    [sessionId],
  );
  return rows.map((m) => toSessionExercise(SessionExerciseRow.fromMap(m))).toList();
}

/// 找出这场训练里**最近有动作的那一组**所属的 `session_exercise`。
///
/// 用途是恢复「练到第几个动作」：`completed_at` 最大的那一组就是用户最后碰过的
/// 那组，它归属的动作就是当时停下的地方。训练里没有「当前动作」这个字段，
/// 但这件事推得出来，**不值得为它加一列**。
///
/// 正在休息时结论相同 —— `startRest` 就是对刚 `completeSet` 的同一组调用的。
///
/// `st.rowid DESC` 不能省，理由同 [getActiveSession]。
Future<String?> findLastActiveSessionExerciseId(
  SqlExecutor exec,
  String sessionId,
) async {
  final row = await exec.first<Map<String, Object?>>(
    '''SELECT se.id AS id
         FROM set_entry st
         JOIN session_exercise se ON se.id = st.session_exercise_id
        WHERE se.session_id = ?
          AND st.completed_at IS NOT NULL
        ORDER BY st.completed_at DESC, st.rowid DESC
        LIMIT 1''',
    [sessionId],
  );
  return row?['id'] as String?;
}
