import '../../domain/weight_value.dart';
import '../../domain/workout_csv_export.dart';
import '../../domain/set_detail.dart';
import '../db/sql_executor.dart';

Future<List<WorkoutCsvRow>> readWorkoutCsvRows(
  SqlExecutor exec, {
  int? startInclusive,
  int? endExclusive,
}) async {
  final rows = await exec.all<Map<String, Object?>>(
    '''SELECT s.id AS session_id, s.name AS session_name,
      s.started_at, s.finished_at, e.name AS exercise_name,
      st.id AS set_id, st.position, st.weight, st.source_weight, st.source_unit, st.reps, sd.payload AS detail_payload
      FROM session s
      JOIN session_exercise se ON se.session_id=s.id
      JOIN exercise e ON e.id=se.exercise_id
      JOIN set_entry st ON st.session_exercise_id=se.id
      LEFT JOIN set_detail sd ON sd.id=st.id
      WHERE s.finished_at IS NOT NULL AND st.is_completed=1
      ${startInclusive == null ? '' : 'AND s.started_at>=?'}
      ${endExclusive == null ? '' : 'AND s.started_at<?'}
      ORDER BY s.started_at DESC, s.rowid DESC,
        se.position ASC, se.rowid ASC, st.position ASC, st.rowid ASC''',
    [?startInclusive, ?endExclusive],
  );
  return [
    for (final row in rows)
      WorkoutCsvRow(
        groupId: row['set_id'] as String,
        detail: row['detail_payload'] == null
            ? null
            : SetDetail.decode(row['detail_payload'] as String),
        sessionId: row['session_id'] as String,
        sessionName: row['session_name'] as String?,
        startedAt: row['started_at'] as int,
        finishedAt: row['finished_at'] as int,
        exerciseName: row['exercise_name'] as String,
        setPosition: row['position'] as int,
        reading: row['source_weight'] == null
            ? EquipmentWeight.kg((row['weight'] as num).toDouble())
            : EquipmentWeight(
                DecimalReading.parse(row['source_weight'] as String),
                WeightUnit.values.byName(row['source_unit'] as String),
              ),
        reps: row['reps'] as int,
      ),
  ];
}
