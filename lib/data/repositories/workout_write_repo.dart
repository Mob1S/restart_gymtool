import '../../domain/backup_codec.dart';
import '../../domain/record_management.dart';
import '../../domain/types.dart';
import '../../domain/weight_value.dart';
import '../../domain/training_prescription.dart';
import 'set_detail_repo.dart';
import 'training_program_repo.dart';
import '../db/sql_executor.dart';
import 'backup_repo.dart';
import 'exercise_repo.dart';
import 'exercise_preferences_repo.dart';
import 'session_repo.dart';
import 'set_repo.dart';

Future<void> requireActiveWorkout(SqlExecutor tx, String id) async {
  final session = await getSession(tx, id);
  if (session == null || session.finishedAt != null) {
    throw const RecordManagementException('训练已变化，请重新载入');
  }
}

Future<SetEntry> requirePendingSet(
  SqlExecutor tx,
  String sessionId,
  String id,
) async {
  await requireActiveWorkout(tx, sessionId);
  final row = await tx.first<Map<String, Object?>>(
    'SELECT st.* FROM set_entry st JOIN session_exercise se ON se.id=st.session_exercise_id '
    'WHERE st.id=? AND se.session_id=? AND st.is_completed=0',
    [id, sessionId],
  );
  if (row == null) throw const RecordManagementException('当前组已变化，请重新载入');
  final pending = toSetEntry(SetRow.fromMap(row));
  final sets = await listSets(tx, pending.sessionExerciseId);
  if (sets.where((s) => !s.isCompleted).length != 1) {
    throw const RecordManagementException('当前组状态异常，请重新载入');
  }
  return pending;
}

Future<List<String>> _rests(SqlExecutor tx, String sessionId) async {
  final rows = await tx.all<Map<String, Object?>>(
    'SELECT st.id FROM set_entry st JOIN session_exercise se ON se.id=st.session_exercise_id '
    'WHERE se.session_id=? AND st.rest_started_at IS NOT NULL',
    [sessionId],
  );
  if (rows.length > 1) throw const RecordManagementException('休息状态异常，请重新载入');
  return rows.map((r) => r['id'] as String).toList();
}

Future<SessionExercise> addExerciseWithFirstSet(
  SqlExecutor tx,
  String sessionId,
  String exerciseId,
) async {
  final se = await addExerciseToSession(tx, sessionId, exerciseId);
  final preference = (await readExercisePreferences(tx, [
    exerciseId,
  ]))[exerciseId]!;
  final unit = preference.weightUnit;
  // A source reading from another unit is not an equipment setting. Search
  // completed sessions for the latest performance in this equipment's unit.
  final row = await tx.first<Map<String, Object?>>(
    'SELECT $setColumnsPrefixed FROM set_entry st '
    'JOIN session_exercise se ON se.id=st.session_exercise_id '
    'JOIN session s ON s.id=se.session_id '
    'WHERE se.exercise_id=? AND s.id<>? AND s.finished_at IS NOT NULL '
    'AND st.is_completed=1 AND COALESCE(st.source_unit,\'kg\')=? '
    'ORDER BY s.started_at DESC,s.rowid DESC,st.position ASC,st.rowid ASC LIMIT 1',
    [exerciseId, sessionId, unit.name],
  );
  final last = row == null ? null : toSetEntry(SetRow.fromMap(row));
  final reading =
      last?.equipmentWeight ??
      EquipmentWeight(
        DecimalReading.parse(unit == WeightUnit.kg ? '20' : '45'),
        unit,
      );
  await addSet(tx, se.id, reading.kilograms, last?.reps ?? 8, reading: reading);
  return se;
}

Future<void> completeWorkoutSet(
  SqlExecutor exec, {
  required String sessionId,
  required String pendingSetId,
  required double weight,
  required int reps,
  required int now,
  EquipmentWeight? reading,
  Effort? effort,
}) async {
  if (!weight.isFinite || weight < 0 || reps < 0) {
    throw const RecordManagementException('重量或次数无效');
  }
  final detail = await readSetDetail(exec, pendingSetId);
  if (detail.target?.isRestPause == true) {
    await recordWorkoutSegment(
      exec,
      sessionId: sessionId,
      setId: pendingSetId,
      reading: reading ?? EquipmentWeight.kg(weight),
      reps: reps,
      now: now,
      effort: effort,
    );
    return;
  }
  await exec.transaction((tx) async {
    final pending = await requirePendingSet(tx, sessionId, pendingSetId);
    final currentDetail = await readSetDetail(tx, pendingSetId);
    if (currentDetail.target?.isRestPause == true) {
      throw const RecordManagementException('当前组已变化，请重新载入');
    }
    if (effort != null || currentDetail.target != null) {
      await writeSetDetail(
        tx,
        pendingSetId,
        currentDetail.copyWith(effort: effort, clearEffort: effort == null),
      );
    }
    for (final id in await _rests(tx, sessionId)) {
      await endRest(tx, id, now);
    }
    await updateSetValues(tx, pendingSetId, weight, reps, reading: reading);
    await completeSet(tx, pendingSetId, now);
    await startRest(tx, pendingSetId, now);
    await addSet(tx, pending.sessionExerciseId, weight, reps, reading: reading);
    await installPendingTarget(
      tx,
      pending.sessionExerciseId,
      (currentDetail.targetIndex ?? pending.position) + 1,
    );
    encodeBackup(await readBackupSnapshot(tx, exportedAt: now));
  });
}

Future<void> beginWorkoutSet(
  SqlExecutor exec, {
  required String sessionId,
  required String pendingSetId,
  required int now,
}) => exec.transaction((tx) async {
  await requirePendingSet(tx, sessionId, pendingSetId);
  for (final id in await _rests(tx, sessionId)) {
    await endRest(tx, id, now);
  }
});

Future<void> finishActiveWorkout(
  SqlExecutor exec, {
  required String sessionId,
  required int now,
}) => exec.transaction((tx) async {
  await requireActiveWorkout(tx, sessionId);
  await finalizePartialSets(tx, sessionId: sessionId, now: now);
  for (final id in await _rests(tx, sessionId)) {
    await cancelRest(tx, id);
  }
  await finishSession(tx, sessionId, now);
});

Future<void> savePendingWeight(
  SqlExecutor exec, {
  required String sessionId,
  required String pendingSetId,
  required double weight,
  EquipmentWeight? reading,
}) async {
  if (!weight.isFinite || weight < 0) {
    throw const RecordManagementException('重量无效');
  }
  await exec.transaction((tx) async {
    await requirePendingSet(tx, sessionId, pendingSetId);
    final source = reading ?? EquipmentWeight.kg(weight);
    if ((source.kilograms - weight).abs() >
        (weight.abs() * 1e-12).clamp(1e-9, double.infinity)) {
      throw const RecordManagementException('器械读数与标准重量不一致');
    }
    final detail = await readSetDetail(tx, pendingSetId);
    if (detail.firstCompletedAt != null) {
      await writeSetDetail(
        tx,
        pendingSetId,
        detail.copyWith(pendingReading: source),
      );
      return;
    }
    await tx.run(
      'UPDATE set_entry SET weight=?,source_weight=?,source_unit=? WHERE id=? AND is_completed=0',
      [source.kilograms, source.amount.text, source.unit.name, pendingSetId],
    );
  });
}

Future<List<String>> addWorkoutExercises(
  SqlExecutor exec,
  String sessionId,
  List<String> exerciseIds,
) => exec.transaction((tx) async {
  await requireActiveWorkout(tx, sessionId);
  for (final id in exerciseIds) {
    final exercise = await getExercise(tx, id);
    if (exercise == null || exercise.isArchived) {
      throw const RecordManagementException('动作已变化，请重新选择');
    }
  }
  final result = <String>[];
  for (final id in exerciseIds.toSet()) {
    result.add((await addExerciseWithFirstSet(tx, sessionId, id)).id);
  }
  encodeBackup(await readBackupSnapshot(tx, exportedAt: 0));
  return result;
});
