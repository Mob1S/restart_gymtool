import '../../domain/backup_codec.dart';
import '../../domain/record_management.dart';
import '../../domain/types.dart';
import '../db/sql_executor.dart';
import 'backup_repo.dart';
import 'exercise_repo.dart';
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
  final last = await getLastPerformance(tx, exerciseId, sessionId);
  await addSet(
    tx,
    se.id,
    last.isEmpty ? 20 : last.first.weight,
    last.isEmpty ? 8 : last.first.reps,
  );
  return se;
}

Future<void> completeWorkoutSet(
  SqlExecutor exec, {
  required String sessionId,
  required String pendingSetId,
  required double weight,
  required int reps,
  required int now,
}) async {
  if (!weight.isFinite || weight < 0 || reps < 0) {
    throw const RecordManagementException('重量或次数无效');
  }
  await exec.transaction((tx) async {
    final pending = await requirePendingSet(tx, sessionId, pendingSetId);
    for (final id in await _rests(tx, sessionId)) {
      await endRest(tx, id, now);
    }
    await updateSetValues(tx, pendingSetId, weight, reps);
    await completeSet(tx, pendingSetId, now);
    await startRest(tx, pendingSetId, now);
    await addSet(tx, pending.sessionExerciseId, weight, reps);
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
}) async {
  if (!weight.isFinite || weight < 0) {
    throw const RecordManagementException('重量无效');
  }
  await exec.transaction((tx) async {
    await requirePendingSet(tx, sessionId, pendingSetId);
    await tx.run(
      'UPDATE set_entry SET weight=? WHERE id=? AND is_completed=0',
      [weight, pendingSetId],
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
