import '../../domain/metrics.dart';
import '../../domain/types.dart';
import '../../domain/local_date.dart';
import '../../domain/set_detail.dart';
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
  final String? planId;
  final String? planNameSnapshot;
  final String? dayNameSnapshot;
  final String origin;

  const SessionRow({
    required this.id,
    this.name,
    required this.startedAt,
    this.finishedAt,
    this.note,
    this.templateId,
    this.planId,
    this.planNameSnapshot,
    this.dayNameSnapshot,
    this.origin = 'legacy',
  });

  factory SessionRow.fromMap(Map<String, Object?> m) => SessionRow(
    id: m['id'] as String,
    name: m['name'] as String?,
    startedAt: m['started_at'] as int,
    finishedAt: m['finished_at'] as int?,
    note: m['note'] as String?,
    templateId: m['template_id'] as String?,
    planId: m['plan_id'] as String?,
    planNameSnapshot: m['plan_name_snapshot'] as String?,
    dayNameSnapshot: m['day_name_snapshot'] as String?,
    origin: m['origin'] as String? ?? 'legacy',
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

  factory SessionExerciseRow.fromMap(Map<String, Object?> m) =>
      SessionExerciseRow(
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
  planId: row.planId,
  planNameSnapshot: row.planNameSnapshot,
  dayNameSnapshot: row.dayNameSnapshot,
  origin: row.origin,
);

SessionExercise toSessionExercise(SessionExerciseRow row) => SessionExercise(
  id: row.id,
  sessionId: row.sessionId,
  exerciseId: row.exerciseId,
  position: row.position,
  note: row.note,
);

const String sessionColumns =
    'id, name, started_at, finished_at, note, template_id, plan_id, plan_name_snapshot, day_name_snapshot, origin';
const String sessionExerciseColumns =
    'id, session_id, exercise_id, position, note';

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
  String? planId,
  String? planNameSnapshot,
  String? dayNameSnapshot,
  String origin = 'live',
}) async {
  final session = WorkoutSession(
    id: newId(),
    name: name,
    startedAt: DateTime.now().millisecondsSinceEpoch,
    finishedAt: null,
    note: null,
    templateId: templateId,
    planId: planId,
    planNameSnapshot: planNameSnapshot,
    dayNameSnapshot: dayNameSnapshot,
    origin: origin,
  );
  await exec.run(
    'INSERT INTO session (id, name, started_at, finished_at, note, template_id, plan_id, plan_name_snapshot, day_name_snapshot, origin) VALUES (?, ?, ?, NULL, NULL, ?, ?, ?, ?, ?)',
    [
      session.id,
      session.name,
      session.startedAt,
      session.templateId,
      planId,
      planNameSnapshot,
      dayNameSnapshot,
      origin,
    ],
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
  await exec.run('UPDATE session SET finished_at = ? WHERE id = ?', [
    finishedAt,
    id,
  ]);
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
       ORDER BY position ASC, rowid ASC''',
    [sessionId],
  );
  return rows
      .map((m) => toSessionExercise(SessionExerciseRow.fromMap(m)))
      .toList();
}

Future<String?> findLatestTemplateId(SqlExecutor exec) async {
  final row = await exec.first<Map<String, Object?>>(
    'SELECT template_id FROM session WHERE finished_at IS NOT NULL AND template_id IS NOT NULL ORDER BY started_at DESC,rowid DESC LIMIT 1',
  );
  return row?['template_id'] as String?;
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
  final rows = await exec.all<Map<String, Object?>>(
    '''SELECT se.id AS id, st.completed_at, sd.payload
         FROM set_entry st
         JOIN session_exercise se ON se.id = st.session_exercise_id
         LEFT JOIN set_detail sd ON sd.id=st.id
        WHERE se.session_id = ?
          AND (st.completed_at IS NOT NULL OR sd.id IS NOT NULL)
        ORDER BY st.rowid DESC''',
    [sessionId],
  );
  String? latestId;
  var latestAt = -1;
  for (final row in rows) {
    final detail = row['payload'] == null
        ? null
        : SetDetail.decode(row['payload'] as String);
    final at =
        row['completed_at'] as int? ??
        detail?.segmentStartedAt ??
        detail?.continuations.lastOrNull?.completedAt ??
        detail?.firstCompletedAt;
    if (at != null && at > latestAt) {
      latestAt = at;
      latestId = row['id'] as String;
    }
  }
  return latestId;
}

/// 历史列表的一行：一场已结束训练 + 两个聚合数。
///
/// 组数与容量由 [listSessionSummaries] 的 SQL 一并算出，**不是**拿到训练后再
/// 逐个回库补的 —— 那是 N+1，见那个函数上的说明。
class SessionSummaryRow {
  final WorkoutSession session;

  /// 时长（秒）。口径与 Phase 1 总结页**同一个算法**：
  /// `((finishedAt - startedAt) / 1000).round()`（`summary_page.dart`）。
  /// 两处各算各的话，同一场训练在总结页与历史行上会显示不同的分钟数。
  final int durationSeconds;

  /// 已完成的组数。占位组（`is_completed = 0`）不算。
  final int setCount;

  /// 总容量 Σ(重量 × 次数)，口径同 `domain/metrics.dart` 的 `totalVolumeLoad`：
  /// 只累加已完成的组。
  final double volumeLoad;

  const SessionSummaryRow({
    required this.session,
    required this.durationSeconds,
    required this.setCount,
    required this.volumeLoad,
  });

  factory SessionSummaryRow.fromMap(Map<String, Object?> m) {
    final session = toSession(SessionRow.fromMap(m));
    return SessionSummaryRow(
      session: session,
      // 查询只取已结束的训练，`finished_at` 必非空。这里用 `!` 是刻意的：
      // 真取到 null 说明 WHERE 被改坏了，应当**当场抛**而不是静默算成 0 秒
      // —— 数字悄悄写歪是这一层最难发现的一类错。
      durationSeconds: sessionDurationSeconds(
        session.startedAt,
        session.finishedAt!,
      ),
      setCount: m['set_count'] as int,
      // 不能写 `as double`：0 组时 COALESCE 给的是**整数** 0，FFI 后端原样
      // 返回 int，`as double` 会抛。经 num 转一道，两种数字类型都收得住。
      volumeLoad: (m['volume_load'] as num).toDouble(),
    );
  }
}

/// 历史列表：**一条聚合查询**，不是「先查训练、再逐个查组」。
///
/// 后者是 N+1：列表里 200 场就是 201 条 SQL，在手机上肉眼可见地卡
/// （旧项目 sessionRepo 的注释写明过这一条，规格 §3.1 引它作为取数纪律）。
/// 代价是这一条 SQL 同时承担过滤、聚合、排序三件事 —— 改它之前先读完下面几条。
///
/// **两个 `LEFT JOIN` 都不能改成 `JOIN`**：一个动作都没加就结束的训练（0 组）
/// 必须仍然出现在历史里，显示「0 组 · 0 kg」。内连接会让它**凭空消失**，
/// 而用户会读成「那场训练没记上」。
///
/// **`COALESCE(SUM(...), 0)` 不能省**：0 组时 `SUM` 返回 `NULL` 而不是 0，
/// 去掉它界面会显示「null kg」（准确地说，是在 [SessionSummaryRow.fromMap]
/// 的类型转换处抛异常）。
///
/// `rowid DESC` 兜底的理由同 [getActiveSession]：`started_at` 只有毫秒精度，
/// 同毫秒的两场会完全并列，不兜底就按扫描顺序返回，语义反了。
///
/// SELECT 里带上 `s.note` / `s.template_id`（计划里只列了四列）：行里内嵌的
/// 是完整的 [WorkoutSession]，缺列时 `SessionRow.fromMap` 会把它们**静默填
/// null** —— 将来谁从这一行读 `templateId` 去推计划轮转，就会静默算错。
Future<List<SessionSummaryRow>> listSessionSummaries(
  SqlExecutor exec, {
  LocalDate? date,
}) async {
  final rows = await exec.all<Map<String, Object?>>(
    '''SELECT s.id, s.name, s.started_at, s.finished_at, s.note, s.template_id,
              s.plan_id, s.plan_name_snapshot, s.day_name_snapshot, s.origin,
              COUNT(st.id)                          AS set_count,
              COALESCE(SUM(st.weight * st.reps), 0) AS volume_load
         FROM session s
         LEFT JOIN session_exercise se ON se.session_id = s.id
         LEFT JOIN set_entry st ON st.session_exercise_id = se.id
                               AND st.is_completed = 1
        WHERE s.finished_at IS NOT NULL
        ${date == null ? '' : 'AND s.started_at>=? AND s.started_at<?'}
        GROUP BY s.id
        ORDER BY s.started_at DESC, s.rowid DESC''',
    date == null
        ? null
        : [
            date.start.millisecondsSinceEpoch,
            date.nextStart.millisecondsSinceEpoch,
          ],
  );
  final details = await exec.all<Map<String, Object?>>(
    '''SELECT se.session_id, sd.payload FROM set_detail sd
      JOIN set_entry st ON st.id=sd.id
      JOIN session_exercise se ON se.id=st.session_exercise_id
      JOIN session s ON s.id=se.session_id
      WHERE st.is_completed=1 AND s.finished_at IS NOT NULL
      ${date == null ? '' : 'AND s.started_at>=? AND s.started_at<?'}''',
    date == null
        ? null
        : [
            date.start.millisecondsSinceEpoch,
            date.nextStart.millisecondsSinceEpoch,
          ],
  );
  final extras = <String, double>{};
  for (final row in details) {
    final id = row['session_id'] as String;
    extras[id] =
        (extras[id] ?? 0) +
        SetDetail.decode(row['payload'] as String).extraVolume;
  }
  return [
    for (final row in rows)
      SessionSummaryRow.fromMap({
        ...row,
        'volume_load':
            (row['volume_load'] as num).toDouble() + (extras[row['id']] ?? 0),
      }),
  ];
}

Future<Set<String>> listCompletedTrainingDates(
  SqlExecutor exec,
  LocalDate month,
) async {
  final first = DateTime(month.year, month.month);
  final next = DateTime(month.year, month.month + 1);
  final rows = await exec.all<Map<String, Object?>>(
    'SELECT started_at FROM session WHERE finished_at IS NOT NULL '
    'AND started_at>=? AND started_at<?',
    [first.millisecondsSinceEpoch, next.millisecondsSinceEpoch],
  );
  return {
    for (final row in rows)
      LocalDate.fromDateTime(
        DateTime.fromMillisecondsSinceEpoch(row['started_at'] as int),
      ).key,
  };
}
