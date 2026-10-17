import '../../domain/backup_codec.dart';
import '../../domain/exercise_preferences.dart';
import '../../domain/record_management.dart';
import '../../domain/weight_value.dart';
import '../db/sql_executor.dart';
import 'backup_repo.dart';
import 'exercise_preferences_repo.dart';
import 'set_repo.dart';
import 'workout_write_repo.dart';

/// Commits the pending reading and action settings atomically. A stale modal
/// cannot change either half after the current set or preference has changed.
Future<ExercisePreference> applyPendingWeightSettings(
  SqlExecutor exec, {
  required String sessionId,
  required String pendingSetId,
  required String exerciseId,
  required String expectedPreferenceToken,
  required EquipmentWeight reading,
  required DecimalReading kgStep,
  required DecimalReading lbStep,
  required bool showKgEquivalent,
  String? equipmentNote,
  bool? isFavorite,
}) => exec.transaction((tx) async {
  final pending = await requirePendingSet(tx, sessionId, pendingSetId);
  final owner = await tx.first<Map<String, Object?>>(
    'SELECT exercise_id FROM session_exercise WHERE id=?',
    [pending.sessionExerciseId],
  );
  if (owner?['exercise_id'] != exerciseId) {
    throw const RecordManagementException('当前动作已变化，请重新打开');
  }
  final current = (await readExercisePreferences(tx, [
    exerciseId,
  ]))[exerciseId]!;
  if (current.token != expectedPreferenceToken) {
    throw const RecordManagementException('动作偏好已变化，请重新打开后保存');
  }
  await writeExercisePreference(
    tx,
    ExercisePreference(
      exerciseId: exerciseId,
      weightUnit: reading.unit,
      kgStep: kgStep,
      lbStep: lbStep,
      showKgEquivalent: showKgEquivalent,
      equipmentNote: equipmentNote ?? current.equipmentNote,
      isFavorite: isFavorite ?? current.isFavorite,
      token: current.token,
    ),
  );
  await updateSetValues(
    tx,
    pendingSetId,
    reading.kilograms,
    pending.reps,
    reading: reading,
  );
  encodeBackup(await readBackupSnapshot(tx, exportedAt: 0));
  return (await readExercisePreferences(tx, [exerciseId]))[exerciseId]!;
});
