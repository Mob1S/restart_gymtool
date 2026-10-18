import '../../domain/training_plans.dart';
import '../../domain/training_prescription.dart';
import '../../domain/plans.dart';
import '../../domain/backup_codec.dart';
import '../builtin_programs.dart';
import '../db/sql_executor.dart';
import 'exercise_catalog_repo.dart';
import 'exercise_repo.dart';
import 'training_plan_repo.dart';
import 'training_program_repo.dart';
import 'backup_repo.dart';

Future<int> countBuiltinProgramCopies(SqlExecutor exec, String key) async {
  final rows = await exec.all<Map<String, Object?>>(
    'SELECT payload FROM training_program',
  );
  return rows
      .where(
        (r) =>
            TrainingProgram.decode(r['payload'] as String).templateKey == key,
      )
      .length;
}

Future<TrainingPlanDetail> importBuiltinProgram(
  SqlExecutor exec,
  BuiltinProgram preset, {
  Map<String, String> overrides = const {},
  Set<String> restoreArchivedIds = const {},
  List<BuiltinDay>? cycle,
}) => exec.transaction((tx) async {
  final days = cycle ?? preset.days;
  await syncExerciseCatalogInTransaction(tx);
  final bindings = await readCatalogBindings(tx);
  final all = await listExercises(tx, includeArchived: true);
  final resolved = <String, String>{};
  for (final day in days) {
    for (final item in day.exercises) {
      final selected = overrides[item.key] ?? bindings[item.key];
      final matches = all
          .where(
            (e) => selected != null
                ? e.id == selected
                : e.name == item.name && e.equipment == item.equipment,
          )
          .toList();
      if (matches.length != 1) {
        throw PlanValidationException('请为「${item.name}」选择一个动作');
      }
      final e = matches.single;
      if (e.isArchived) {
        if (!restoreArchivedIds.contains(e.id)) {
          throw PlanValidationException('「${e.name}」已归档，请选择恢复或替代动作');
        }
        await tx.run('UPDATE exercise SET is_archived=0 WHERE id=?', [e.id]);
      }
      resolved[item.key] = e.id;
    }
  }
  final plan = await writeTrainingPlan(
    tx,
    TrainingPlanDraft(
      name: preset.name,
      days: [
        for (final day in days)
          TrainingDayDraft(
            name: day.name,
            kind: day.rest ? TrainingDayKind.rest : TrainingDayKind.training,
            exerciseIds: [for (final e in day.exercises) resolved[e.key]!],
          ),
      ],
    ),
  );
  final stages = <ProgramStage>[];
  for (var stage = 0; stage < preset.stages.length; stage++) {
    final targets = <String, List<SetTarget>>{};
    for (var d = 0; d < days.length; d++) {
      for (var e = 0; e < days[d].exercises.length; e++) {
        targets[plan.days[d].occurrenceIds[e]] = days[d].exercises[e].at(stage);
      }
    }
    stages.add(
      ProgramStage(
        id: 'stage-${stage + 1}',
        name: preset.stages[stage],
        targets: targets,
      ),
    );
  }
  await writeTrainingProgram(
    tx,
    plan.id,
    TrainingProgram(
      stages: stages,
      currentStageId: stages.first.id,
      sourceTitle: preset.sourceTitle,
      sourceUrl: preset.sourceUrl,
      notes: preset.notes,
      templateKey: preset.key,
    ),
  );
  encodeBackup(await readBackupSnapshot(tx, exportedAt: 0));
  return (await readTrainingPlan(tx, plan.id))!;
});
