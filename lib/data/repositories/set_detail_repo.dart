import '../../domain/set_detail.dart';
import '../../domain/training_prescription.dart';
import '../../domain/weight_value.dart';
import '../../domain/record_management.dart';
import '../../domain/backup_codec.dart';
import '../db/sql_executor.dart';
import 'backup_repo.dart';
import 'set_repo.dart';
import 'workout_write_repo.dart';
import 'training_program_repo.dart';

Future<SetDetail> readSetDetail(SqlExecutor tx, String id) async {
  final row = await tx.first<Map<String, Object?>>(
    'SELECT payload FROM set_detail WHERE id=?',
    [id],
  );
  return row == null ? SetDetail() : SetDetail.decode(row['payload'] as String);
}

Future<void> writeSetDetail(SqlExecutor tx, String id, SetDetail detail) async {
  SetDetail.decode(detail.encode());
  await tx.run(
    'INSERT INTO set_detail(id,payload) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload',
    [id, detail.encode()],
  );
}

Future<void> recordWorkoutSegment(
  SqlExecutor exec, {
  required String sessionId,
  required String setId,
  required EquipmentWeight reading,
  required int reps,
  required int now,
  Effort? effort,
}) => exec.transaction((tx) async {
  if (reps < 0) throw const RecordManagementException('次数无效');
  effort?.validate();
  final pending = await requirePendingSet(tx, sessionId, setId);
  final d = await readSetDetail(tx, setId);
  if (d.target?.isRestPause != true) {
    throw const RecordManagementException('当前组不是分段组');
  }
  final rests = await tx.all<Map<String, Object?>>(
    'SELECT st.id FROM set_entry st JOIN session_exercise se ON se.id=st.session_exercise_id WHERE se.session_id=? AND st.rest_started_at IS NOT NULL',
    [sessionId],
  );
  if (rests.length > 1) throw const RecordManagementException('休息状态异常，请重新载入');
  for (final row in rests) {
    await endRest(tx, row['id'] as String, now);
  }
  SetDetail next;
  if (d.firstCompletedAt == null) {
    await updateSetValues(tx, setId, reading.kilograms, reps, reading: reading);
    next = d.copyWith(
      effort: effort,
      clearEffort: effort == null,
      firstCompletedAt: now,
      intraRestStartedAt: now,
      clearPending: true,
    );
  } else {
    if (d.currentSegment >= d.target!.segmentReps.length) {
      throw const RecordManagementException('分段已完成，请重新载入');
    }
    final pause =
        (((d.segmentStartedAt ?? now) -
                    (d.intraRestStartedAt ??
                        d.continuations.lastOrNull?.completedAt ??
                        d.firstCompletedAt ??
                        now)) /
                1000)
            .round()
            .clamp(0, 8640000000000000);
    next = d.copyWith(
      continuations: [
        ...d.continuations,
        RecordedSegment(
          reading: reading,
          reps: reps,
          completedAt: now,
          pauseSeconds: pause,
          effort: effort,
        ),
      ],
      intraRestStartedAt: now,
      clearPending: true,
      clearSegmentStart: true,
    );
  }
  final finished = next.continuations.length == next.target!.extraReps.length;
  if (finished) {
    next = next.copyWith(clearRest: true, clearSegmentStart: true);
    await completeSet(tx, setId, now);
    await startRest(tx, setId, now);
    await addSet(
      tx,
      pending.sessionExerciseId,
      reading.kilograms,
      reps,
      reading: reading,
    );
    await installPendingTarget(
      tx,
      pending.sessionExerciseId,
      (d.targetIndex ?? pending.position) + 1,
    );
  }
  await writeSetDetail(tx, setId, next);
  encodeBackup(await readBackupSnapshot(tx, exportedAt: now));
});
Future<void> endPartialSet(
  SqlExecutor exec, {
  required String sessionId,
  required String setId,
  required int now,
}) => exec.transaction((tx) async {
  final pending = await requirePendingSet(tx, sessionId, setId);
  final d = await readSetDetail(tx, setId);
  if (d.firstCompletedAt == null) {
    throw const RecordManagementException('还没有已完成分段');
  }
  await writeSetDetail(
    tx,
    setId,
    d.copyWith(
      endedEarly: true,
      clearRest: true,
      clearPending: true,
      clearSegmentStart: true,
    ),
  );
  await completeSet(tx, setId, now);
  await startRest(tx, setId, now);
  await addSet(
    tx,
    pending.sessionExerciseId,
    pending.weight,
    pending.reps,
    reading: pending.recordedWeight,
  );
  await installPendingTarget(
    tx,
    pending.sessionExerciseId,
    (d.targetIndex ?? pending.position) + 1,
  );
  encodeBackup(await readBackupSnapshot(tx, exportedAt: now));
});
Future<void> finalizePartialSets(
  SqlExecutor tx, {
  String? sessionId,
  String? sessionExerciseId,
  required int now,
}) async {
  final rows = await tx.all<Map<String, Object?>>(
    'SELECT st.id,sd.payload FROM set_entry st JOIN session_exercise se ON se.id=st.session_exercise_id JOIN set_detail sd ON sd.id=st.id WHERE st.is_completed=0 AND ${sessionExerciseId != null ? 'se.id=?' : 'se.session_id=?'}',
    [sessionExerciseId ?? sessionId],
  );
  for (final row in rows) {
    final d = SetDetail.decode(row['payload'] as String);
    if (d.firstCompletedAt == null) continue;
    await completeSet(tx, row['id'] as String, now);
    await writeSetDetail(
      tx,
      row['id'] as String,
      d.copyWith(
        endedEarly: true,
        clearRest: true,
        clearPending: true,
        clearSegmentStart: true,
      ),
    );
  }
}

Future<void> beginWorkoutSegment(
  SqlExecutor exec, {
  required String sessionId,
  required String setId,
  required int now,
}) => exec.transaction((tx) async {
  await requirePendingSet(tx, sessionId, setId);
  final d = await readSetDetail(tx, setId);
  if (d.firstCompletedAt == null ||
      d.intraRestStartedAt == null ||
      d.segmentStartedAt != null ||
      d.target?.isRestPause != true) {
    throw const RecordManagementException('当前分段已变化，请重新载入');
  }
  await writeSetDetail(
    tx,
    setId,
    d.copyWith(segmentStartedAt: now, clearRest: true),
  );
  encodeBackup(await readBackupSnapshot(tx, exportedAt: now));
});
