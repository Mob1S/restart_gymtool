import 'dart:convert';

import '../../domain/plans.dart';
import '../../domain/local_date.dart';
import '../../domain/training_plans.dart';
import '../../domain/training_schedule.dart';
import '../db/sql_executor.dart';
import 'training_plan_repo.dart';
import 'session_repo.dart';

Future<PlannedWorkout> loadNextWorkout(
  SqlExecutor exec, {
  String? planId,
  String? preferredDayId,
  bool freeTraining = false,
  String? preferredTemplateId,
  DateTime? now,
}) => exec.transaction(
  (tx) => readPlannedWorkout(
    tx,
    planId: planId,
    preferredDayId: preferredDayId,
    freeTraining: freeTraining,
    preferredTemplateId: preferredTemplateId,
    now: now,
  ),
);

Future<PlannedWorkout> readPlannedWorkout(
  SqlExecutor tx, {
  String? planId,
  String? preferredDayId,
  bool freeTraining = false,
  String? preferredTemplateId,
  DateTime? now,
}) async {
  final today = LocalDate.fromDateTime(now ?? DateTime.now());
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
      selectionToken: jsonEncode(['free', today.key, previous?.id, exercises]),
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
  var schedule = resolveTrainingSchedule(
    days: plan.days,
    today: today,
    activatedOn: plan.activatedOn,
    completedDayId: latest?['template_id'] as String?,
    completedOn: latest == null
        ? null
        : LocalDate.fromDateTime(
            DateTime.fromMillisecondsSinceEpoch(latest['finished_at'] as int),
          ),
  );
  if (preferred != null) {
    final chosen = plan.days.firstWhere((day) => day.id == preferred);
    if (chosen.kind != TrainingDayKind.training) {
      throw const PlanValidationException('休息日不能开始计划训练，请重新选择训练日');
    }
    schedule = TrainingSchedule(TrainingScheduleState.training, day: chosen);
  }
  final day = schedule.day;
  final dayId = day?.id;
  return PlannedWorkout(
    schedule: schedule,
    planId: plan.id,
    planName: plan.name,
    templateId: day?.id,
    name: day?.name,
    dayName: day?.name,
    exerciseIds: schedule.state == TrainingScheduleState.training
        ? day!.exerciseIds
        : [],
    selectionToken: jsonEncode([
      plan.id,
      [
        for (final parent in plans) [parent.id, parent.position],
      ],
      plan.token,
      plan.activatedOn?.key,
      latest,
      dayId,
      today.key,
      schedule.state.name,
    ]),
  );
}
