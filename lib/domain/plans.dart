import 'dart:convert';

class SplitTemplate {
  final String id;
  final String name;
  final int position;
  final int createdAt;
  const SplitTemplate({
    required this.id,
    required this.name,
    required this.position,
    required this.createdAt,
  });
}

class TemplateExercise {
  final String id;
  final String templateId;
  final String exerciseId;
  final int position;
  const TemplateExercise({
    required this.id,
    required this.templateId,
    required this.exerciseId,
    required this.position,
  });
}

class TemplateSummary {
  final SplitTemplate template;
  final int exerciseCount;
  const TemplateSummary(this.template, this.exerciseCount);
}

class TemplateItem {
  final TemplateExercise entry;
  final String exerciseName;
  final bool isArchived;
  const TemplateItem(this.entry, this.exerciseName, this.isArchived);
}

class TemplateDetail {
  final SplitTemplate template;
  final List<TemplateItem> exercises;
  final String editToken;
  TemplateDetail(this.template, List<TemplateItem> exercises, this.editToken)
    : exercises = List.unmodifiable(exercises);
}

class TemplateDraft {
  final String? id;
  final String name;
  final List<String> exerciseIds;
  final String? expectedToken;
  TemplateDraft({
    this.id,
    required this.name,
    required List<String> exerciseIds,
    this.expectedToken,
  }) : exerciseIds = List.unmodifiable(exerciseIds);
}

class PlannedWorkout {
  final String? planId;
  final String? planName;
  final String? dayName;
  final String? templateId;
  final String? name;
  final List<String> exerciseIds;
  final String selectionToken;
  PlannedWorkout({
    this.planId,
    this.planName,
    this.dayName,
    this.templateId,
    this.name,
    required List<String> exerciseIds,
    required this.selectionToken,
  }) : exerciseIds = List.unmodifiable(exerciseIds);

  bool get hasUsableDay => templateId != null;
  bool get freeTraining => planId == null;
}

class TemplateDeletePreview {
  final String id;
  final String name;
  final int exerciseCount;
  final int completedReferences;
  final int activeReferences;
  final String token;
  const TemplateDeletePreview(
    this.id,
    this.name,
    this.exerciseCount,
    this.completedReferences,
    this.activeReferences,
    this.token,
  );
}

class TemplateDeleteResult {
  final bool deleted;
  final int detachedCompleted;
  final int detachedActive;
  const TemplateDeleteResult(
    this.deleted,
    this.detachedCompleted,
    this.detachedActive,
  );
}

class PlanValidationException implements Exception {
  final String message;
  const PlanValidationException(this.message);
  @override
  String toString() => message;
}

String templateOrderToken(List<TemplateSummary> ordered) => jsonEncode([
  for (final s in ordered) [s.template.id, s.template.position],
]);
