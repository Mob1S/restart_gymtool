import '../../domain/exercise_catalog.dart';
import '../../domain/backup_codec.dart';
import '../db/sql_executor.dart';
import '../ids.dart';
import 'backup_repo.dart';
import 'exercise_repo.dart';
import 'seed.dart';

const exerciseCatalogVersion = 1;

List<CatalogExercise> get builtinExerciseCatalog => [
  for (final e in seedExercises)
    CatalogExercise(
      e.name,
      e.muscleGroup,
      e.equipment,
      aliases: baseExerciseAliases['${e.name}|${e.equipment}'] ?? const [],
      loadMeaning: e.equipment == '自重' ? 'bodyweight' : 'external',
    ),
  ...addedCatalogExercises,
];
Future<Map<String, String>> readCatalogBindings(SqlExecutor tx) async => {
  for (final row in await tx.all<Map<String, Object?>>(
    'SELECT id,exercise_id FROM exercise_catalog_binding',
  ))
    row['id'] as String: row['exercise_id'] as String,
};
Future<void> syncExerciseCatalog(SqlExecutor exec) =>
    exec.transaction(syncExerciseCatalogInTransaction);
Future<void> syncExerciseCatalogInTransaction(SqlExecutor tx) async {
  final bindings = await readCatalogBindings(tx);
  final all = await listExercises(tx, includeArchived: true);
  final newExercises = <List<Object?>>[];
  final newBindings = <List<Object?>>[];
  for (final item in builtinExerciseCatalog) {
    if (bindings.containsKey(item.key)) continue;
    final matches = all.where(item.identifies).toList();
    // Ambiguous existing custom entries remain separate, selected during import.
    if (matches.length > 1) continue;
    final id = matches.isEmpty ? newId() : matches.single.id;
    if (matches.isEmpty) {
      newExercises.add([
        id,
        item.name,
        item.muscleGroup,
        item.equipment,
        DateTime.now().millisecondsSinceEpoch,
      ]);
    }
    newBindings.add([item.key, id]);
  }
  if (newExercises.isNotEmpty) {
    await tx.run(
      'INSERT INTO exercise(id,name,muscle_group,equipment,is_custom,is_archived,created_at) VALUES ${newExercises.map((_) => '(?,?,?,?,0,0,?)').join(',')}',
      newExercises.expand((row) => row).toList(),
    );
  }
  if (newBindings.isNotEmpty) {
    await tx.run(
      'INSERT INTO exercise_catalog_binding(id,exercise_id) VALUES ${newBindings.map((_) => '(?,?)').join(',')}',
      newBindings.expand((row) => row).toList(),
    );
    encodeBackup(await readBackupSnapshot(tx, exportedAt: 0));
  }
  await tx.run(
    "INSERT INTO app_meta(key,value) VALUES('exercise_catalog_version',?) ON CONFLICT(key) DO UPDATE SET value=excluded.value",
    ['$exerciseCatalogVersion'],
  );
}
