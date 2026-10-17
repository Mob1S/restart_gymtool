import 'dart:convert';

import '../../domain/plans.dart';
import '../../domain/rotation.dart';
import '../db/sql_executor.dart';
import 'training_plan_repo.dart';
import 'session_repo.dart';

Future<PlannedWorkout> loadNextWorkout(
  SqlExecutor exec, {
  String? planId,
  String? preferredDayId,
  bool freeTraining = false,
  String? preferredTemplateId,
}) => exec.transaction(
  (tx) => readPlannedWorkout(
    tx,
    planId: planId,
    preferredDayId: preferredDayId,
    freeTraining: freeTraining,
    preferredTemplateId: preferredTemplateId,
  ),
);

Future<PlannedWorkout> readPlannedWorkout(
  SqlExecutor tx, {
  String? planId,
  String? preferredDayId,
  bool freeTraining = false,
  String? preferredTemplateId,
}) async {
  if (preferredDayId != null &&
      preferredTemplateId != null &&
      preferredDayId != preferredTemplateId) {
    throw const PlanValidationException('训练日选择不一致，请重新选择');
  }
  final preferred = preferredDayId ?? preferredTemplateId;
  if (freeTraining && (planId != null || preferred != null)) {
    throw const PlanValidationException('自由训练不能同时选择训练计划');
  }
  final plans = await readTrainingPlans(tx);
  var selectedId = planId;
  if (!freeTraining && selectedId == null && preferred != null) {
    final day = await tx.first<Map<String, Object?>>(
      'SELECT plan_id FROM split_template WHERE id=?',
      [preferred],
    );
    selectedId = day?['plan_id'] as String?;
    if (selectedId == null) {
      throw const PlanValidationException('所选训练日已不存在，请重新选择');
    }
  }
  if (freeTraining || (selectedId == null && plans.isEmpty)) {
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
      selectionToken: jsonEncode(['free', previous?.id, exercises]),
    );
  }
  selectedId ??= plans.first.id;
  final matching = plans.where((plan) => plan.id == selectedId);
  if (matching.isEmpty) throw const PlanValidationException('所选训练计划已不存在，请重新选择');
  final plan = matching.single;
  final ids = plan.days.map((day) => day.id).toList();
  if (preferred != null && !ids.contains(preferred)) {
    throw const PlanValidationException('所选训练日已不存在，请重新选择');
  }
  // The most recent completion still matters when its day has been deleted.
  final latest = await tx.first<Map<String, Object?>>(
    'SELECT id,template_id,finished_at FROM session WHERE plan_id=? '
    "AND finished_at IS NOT NULL AND origin IN ('live','legacy') "
    'ORDER BY finished_at DESC,rowid DESC LIMIT 1',
    [plan.id],
  );
  final dayId =
      preferred ?? recommendDay(ids, latest?['template_id'] as String?);
  final day = dayId == null
      ? null
      : plan.days.firstWhere((day) => day.id == dayId);
  return PlannedWorkout(
    planId: plan.id,
    planName: plan.name,
    templateId: day?.id,
    name: day?.name,
    dayName: day?.name,
    exerciseIds: day?.exerciseIds ?? [],
    selectionToken: jsonEncode([
      plan.id,
      [
        for (final parent in plans) [parent.id, parent.position],
      ],
      plan.token,
      latest,
      dayId,
    ]),
  );
}
