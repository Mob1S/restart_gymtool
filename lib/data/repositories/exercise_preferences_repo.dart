import '../../domain/backup_codec.dart';

import 'dart:convert';

import '../../domain/exercise_preferences.dart';
import '../../domain/record_management.dart';
import '../db/sql_executor.dart';
import 'exercise_repo.dart';
import 'backup_repo.dart';

ExercisePreference _preference(String id, Map<String, Object?>? row) =>
    ExercisePreference(
      exerciseId: id,
      weightStepMilli: row?['weight_step_milli'] as int? ?? 2500,
      isFavorite: row?['is_favorite'] == 1,
      equipmentNote: row?['equipment_note'] as String? ?? '',
      token: jsonEncode(row),
    );

Future<Map<String, ExercisePreference>> readExercisePreferences(
  SqlExecutor tx,
  Iterable<String> ids,
) async {
  final wanted = ids.toSet();
  final rows = await tx.all<Map<String, Object?>>(
    'SELECT * FROM exercise_preference ORDER BY rowid',
  );
  final indexed = {for (final row in rows) row['exercise_id'] as String: row};
  return {for (final id in wanted) id: _preference(id, indexed[id])};
}

Future<ExercisePreference> saveExercisePreference(
  SqlExecutor exec,
  String exerciseId, {
  required String expectedToken,
  int? weightStepMilli,
  bool? isFavorite,
  String? equipmentNote,
}) async {
  if (weightStepMilli != null && !weightStepOptions.contains(weightStepMilli)) {
    throw const FormatException('调重幅度无效');
  }
  final note = equipmentNote == null
      ? null
      : normalizeEquipmentNote(equipmentNote);
  return exec.transaction((tx) async {
    if (await getExercise(tx, exerciseId) == null) {
      throw const RecordManagementException('动作已变化，请重新打开');
    }
    final current = (await readExercisePreferences(tx, [
      exerciseId,
    ]))[exerciseId]!;
    if (current.token != expectedToken) {
      throw const RecordManagementException('动作偏好已变化，请重新打开后保存');
    }
    final step = weightStepMilli ?? current.weightStepMilli;
    final favorite = isFavorite ?? current.isFavorite;
    final text = note ?? current.equipmentNote;
    if (step == 2500 && !favorite && text.isEmpty) {
      await tx.run('DELETE FROM exercise_preference WHERE exercise_id=?', [
        exerciseId,
      ]);
    } else {
      await tx.run(
        'INSERT INTO exercise_preference (exercise_id,weight_step_milli,is_favorite,equipment_note) VALUES (?,?,?,?) '
        'ON CONFLICT(exercise_id) DO UPDATE SET weight_step_milli=excluded.weight_step_milli,is_favorite=excluded.is_favorite,equipment_note=excluded.equipment_note',
        [exerciseId, step, favorite ? 1 : 0, text],
      );
    }
    encodeBackup(await readBackupSnapshot(tx, exportedAt: 0));
    return (await readExercisePreferences(tx, [exerciseId]))[exerciseId]!;
  });
}
