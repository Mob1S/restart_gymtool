import 'motion_project_repo.dart';

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
  Future<Map<String, dynamic>?> load(String setId) =>
      MotionProjectRepo(exec).forSet(setId);
  Future<void> save(
    String setId,
    String folder,
    Map<String, dynamic> payload,
  ) async {
    final projects = MotionProjectRepo(exec);
    final old = await projects.forSet(setId);
    await projects.save(
      id: old?['id'] as String? ?? 'legacy-$setId',
      setId: setId,
      mode: 'import',
      folder: folder,
      payload: payload,
    );
  }

  Future<void> delete(String setId) async {
    final old = await MotionProjectRepo(exec).forSet(setId);
    if (old != null) await MotionProjectRepo(exec).delete(old['id'] as String);
  }

  Future<List<String>> folders() async => [
    for (final p in await MotionProjectRepo(exec).list()) p['folder'] as String,
  ];
  Future<Map<String, String>> resultFiles() =>
      MotionProjectRepo(exec).resultFiles();
}
