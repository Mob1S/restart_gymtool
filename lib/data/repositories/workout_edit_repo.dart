import '../../domain/record_management.dart';
import '../../domain/workout_edit.dart';
import '../../domain/rest.dart';
import '../db/sql_executor.dart';
import 'record_management_repo.dart';
import 'set_repo.dart';

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
    'SELECT st.* FROM set_entry st JOIN session_exercise se ON se.id=st.session_exercise_id WHERE se.session_id=? AND st.id=? AND st.is_completed=1',
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
    await tx.run(
      'UPDATE set_entry SET weight=?, reps=? WHERE id=? AND session_exercise_id=? AND is_completed=1',
      [weight, reps, edit.original.id, edit.original.sessionExerciseId],
    );
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
    'SELECT st.* FROM set_entry st JOIN session_exercise se ON se.id=st.session_exercise_id WHERE se.session_id=? AND st.is_completed=1 ORDER BY st.completed_at DESC,st.rowid DESC LIMIT 1',
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
});
