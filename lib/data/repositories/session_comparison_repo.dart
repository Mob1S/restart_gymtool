import '../../domain/metrics.dart';
import '../../domain/session_comparison.dart';
import '../../domain/session_summary.dart';
import '../../domain/types.dart';
import '../db/sql_executor.dart';
import 'session_repo.dart';
import 'set_repo.dart';

/// One read statement selects and loads the previous session for every action.
/// Parent rows and their details stay intact; no flattened progression facts are
/// used for group counts. CTEs avoid a dependency on newer SQLite window APIs.
Future<List<ExerciseComparison>> loadSessionComparisons(
  SqlExecutor exec,
  SessionSummary current,
) async {
  if (current.session.finishedAt == null || current.exercises.isEmpty) {
    return const [];
  }
  final sessionAliases = sessionColumns
      .split(', ')
      .map((column) => 's.$column AS comparison_$column')
      .join(', ');
  final rows = await exec.all<Map<String, Object?>>(
    '''WITH candidates AS (
         SELECT DISTINCT se.exercise_id, s.id AS sid, s.started_at
           FROM session s
           JOIN session_exercise se ON se.session_id = s.id
           JOIN set_entry st ON st.session_exercise_id = se.id
          WHERE s.finished_at IS NOT NULL
            AND s.started_at < ?
            AND s.id <> ?
            AND st.is_completed = 1
            AND se.exercise_id IN (
              SELECT exercise_id FROM session_exercise WHERE session_id = ?
            )
       ), latest_starts AS (
         SELECT exercise_id, MAX(started_at) AS started_at
           FROM candidates
          GROUP BY exercise_id
       ), previous_sessions AS (
         SELECT c.exercise_id, MAX(c.sid) AS sid
           FROM candidates c
           JOIN latest_starts latest
             ON latest.exercise_id = c.exercise_id
            AND latest.started_at = c.started_at
          GROUP BY c.exercise_id
       )
       SELECT $sessionAliases, se.exercise_id, e.name AS exercise_name,
              $setColumnsPrefixed, sd.payload AS detail_payload
         FROM previous_sessions p
         JOIN session s ON s.id = p.sid
         JOIN session_exercise se
           ON se.session_id = s.id AND se.exercise_id = p.exercise_id
         JOIN set_entry st ON st.session_exercise_id = se.id
         LEFT JOIN exercise e ON e.id = se.exercise_id
         LEFT JOIN set_detail sd ON sd.id = st.id
        WHERE st.is_completed = 1
        ORDER BY s.started_at ASC, s.id ASC, se.position ASC, se.rowid ASC,
                 st.position ASC, st.rowid ASC''',
    [current.session.startedAt, current.session.id, current.session.id],
  );

  final sessions = <String, _HistorySession>{};
  for (final row in rows) {
    final id = row['comparison_id'] as String;
    final history = sessions.putIfAbsent(
      id,
      () => _HistorySession(
        toSession(
          SessionRow.fromMap({
            for (final column in sessionColumns.split(', '))
              column: row['comparison_$column'],
          }),
        ),
      ),
    );
    final occurrence = history.occurrences.putIfAbsent(
      row['session_exercise_id'] as String,
      () => _HistoryOccurrence(
        row['exercise_id'] as String,
        row['exercise_name'] as String? ?? '未知动作',
      ),
    );
    occurrence.sets.add(toSetEntry(SetRow.fromMap(row)));
  }

  return buildSessionComparisons(
    current,
    sessions.values.map((history) => history.toSummary()),
  );
}

class _HistorySession {
  final WorkoutSession session;
  final occurrences = <String, _HistoryOccurrence>{};
  _HistorySession(this.session);

  SessionSummary toSummary() {
    final exercises = [
      for (final occurrence in occurrences.values)
        ExerciseSummary(
          exerciseId: occurrence.exerciseId,
          exerciseName: occurrence.exerciseName,
          sets: List.unmodifiable(occurrence.sets),
        ),
    ];
    final sets = exercises.expand((exercise) => exercise.sets).toList();
    return SessionSummary(
      session: session,
      exercises: exercises,
      durationSeconds: sessionDurationSeconds(
        session.startedAt,
        session.finishedAt!,
      ),
      totalSets: sets.length,
      volumeLoad: recordedSetsVolume(sets),
    );
  }
}

class _HistoryOccurrence {
  final String exerciseId, exerciseName;
  final sets = <SetEntry>[];
  _HistoryOccurrence(this.exerciseId, this.exerciseName);
}
