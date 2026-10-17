import '../../domain/backup_codec.dart';

import 'dart:convert';

import '../../domain/exercise_preferences.dart';
import '../../domain/weight_value.dart';
import '../../domain/record_management.dart';
import '../db/sql_executor.dart';
import 'exercise_repo.dart';
import 'backup_repo.dart';

ExercisePreference _preference(String id, Map<String, Object?>? row) =>
    ExercisePreference(
      exerciseId: id,
      weightUnit: WeightUnit.values.byName(
        row?['weight_unit'] as String? ?? 'kg',
      ),
      kgStep: DecimalReading.parse(row?['kg_step'] as String? ?? '2.5'),
      lbStep: DecimalReading.parse(row?['lb_step'] as String? ?? '5'),
      showKgEquivalent: row?['show_kg_equivalent'] == 1,
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
  WeightUnit? weightUnit,
  DecimalReading? kgStep,
  DecimalReading? lbStep,
  bool? showKgEquivalent,
  bool? isFavorite,
  String? equipmentNote,
}) async {
  if ((weightStepMilli != null && weightStepMilli <= 0) ||
      (kgStep != null && (!kgStep.asDouble.isFinite || kgStep.asDouble <= 0)) ||
      (lbStep != null && (!lbStep.asDouble.isFinite || lbStep.asDouble <= 0))) {
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
    final kg =
        kgStep ??
        (weightStepMilli == null
            ? current.kgStep
            : DecimalReading.parse((weightStepMilli / 1000).toString()));
    final lb = lbStep ?? current.lbStep;
    final unit = weightUnit ?? current.weightUnit;
    final showKg = showKgEquivalent ?? current.showKgEquivalent;
    final favorite = isFavorite ?? current.isFavorite;
    final text = note ?? current.equipmentNote;
    await writeExercisePreference(
      tx,
      ExercisePreference(
        exerciseId: exerciseId,
        kgStep: kg,
        lbStep: lb,
        weightUnit: unit,
        showKgEquivalent: showKg,
        isFavorite: favorite,
        equipmentNote: text,
        token: current.token,
      ),
    );
    encodeBackup(await readBackupSnapshot(tx, exportedAt: 0));
    return (await readExercisePreferences(tx, [exerciseId]))[exerciseId]!;
  });
}

/// Only writes within the caller's transaction, without notifications or a
/// nested transaction. The caller validates its conflict token and snapshot.
Future<void> writeExercisePreference(
  SqlExecutor tx,
  ExercisePreference value,
) async {
  if (!value.kgStep.asDouble.isFinite ||
      value.kgStep.asDouble <= 0 ||
      !value.lbStep.asDouble.isFinite ||
      value.lbStep.asDouble <= 0) {
    throw const FormatException('调重幅度必须为正的有限数');
  }
  final text = normalizeEquipmentNote(value.equipmentNote);
  if (value.kgStep.text == '2.5' &&
      value.lbStep.text == '5' &&
      value.weightUnit == WeightUnit.kg &&
      !value.showKgEquivalent &&
      !value.isFavorite &&
      text.isEmpty) {
    await tx.run('DELETE FROM exercise_preference WHERE exercise_id=?', [
      value.exerciseId,
    ]);
  } else {
    await tx.run(
      'INSERT INTO exercise_preference (exercise_id,weight_unit,kg_step,lb_step,show_kg_equivalent,is_favorite,equipment_note) VALUES (?,?,?,?,?,?,?) '
      'ON CONFLICT(exercise_id) DO UPDATE SET weight_unit=excluded.weight_unit,kg_step=excluded.kg_step,lb_step=excluded.lb_step,show_kg_equivalent=excluded.show_kg_equivalent,is_favorite=excluded.is_favorite,equipment_note=excluded.equipment_note',
      [
        value.exerciseId,
        value.weightUnit.name,
        value.kgStep.text,
        value.lbStep.text,
        value.showKgEquivalent ? 1 : 0,
        value.isFavorite ? 1 : 0,
        text,
      ],
    );
  }
}
