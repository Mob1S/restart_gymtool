import 'session_summary.dart';
import 'types.dart';

/// All completed occurrences of one stable exercise in a single session.
class SessionExerciseRecord {
  final WorkoutSession session;
  final List<ExerciseSummary> occurrences;

  const SessionExerciseRecord({
    required this.session,
    required this.occurrences,
  });

  int get logicalSetCount => occurrences.fold(
    0,
    (count, occurrence) =>
        count + occurrence.sets.where((set) => set.isCompleted).length,
  );

  double get volumeLoad =>
      recordedSetsVolume(occurrences.expand((occurrence) => occurrence.sets));
}

class ExerciseComparison {
  final String exerciseId, exerciseName;
  final SessionExerciseRecord current;
  final SessionExerciseRecord? previous;

  const ExerciseComparison({
    required this.exerciseId,
    required this.exerciseName,
    required this.current,
    this.previous,
  });
}

/// Compares actual records, without inferring progress from volume or load.
/// History order and the time of an import never decide the previous session.
List<ExerciseComparison> buildSessionComparisons(
  SessionSummary current,
  Iterable<SessionSummary> history,
) {
  if (current.session.finishedAt == null) return const [];
  final currentGroups = _completedOccurrences(current.exercises);
  if (currentGroups.isEmpty) return const [];

  final previous = <String, SessionExerciseRecord>{};
  for (final candidate in history) {
    final session = candidate.session;
    if (session.id == current.session.id ||
        session.finishedAt == null ||
        session.startedAt >= current.session.startedAt) {
      continue;
    }
    final groups = _completedOccurrences(candidate.exercises);
    for (final exerciseId in currentGroups.keys) {
      final occurrences = groups[exerciseId];
      if (occurrences == null) continue;
      final selected = previous[exerciseId]?.session;
      if (selected != null &&
          (session.startedAt < selected.startedAt ||
              (session.startedAt == selected.startedAt &&
                  session.id.compareTo(selected.id) <= 0))) {
        continue;
      }
      previous[exerciseId] = SessionExerciseRecord(
        session: session,
        occurrences: List.unmodifiable(occurrences),
      );
    }
  }

  return List.unmodifiable([
    for (final entry in currentGroups.entries)
      ExerciseComparison(
        exerciseId: entry.key,
        exerciseName: entry.value.first.exerciseName,
        current: SessionExerciseRecord(
          session: current.session,
          occurrences: List.unmodifiable(entry.value),
        ),
        previous: previous[entry.key],
      ),
  ]);
}

Map<String, List<ExerciseSummary>> _completedOccurrences(
  Iterable<ExerciseSummary> occurrences,
) {
  final groups = <String, List<ExerciseSummary>>{};
  for (final occurrence in occurrences) {
    final completed = occurrence.sets.where((set) => set.isCompleted).toList();
    if (completed.isEmpty) continue;
    (groups[occurrence.exerciseId] ??= []).add(
      completed.length == occurrence.sets.length
          ? occurrence
          : ExerciseSummary(
              exerciseId: occurrence.exerciseId,
              exerciseName: occurrence.exerciseName,
              sets: List.unmodifiable(completed),
            ),
    );
  }
  return groups;
}
