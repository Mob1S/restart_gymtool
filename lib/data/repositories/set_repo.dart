import '../../domain/types.dart';
import '../db/sql_executor.dart';
import '../ids.dart';

/// `set_entry` 表的原始行。
///
/// **字段用 camelCase，列名（map 的键）用 snake_case** —— 两者的对应关系由
/// [SetRow.fromMap] 一处显式写出（约定见 Global Constraints）。
class SetRow {
  final String id;
  final String sessionExerciseId;
  final int position;
  final double weight;
  final int reps;
  final int isCompleted;
  final int? restSeconds;
  final int? restStartedAt;
  final int? completedAt;

  const SetRow({
    required this.id,
    required this.sessionExerciseId,
    required this.position,
    required this.weight,
    required this.reps,
    required this.isCompleted,
    this.restSeconds,
    this.restStartedAt,
    this.completedAt,
  });

  factory SetRow.fromMap(Map<String, Object?> m) => SetRow(
    id: m['id'] as String,
    sessionExerciseId: m['session_exercise_id'] as String,
    position: m['position'] as int,
    weight: (m['weight'] as num).toDouble(),
    reps: m['reps'] as int,
    isCompleted: m['is_completed'] as int,
    restSeconds: m['rest_seconds'] as int?,
    restStartedAt: m['rest_started_at'] as int?,
    completedAt: m['completed_at'] as int?,
  );
}

/// `is_completed` 的 0/1 在这里还原成布尔。
SetEntry toSetEntry(SetRow row) => SetEntry(
  id: row.id,
  sessionExerciseId: row.sessionExerciseId,
  position: row.position,
  weight: row.weight,
  reps: row.reps,
  isCompleted: row.isCompleted == 1,
  restSeconds: row.restSeconds,
  restStartedAt: row.restStartedAt,
  completedAt: row.completedAt,
);

const String setColumns =
    'id, session_exercise_id, position, weight, reps, is_completed, rest_seconds, rest_started_at, completed_at';

/// 与 [setColumns] 同一组列，但带 `st.` 前缀。
///
/// `set_entry` 与 `session_exercise` 都有 `id` 和 `position`，凡是 JOIN 了
/// `session_exercise` 的查询都必须用带前缀的版本，否则 SQLite 直接报
/// `ambiguous column name: id`（实测：prepare 阶段就抛，不是取数阶段）。
const String setColumnsPrefixed =
    'st.id, st.session_exercise_id, st.position, st.weight, st.reps, st.is_completed, st.rest_seconds, st.rest_started_at, st.completed_at';

/// 追加一组，`position` 取当前最大值 +1（第一组是 0）。
///
/// 新建出来的组**一律未完成** —— 它是界面上的「下一组」占位。
/// 「完成即落盘」的两步（[updateSetValues] → [completeSet]）发生在用户点完成时。
///
/// [sessionExerciseId] 是 **`session_exercise.id`，不是 `exercise.id`**。
Future<SetEntry> addSet(
  SqlExecutor exec,
  String sessionExerciseId,
  double weight,
  int reps,
) async {
  final row = await exec.first<Map<String, Object?>>(
    'SELECT MAX(position) + 1 AS next FROM set_entry WHERE session_exercise_id = ?',
    [sessionExerciseId],
  );
  final position = (row?['next'] as int?) ?? 0;

  final set = SetEntry(
    id: newId(),
    sessionExerciseId: sessionExerciseId,
    position: position,
    weight: weight,
    reps: reps,
    isCompleted: false,
  );

  await exec.run(
    '''INSERT INTO set_entry
         (id, session_exercise_id, position, weight, reps, is_completed, rest_seconds, rest_started_at, completed_at)
       VALUES (?, ?, ?, ?, ?, 0, NULL, NULL, NULL)''',
    [set.id, sessionExerciseId, position, weight, reps],
  );

  return set;
}

/// 取某个动作（在这一场里）的全部组，**含未完成的占位组** ——
/// 界面正需要那条占位来确定「当前该记哪一组」。
Future<List<SetEntry>> listSets(
  SqlExecutor exec,
  String sessionExerciseId,
) async {
  final rows = await exec.all<Map<String, Object?>>(
    '''SELECT $setColumns FROM set_entry
       WHERE session_exercise_id = ?
       ORDER BY position ASC''',
    [sessionExerciseId],
  );
  return rows.map((m) => toSetEntry(SetRow.fromMap(m))).toList();
}

/// 改写某一组的重量与次数。
///
/// 记录界面在「完成这一组」时会**先**把用户当前填的数值写进来，**再**标记完成
/// —— 顺序反过来的话，中途失败就会留下一条「已完成但数值是旧的」的记录。
Future<void> updateSetValues(
  SqlExecutor exec,
  String setId,
  double weight,
  int reps,
) async {
  await exec.run('UPDATE set_entry SET weight = ?, reps = ? WHERE id = ?', [
    weight,
    reps,
    setId,
  ]);
}

/// 标记一组已完成。**这一步必须立刻落盘** —— 训练记录的全部价值就在于不丢，
/// 不能等训练结束再统一保存。
///
/// [completedAt] 由调用方传入，与休息计时共用同一个 now，
/// 保证「完成时刻」和「休息开始时刻」不差毫秒。
Future<void> completeSet(
  SqlExecutor exec,
  String setId,
  int completedAt,
) async {
  await exec.run(
    'UPDATE set_entry SET is_completed = 1, completed_at = ? WHERE id = ?',
    [completedAt, setId],
  );
}

/// 开始休息计时：**只记时间戳**，之后用「现在 − 这个时间戳」算时长。
Future<void> startRest(SqlExecutor exec, String setId, int at) async {
  await exec.run('UPDATE set_entry SET rest_started_at = ? WHERE id = ?', [
    at,
    setId,
  ]);
}

/// 结束休息计时，写入这段休息的秒数。
///
/// **必须基于 `rest_started_at` 做时间戳相减，而不是用计数器累加** ——
/// App 被系统挂起后计数器会停，时间戳不会。旧项目真机实测：息屏前 `18:20`，
/// 息屏 35 秒后 `19:01`（Δ41 秒 vs 实测等待 40 秒，吻合）。
///
/// 该组本来就没在休息时**静默返回**（不写、不抛）——
/// 界面重复点「开始下一组」不会留下脏数据。
Future<void> endRest(SqlExecutor exec, String setId, int at) async {
  final row = await exec.first<Map<String, Object?>>(
    'SELECT rest_started_at FROM set_entry WHERE id = ?',
    [setId],
  );
  final startedAt = row?['rest_started_at'] as int?;
  if (row == null || startedAt == null) return;

  final seconds = ((at - startedAt) / 1000).round();
  await exec.run(
    'UPDATE set_entry SET rest_seconds = ?, rest_started_at = NULL WHERE id = ?',
    [seconds < 0 ? 0 : seconds, setId],
  );
}

/// 放弃一段休息：清掉 `rest_started_at`，**且不写入 `rest_seconds`**。
///
/// 用于「这段休息跑了太久，显然是忘了按开始下一组」的情况。它和 [endRest]
/// 的区别是刻意的：**那种时长不是真实休息，不该作为数据留下来** ——
/// 休息建议规则要算平均休息时长，一条 8 小时的记录足以把平均值彻底带偏。
Future<void> cancelRest(SqlExecutor exec, String setId) async {
  await exec.run('UPDATE set_entry SET rest_started_at = NULL WHERE id = ?', [
    setId,
  ]);
}

/// 取某个动作在**更早的某一次训练**里的完成组，用于显示「上次练了多少」。
///
/// 只取最近一次有该动作的训练：更早的数据对「这次该加多少」没有参考价值，
/// 混在一起反而会干扰。
///
/// **`s.rowid DESC` 这个并列项不能省。** `started_at` 只有毫秒精度，两场训练
/// 完全可能落在同一毫秒里；此时只写 `ORDER BY s.started_at DESC`，SQLite 会按
/// 扫描顺序返回，也就是**先插入的那一场** —— 正是「更早」的那一场，
/// 语义整个反了。
///
/// 从没练过时返回**空数组**，调用方据此回退到默认重量。
Future<List<SetEntry>> getLastPerformance(
  SqlExecutor exec,
  String exerciseId,
  String beforeSessionId,
) async {
  final previous = await exec.first<Map<String, Object?>>(
    '''SELECT s.id AS id
         FROM session s
         JOIN session_exercise se ON se.session_id = s.id
        WHERE se.exercise_id = ?
          AND s.id <> ?
          AND s.finished_at IS NOT NULL
        ORDER BY s.started_at DESC, s.rowid DESC
        LIMIT 1''',
    [exerciseId, beforeSessionId],
  );

  final previousId = previous?['id'] as String?;
  if (previousId == null) return [];

  final rows = await exec.all<Map<String, Object?>>(
    '''SELECT $setColumnsPrefixed
         FROM set_entry st
         JOIN session_exercise se ON se.id = st.session_exercise_id
        WHERE se.exercise_id = ?
          AND se.session_id = ?
          AND st.is_completed = 1
        ORDER BY st.position ASC''',
    [exerciseId, previousId],
  );

  return rows.map((m) => toSetEntry(SetRow.fromMap(m))).toList();
}
