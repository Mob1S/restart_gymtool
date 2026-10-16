import 'dart:convert';

import '../../domain/plans.dart';
import '../../domain/rotation.dart';
import '../db/sql_executor.dart';
import 'template_repo.dart';
import 'session_repo.dart';

Future<PlannedWorkout> loadNextWorkout(
  SqlExecutor exec, {
  String? preferredTemplateId,
}) => exec.transaction(
  (tx) => readPlannedWorkout(tx, preferredTemplateId: preferredTemplateId),
);
Future<PlannedWorkout> readPlannedWorkout(
  SqlExecutor tx, {
  String? preferredTemplateId,
}) async {
  final templates = await readTemplates(tx);
  final last = await findLatestTemplateId(tx);
  final ids = templates.map((e) => e.template.id).toList();
  if (preferredTemplateId != null && !ids.contains(preferredTemplateId)) {
    throw const PlanValidationException('所选计划已不存在，请重新选择');
  }
  if (ids.isEmpty) {
    final sessions = await listSessions(tx, 1);
    final previous = sessions.isEmpty ? null : sessions.first;
    final exercises = previous == null
        ? <String>[]
        : (await listSessionExercises(
            tx,
            previous.id,
          )).map((e) => e.exerciseId).toList();
    return PlannedWorkout(
      exerciseIds: exercises,
      selectionToken: jsonEncode([previous?.id, exercises]),
    );
  }
  final id = preferredTemplateId ?? ids[nextTemplateIndex(ids, last)!];
  final detail = (await readTemplate(tx, id))!;
  return PlannedWorkout(
    templateId: id,
    name: detail.template.name,
    exerciseIds: detail.exercises.map((e) => e.entry.exerciseId).toList(),
    selectionToken: jsonEncode([
      templateOrderToken(templates),
      last,
      detail.editToken,
    ]),
  );
}
