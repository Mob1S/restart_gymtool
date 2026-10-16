import '../../domain/exercise_preferences.dart';
import '../db/sql_executor.dart';
import 'exercise_repo.dart';
import 'exercise_preferences_repo.dart';

Future<ExercisePickerData> loadExercisePickerData(
  SqlExecutor exec,
) => exec.transaction((tx) async {
  final all = await listExercises(tx);
  final preferences = await readExercisePreferences(tx, all.map((e) => e.id));
  final recent = await tx.all<Map<String, Object?>>(
    'SELECT se.exercise_id,MAX(COALESCE(st.completed_at,s.started_at)) AS used '
    'FROM set_entry st JOIN session_exercise se ON se.id=st.session_exercise_id JOIN session s ON s.id=se.session_id '
    'WHERE st.is_completed=1 GROUP BY se.exercise_id',
  );
  final times = {
    for (final r in recent) r['exercise_id'] as String: r['used'] as int,
  };
  final ordered = all.where((e) => times.containsKey(e.id)).toList();
  final ranks = {for (var i = 0; i < all.length; i++) all[i].id: i};
  ordered.sort((a, b) {
    final time = times[b.id]!.compareTo(times[a.id]!);
    return time != 0 ? time : ranks[a.id]!.compareTo(ranks[b.id]!);
  });
  return ExercisePickerData(
    all,
    preferences,
    ordered.take(10).map((e) => e.id).toList(),
  );
});
