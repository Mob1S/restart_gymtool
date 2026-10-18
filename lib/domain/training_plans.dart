import 'dart:convert';

import 'local_date.dart';

enum TrainingDayKind { training, rest }

/// An entire plan is edited locally and committed together with all its days.
class TrainingPlanDraft {
  final String? id, expectedToken;
  final String name;
  final List<TrainingDayDraft> days;
  TrainingPlanDraft({
    this.id,
    this.expectedToken,
    required this.name,
    required List<TrainingDayDraft> days,
  }) : days = List.unmodifiable(days);
}

class TrainingDayDraft {
  final String? id;
  final String name;
  final List<String> exerciseIds;
  final List<String?>? occurrenceIds;
  final TrainingDayKind kind;
  TrainingDayDraft({
    this.id,
    this.kind = TrainingDayKind.training,
    required this.name,
    required List<String> exerciseIds,
    List<String?>? occurrenceIds,
  }) : exerciseIds = List.unmodifiable(exerciseIds),
       occurrenceIds = occurrenceIds == null
           ? null
           : List.unmodifiable(occurrenceIds);
}

class TrainingDay {
  final String id, name;
  final List<String> exerciseIds;
  final List<String> occurrenceIds;
  final TrainingDayKind kind;
  TrainingDay({
    required this.id,
    List<String> occurrenceIds = const [],
    this.kind = TrainingDayKind.training,
    required this.name,
    required List<String> exerciseIds,
  }) : exerciseIds = List.unmodifiable(exerciseIds),
       occurrenceIds = List.unmodifiable(occurrenceIds);
  TrainingDayDraft toDraft() => TrainingDayDraft(
    id: id,
    name: name,
    kind: kind,
    exerciseIds: exerciseIds,
    occurrenceIds: occurrenceIds,
  );
}

class TrainingPlanDetail {
  final String id, name, token;
  final int position, createdAt;
  final List<TrainingDay> days;
  final LocalDate? activatedOn;
  TrainingPlanDetail({
    required this.id,
    this.activatedOn,
    required this.name,
    required this.token,
    required this.position,
    required this.createdAt,
    required List<TrainingDay> days,
  }) : days = List.unmodifiable(days);
  TrainingPlanDraft toDraft() => TrainingPlanDraft(
    id: id,
    expectedToken: token,
    name: name,
    days: days.map((day) => day.toDraft()).toList(),
  );
}

String trainingPlanOrderToken(List<TrainingPlanDetail> plans) => jsonEncode([
  for (final plan in plans) [plan.id, plan.position],
]);
