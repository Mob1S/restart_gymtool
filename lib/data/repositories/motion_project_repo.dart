import 'dart:convert';

import '../db/sql_executor.dart';
import '../../plugins/api/feature_clients.dart';

class MotionProjectRepo implements MotionProjectStore {
  final SqlExecutor exec;
  final void Function()? ensureActive;
  const MotionProjectRepo(this.exec, {this.ensureActive});

  Map<String, dynamic> _decode(Map<String, Object?> row) => {
    ...jsonDecode(row['payload'] as String) as Map<String, dynamic>,
    'id': row['id'],
    'setId': row['set_id'],
    'mode': row['mode'],
    'folder': row['folder'],
    'createdAt': row['created_at'],
    'updatedAt': row['updated_at'],
  };
  @override
  Future<List<Map<String, dynamic>>> list() async => [
    for (final row in await exec.all<Map<String, Object?>>(
      'SELECT * FROM motion_project ORDER BY updated_at DESC',
    ))
      _decode(row),
  ];
  @override
  Future<Map<String, dynamic>?> load(String id) async {
    final row = await exec.first<Map<String, Object?>>(
      'SELECT * FROM motion_project WHERE id=?',
      [id],
    );
    return row == null ? null : _decode(row);
  }

  @override
  Future<Map<String, dynamic>?> forSet(String setId) async {
    final row = await exec.first<Map<String, Object?>>(
      'SELECT * FROM motion_project WHERE set_id=?',
      [setId],
    );
    return row == null ? null : _decode(row);
  }

  @override
  Future<List<Map<String, Object?>>> completedSets() => exec.all(
    'SELECT st.id,e.name,st.weight,st.reps,st.completed_at FROM set_entry st '
    'JOIN session_exercise se ON se.id=st.session_exercise_id '
    'JOIN exercise e ON e.id=se.exercise_id WHERE st.is_completed=1 '
    'ORDER BY st.completed_at DESC',
  );
  @override
  Future<void> save({
    required String id,
    String? setId,
    required String mode,
    required String folder,
    required Map<String, dynamic> payload,
  }) => exec.transaction((tx) async {
    ensureActive?.call();
    if (setId != null) {
      if (await tx.first(
            'SELECT id FROM set_entry WHERE id=? AND is_completed=1',
            [setId],
          ) ==
          null) {
        throw StateError('这组训练已被删除或尚未完成');
      }
      final other = await tx.first<Map<String, Object?>>(
        'SELECT id FROM motion_project WHERE set_id=? AND id<>?',
        [setId, id],
      );
      if (other != null) throw StateError('这组已有分析项目，请先解除原项目关联');
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    await tx.run(
      'INSERT INTO motion_project(id,set_id,mode,folder,payload,created_at,updated_at) '
      'VALUES(?,?,?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET set_id=excluded.set_id,'
      'mode=excluded.mode,folder=excluded.folder,payload=excluded.payload,updated_at=excluded.updated_at',
      [id, setId, mode, folder, jsonEncode(payload), now, now],
    );
    ensureActive?.call();
  });
  @override
  Future<void> delete(String id) => exec.transaction((tx) async {
    ensureActive?.call();
    await tx.run('DELETE FROM motion_project WHERE id=?', [id]);
    ensureActive?.call();
  });
  @override
  Future<Map<String, String>> resultFiles() async => {
    for (final project in await list()) ...{
      if (project['result'] is String)
        project['folder'] as String: project['result'] as String,
      for (final item in project['observations'] as List? ?? [])
        if (item is Map && item['folder'] is String && item['result'] is String)
          item['folder'] as String: item['result'] as String,
    },
  };
}
