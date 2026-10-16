import '../../domain/backup_codec.dart';
import '../../domain/record_management.dart';
import '../../domain/workout_edit.dart';
import '../db/sql_executor.dart';
import 'exercise_repo.dart';
import 'session_repo.dart';
import 'set_repo.dart';
import 'record_management_repo.dart';
import 'workout_edit_repo.dart';
import 'workout_write_repo.dart';
import 'backup_repo.dart';

Future<ExerciseReplacementPreview> _inspect(
  SqlExecutor tx,
  String sessionId,
  String sourceId,
  String targetId,
) async {
  final token = await requireWorkoutToken(tx, sessionId);
  final source = (await listSessionExercises(
    tx,
    sessionId,
  )).where((e) => e.id == sourceId).firstOrNull;
  final target = await getExercise(tx, targetId);
  if (source == null || target == null || target.isArchived) {
    throw const RecordManagementException('动作已变化，请重新选择');
  }
  final sets = await listSets(tx, sourceId);
  if (sets.where((s) => !s.isCompleted).length != 1) {
    throw const RecordManagementException('原动作已变化，请重新选择');
  }
  return ExerciseReplacementPreview(
    sessionId: sessionId,
    sourceSessionExerciseId: sourceId,
    sourceExerciseId: source.exerciseId,
    targetExerciseId: targetId,
    sourceName: (await getExercise(tx, source.exerciseId))?.name ?? '动作',
    targetName: target.name,
    completedSets: sets.where((s) => s.isCompleted).length,
    token: token,
  );
}

Future<ExerciseReplacementPreview> inspectExerciseReplacement(
  SqlExecutor exec,
  String sessionId,
  String sourceSessionExerciseId,
  String targetExerciseId,
) => exec.transaction(
  (tx) => _inspect(tx, sessionId, sourceSessionExerciseId, targetExerciseId),
);
Future<String> replaceWorkoutExercise(
  SqlExecutor exec,
  ExerciseReplacementPreview preview,
) => exec.transaction((tx) async {
  final current = await _inspect(
    tx,
    preview.sessionId,
    preview.sourceSessionExerciseId,
    preview.targetExerciseId,
  );
  if (current.token != preview.token) {
    throw const RecordManagementException('训练已变化，请重新选择替换动作');
  }
  if (current.sourceExerciseId == current.targetExerciseId) {
    return current.sourceSessionExerciseId;
  }
  final original = await listSessionExercises(tx, current.sessionId);
  final sourceId = current.sourceSessionExerciseId;
  final added = await addExerciseWithFirstSet(
    tx,
    current.sessionId,
    current.targetExerciseId,
  );
  final order = <String>[];
  for (final e in original) {
    if (e.id != sourceId) {
      order.add(e.id);
      continue;
    }
    if (current.completedSets > 0) {
      await retainCompletedSets(tx, sourceId);
      order.add(sourceId);
    } else {
      await tx.run('DELETE FROM session_exercise WHERE id=?', [sourceId]);
    }
    order.add(added.id);
  }
  for (var i = 0; i < order.length; i++) {
    await tx.run('UPDATE session_exercise SET position=? WHERE id=?', [
      i,
      order[i],
    ]);
  }
  encodeBackup(await readBackupSnapshot(tx, exportedAt: 0));
  return added.id;
});
