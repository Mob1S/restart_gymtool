import 'dart:convert';

import '../../domain/record_management.dart';
import '../db/sql_executor.dart';
import 'session_repo.dart';

Future<SessionDeletePreview?> inspectSessionDeletion(
  SqlExecutor exec,
  String id,
) => exec.transaction((tx) => readSessionDeletion(tx, id));

/// Transaction-scoped snapshot used for confirmation and revalidation.
Future<SessionDeletePreview?> readSessionDeletion(
  SqlExecutor tx,
  String id,
) async {
  final session = await getSession(tx, id);
  if (session == null) return null;
  final row = await tx.first('SELECT * FROM session WHERE id=?', [id]);
  final children = await tx.all(
    'SELECT * FROM session_exercise WHERE session_id=? ORDER BY position,rowid',
    [id],
  );
  final sets = await tx.all<Map<String, Object?>>(
    'SELECT st.* FROM set_entry st JOIN session_exercise se ON se.id=st.session_exercise_id WHERE se.session_id=? ORDER BY se.position,se.rowid,st.position,st.rowid',
    [id],
  );
  return SessionDeletePreview(
    session,
    sets.where((s) => s['is_completed'] == 1).length,
    sets.where((s) => s['is_completed'] == 0).length,
    jsonEncode([row, children, sets]),
  );
}

Future<SessionDeleteResult> deleteSession(
  SqlExecutor exec,
  SessionDeletePreview preview,
) => exec.transaction((tx) async {
  final current = await readSessionDeletion(tx, preview.session.id);
  if (current == null) {
    return SessionDeleteResult(
      false,
      preview.session.id,
      preview.session.finishedAt == null,
    );
  }
  if (current.token != preview.token) {
    throw const RecordManagementException('这场训练已变化，请重新确认删除');
  }
  await tx.run('DELETE FROM session WHERE id=?', [current.session.id]);
  return SessionDeleteResult(
    true,
    current.session.id,
    current.session.finishedAt == null,
  );
});
Future<void> deleteSessionExercise(SqlExecutor tx, String id) async {
  final target = await tx.first<Map<String, Object?>>(
    'SELECT session_id FROM session_exercise WHERE id=?',
    [id],
  );
  if (target == null) return;
  await tx.run('DELETE FROM session_exercise WHERE id=?', [id]);
  final remaining = await listSessionExercises(
    tx,
    target['session_id'] as String,
  );
  for (var i = 0; i < remaining.length; i++) {
    await tx.run('UPDATE session_exercise SET position=? WHERE id=?', [
      i,
      remaining[i].id,
    ]);
  }
}

Future<void> retainCompletedSets(SqlExecutor tx, String id) async {
  await tx.run(
    'DELETE FROM set_entry WHERE session_exercise_id=? AND is_completed=0',
    [id],
  );
  await tx.run(
    'UPDATE set_entry SET rest_started_at=NULL WHERE session_exercise_id=? AND rest_started_at IS NOT NULL',
    [id],
  );
}
