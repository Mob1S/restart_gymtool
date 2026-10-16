import 'types.dart';

enum WorkoutWriteResult {
  saved,
  savedNeedsReload,
  unchanged,
  busy,
  conflict,
  failed,
}

class CompletedSetEdit {
  final String sessionId;
  final SetEntry original;
  final String token;
  const CompletedSetEdit(this.sessionId, this.original, this.token);
}

class UndoSetPreview {
  final String sessionId, sessionExerciseId, setId, pendingSetId, token;
  const UndoSetPreview(
    this.sessionId,
    this.sessionExerciseId,
    this.setId,
    this.pendingSetId,
    this.token,
  );
}

class ExerciseReplacementPreview {
  final String sessionId,
      sourceSessionExerciseId,
      sourceExerciseId,
      targetExerciseId,
      sourceName,
      targetName,
      token;
  final int completedSets;
  const ExerciseReplacementPreview({
    required this.sessionId,
    required this.sourceSessionExerciseId,
    required this.sourceExerciseId,
    required this.targetExerciseId,
    required this.sourceName,
    required this.targetName,
    required this.completedSets,
    required this.token,
  });
}
