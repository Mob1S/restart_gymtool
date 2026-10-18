import '../../domain/record_management.dart';
import '../../domain/workout_edit.dart';
import '../../domain/weight_value.dart';
import '../../domain/rest.dart';
import '../db/sql_executor.dart';
import 'record_management_repo.dart';
import 'set_repo.dart';
import 'set_detail_repo.dart';
import 'backup_repo.dart';
import '../../domain/backup_codec.dart';
import '../../domain/set_detail.dart';

Future<String> requireWorkoutToken(
  SqlExecutor tx,
  String sessionId, [
  String? expected,
]) async {
  final snapshot = await readSessionDeletion(tx, sessionId);
  if (snapshot == null ||
      snapshot.session.finishedAt != null ||
      (expected != null && expected != snapshot.token)) {
    throw const RecordManagementException('记录已变化，请重新打开后修改');
  }
  return snapshot.token;
}

Future<CompletedSetEdit> inspectCompletedSet(
  SqlExecutor exec,
  String sessionId,
  String setId,
) => exec.transaction((tx) async {
  final token = await requireWorkoutToken(tx, sessionId);
  final row = await tx.first<Map<String, Object?>>(
    'SELECT st.*,sd.payload AS detail_payload FROM set_entry st JOIN session_exercise se ON se.id=st.session_exercise_id LEFT JOIN set_detail sd ON sd.id=st.id WHERE se.session_id=? AND st.id=? AND st.is_completed=1',
    [sessionId, setId],
  );
  if (row == null) throw const RecordManagementException('记录已变化，请重新打开后修改');
  return CompletedSetEdit(sessionId, toSetEntry(SetRow.fromMap(row)), token);
});

Future<void> updateCompletedSet(
  SqlExecutor exec,
  CompletedSetEdit edit, {
  required double weight,
  required int reps,
  EquipmentWeight? reading,
  SetDetail? detail,
}) async {
  if (!weight.isFinite || weight < 0 || reps < 0) {
    throw const RecordManagementException('重量或次数无效');
  }
  await exec.transaction((tx) async {
    await requireWorkoutToken(tx, edit.sessionId, edit.token);
    final row = await tx.first<Map<String, Object?>>(
      'SELECT st.id FROM set_entry st JOIN session_exercise se ON se.id=st.session_exercise_id '
      'WHERE st.id=? AND st.session_exercise_id=? AND se.session_id=? AND st.is_completed=1',
      [edit.original.id, edit.original.sessionExerciseId, edit.sessionId],
    );
    if (row == null) throw const RecordManagementException('记录已变化，请重新打开后修改');
    // updateSetValues validates canonical/source consistency and writes the
    // three weight columns together after ownership and token checks above.
    await updateSetValues(tx, edit.original.id, weight, reps, reading: reading);
    if (detail != null) await writeSetDetail(tx, edit.original.id, detail);
    encodeBackup(await readBackupSnapshot(tx, exportedAt: 0));
  });
}

Future<UndoSetPreview?> _undo(
  SqlExecutor tx,
  String sessionId,
  String seId,
  int now,
) async {
  final token = await requireWorkoutToken(tx, sessionId);
  final latest = await tx.first<Map<String, Object?>>(
    'SELECT st.*,sd.payload AS detail_payload FROM set_entry st JOIN session_exercise se ON se.id=st.session_exercise_id LEFT JOIN set_detail sd ON sd.id=st.id WHERE se.session_id=? AND st.is_completed=1 ORDER BY st.completed_at DESC,st.rowid DESC LIMIT 1',
    [sessionId],
  );
  if (latest == null || latest['session_exercise_id'] != seId) return null;
  final target = toSetEntry(SetRow.fromMap(latest));
  if (target.restStartedAt == null ||
      target.restSeconds != null ||
      findStaleRest([target], now) != null) {
    return null;
  }
  final rests = await tx.all(
    'SELECT st.id FROM set_entry st JOIN session_exercise se ON se.id=st.session_exercise_id WHERE se.session_id=? AND st.rest_started_at IS NOT NULL',
    [sessionId],
  );
  final sets = await listSets(tx, seId);
  final pending = sets.where((s) => !s.isCompleted).toList();
  final done = sets.where((s) => s.isCompleted).toList();
  if (rests.length != 1 ||
      pending.length != 1 ||
      done.last.id != target.id ||
      sets.indexOf(pending.single) <=
          sets.indexWhere((s) => s.id == target.id)) {
    return null;
  }
  return UndoSetPreview(sessionId, seId, target.id, pending.single.id, token);
}

Future<UndoSetPreview?> inspectUndoSet(
  SqlExecutor exec,
  String sessionId,
  String sessionExerciseId, {
  required int now,
}) => exec.transaction((tx) => _undo(tx, sessionId, sessionExerciseId, now));
Future<void> undoCompletedSet(
  SqlExecutor exec,
  UndoSetPreview preview, {
  required int now,
}) => exec.transaction((tx) async {
  await requireWorkoutToken(tx, preview.sessionId, preview.token);
  final current = await _undo(
    tx,
    preview.sessionId,
    preview.sessionExerciseId,
    now,
  );
  if (current == null ||
      current.setId != preview.setId ||
      current.pendingSetId != preview.pendingSetId) {
    throw const RecordManagementException('撤销条件已变化，请重新载入');
  }
  await tx.run(
    'DELETE FROM set_entry WHERE id=? AND session_exercise_id=? AND is_completed=0',
    [preview.pendingSetId, preview.sessionExerciseId],
  );
  await tx.run(
    'UPDATE set_entry SET is_completed=0,completed_at=NULL,rest_started_at=NULL,rest_seconds=NULL WHERE id=? AND session_exercise_id=? AND is_completed=1',
    [preview.setId, preview.sessionExerciseId],
  );
  final d = await readSetDetail(tx, preview.setId);
  if (d.isRestPause) {
    if (d.continuations.isNotEmpty) {
      final last = d.continuations.last;
      await writeSetDetail(
        tx,
        preview.setId,
        d.copyWith(
          continuations: d.continuations
              .take(d.continuations.length - 1)
              .toList(),
          intraRestStartedAt: now,
          endedEarly: false,
          pendingReading: last.reading,
        ),
      );
    } else {
      await writeSetDetail(
        tx,
        preview.setId,
        SetDetail(
          role: d.role,
          target: d.target,
          targetIndex: d.targetIndex,
          reference: d.reference,
        ),
      );
    }
  }
});

Future<CompletedSetEdit> inspectHistoricalSet(
  SqlExecutor exec,
  String sessionId,
  String setId,
) => exec.transaction((tx) async {
  final preview = await readSessionDeletion(tx, sessionId);
  if (preview == null || preview.session.finishedAt == null) {
    throw const RecordManagementException('历史记录已变化，请重新打开');
  }
  final row = await tx.first<Map<String, Object?>>(
    'SELECT st.*,sd.payload AS detail_payload FROM set_entry st JOIN session_exercise se ON se.id=st.session_exercise_id LEFT JOIN set_detail sd ON sd.id=st.id WHERE se.session_id=? AND st.id=? AND st.is_completed=1',
    [sessionId, setId],
  );
  if (row == null) throw const RecordManagementException('训练组不存在');
  return CompletedSetEdit(
    sessionId,
    toSetEntry(SetRow.fromMap(row)),
    preview.token,
  );
});

Future<void> updateHistoricalSet(
  SqlExecutor exec,
  CompletedSetEdit edit,
  EquipmentWeight reading,
  int reps,
  SetDetail? detail,
) => exec.transaction((tx) async {
  final current = await readSessionDeletion(tx, edit.sessionId);
  if (current == null ||
      current.session.finishedAt == null ||
      current.token != edit.token) {
    throw const RecordManagementException('记录已变化，请重新打开后修改');
  }
  if (reps < 0) throw const RecordManagementException('次数无效');
  await updateSetValues(
    tx,
    edit.original.id,
    reading.kilograms,
    reps,
    reading: reading,
  );
  if (detail != null) await writeSetDetail(tx, edit.original.id, detail);
  encodeBackup(await readBackupSnapshot(tx, exportedAt: 0));
});
