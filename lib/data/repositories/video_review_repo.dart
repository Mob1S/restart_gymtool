import 'dart:convert';

import '../db/sql_executor.dart';

class VideoReviewRepo {
  final SqlExecutor exec;
  const VideoReviewRepo(this.exec);

  Future<Map<String, Object?>?> group(String setId) =>
      exec.first<Map<String, Object?>>(
        'SELECT st.*, e.name, sd.payload AS detail FROM set_entry st '
        'JOIN session_exercise se ON se.id=st.session_exercise_id '
        'JOIN exercise e ON e.id=se.exercise_id LEFT JOIN set_detail sd ON sd.id=st.id '
        'WHERE st.id=? AND st.is_completed=1',
        [setId],
      );
  Future<Map<String, dynamic>?> load(String setId) async {
    final row = await exec.first<Map<String, Object?>>(
      'SELECT * FROM video_review WHERE set_id=?',
      [setId],
    );
    return row == null
        ? null
        : {
            'folder': row['folder'],
            ...jsonDecode(row['payload'] as String) as Map<String, dynamic>,
          };
  }

  Future<void> save(
    String setId,
    String folder,
    Map<String, dynamic> payload,
  ) => exec.transaction((tx) async {
    if (await tx.first(
          'SELECT id FROM set_entry WHERE id=? AND is_completed=1',
          [setId],
        ) ==
        null) {
      throw StateError('这组训练已被删除或尚未完成');
    }
    await tx.run(
      'INSERT INTO video_review(set_id,folder,payload) VALUES(?,?,?) '
      'ON CONFLICT(set_id) DO UPDATE SET folder=excluded.folder,payload=excluded.payload',
      [setId, folder, jsonEncode(payload)],
    );
  });
  Future<void> delete(String setId) =>
      exec.run('DELETE FROM video_review WHERE set_id=?', [setId]);
  Future<List<String>> folders() async => [
    for (final row in await exec.all<Map<String, Object?>>(
      'SELECT folder FROM video_review',
    ))
      row['folder'] as String,
  ];
  Future<Map<String, String>> resultFiles() async => {
    for (final row in await exec.all<Map<String, Object?>>(
      'SELECT folder,payload FROM video_review',
    ))
      row['folder'] as String:
          (jsonDecode(row['payload'] as String)
                  as Map<String, dynamic>)['result']
              as String,
  };
}
