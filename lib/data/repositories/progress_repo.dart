import '../../domain/progress.dart';
import '../../domain/set_detail.dart';
import '../db/sql_executor.dart';

/// 三表 JOIN 查出来的原始行。
///
/// **字段用 camelCase，列名（map 的键）用 snake_case** —— 两者的对应关系由
/// [SetFactRow.fromMap] 一处显式写出（约定见 session_repo.dart）。
class SetFactRow {
  final String exerciseId;
  final String sessionId;
  final int sessionStartedAt;
  final double weight;
  final int reps;

  const SetFactRow({
    required this.exerciseId,
    required this.sessionId,
    required this.sessionStartedAt,
    required this.weight,
    required this.reps,
  });

  factory SetFactRow.fromMap(Map<String, Object?> m) => SetFactRow(
    exerciseId: m['exercise_id'] as String,
    sessionId: m['session_id'] as String,
    sessionStartedAt: m['session_started_at'] as int,
    // 与 set_repo 的 SetRow 同款：weight 先收 num 再转 double，
    // 同一种列在两个仓储里不该有两种写法。
    weight: (m['weight'] as num).toDouble(),
    reps: m['reps'] as int,
  );
}

SetFact toSetFact(SetFactRow row) => SetFact(
  exerciseId: row.exerciseId,
  sessionId: row.sessionId,
  sessionStartedAt: row.sessionStartedAt,
  weight: row.weight,
  reps: row.reps,
);

/// 取**所有**已完成组的原始事实（跨全部训练、全部动作）。
///
/// 一条 SQL 解决动作列表 + 动作详情 + 迷你走势三处，之后全在 Dart 里分组。
/// **不按动作逐个查** —— 那是 N+1，在手机上会肉眼可见地卡
/// （旧项目 sessionRepo 的注释里写明了这一条）。
///
/// 两道过滤都是语义，不是优化：
/// - `st.is_completed = 1` —— 占位组是界面上的「下一组」，用户还没做过它；
/// - `s.finished_at IS NOT NULL` —— 进行中的那一场还在变。曲线回答的是
///   「比上一次强了吗」，把正在录的这一场也算进去，末点会在用户眼前来回跳。
///
/// 排序给出**确定的返回顺序**（分组与排序归 `buildSessionPoints`，它不依赖
/// 输入顺序）。两个 `rowid` 兜底不能省：`started_at` 只有毫秒精度，同一毫秒
/// 开的两场完全并列，只按 `started_at` 排时顺序由 SQLite 的扫描顺序决定 ——
/// 同一份数据换一次查询计划就换一种顺序。理由与 session_repo 的几处一致。
Future<List<SetFact>> listAllCompletedSetFacts(SqlExecutor exec) async {
  final rows = await exec.all<Map<String, Object?>>(
    '''SELECT se.exercise_id AS exercise_id,
              s.id           AS session_id,
              s.started_at   AS session_started_at,
              st.weight      AS weight,
              st.reps        AS reps, sd.payload AS detail_payload
         FROM set_entry st
         JOIN session_exercise se ON se.id = st.session_exercise_id
         JOIN session s           ON s.id  = se.session_id
         LEFT JOIN set_detail sd ON sd.id = st.id
        WHERE st.is_completed = 1
          AND s.finished_at IS NOT NULL
        ORDER BY s.started_at ASC, s.rowid ASC, se.position ASC, st.rowid ASC''',
  );
  return [for (final m in rows) ..._facts(m)];
}

List<SetFact> _facts(Map<String, Object?> row) {
  final original = toSetFact(SetFactRow.fromMap(row));
  final detail = row['detail_payload'] == null
      ? null
      : SetDetail.decode(row['detail_payload'] as String);
  SetFact fact(double weight, int reps, bool eligible) => SetFact(
    exerciseId: original.exerciseId,
    sessionId: original.sessionId,
    sessionStartedAt: original.sessionStartedAt,
    weight: weight,
    reps: reps,
    e1rmEligible: eligible,
  );
  return [
    fact(
      original.weight,
      original.reps,
      detail?.isRestPause != true && detail?.role != 'warmup',
    ),
    for (final segment in detail?.continuations ?? <RecordedSegment>[])
      fact(segment.reading.kilograms, segment.reps, false),
  ];
}
