import 'local_date.dart';
import 'training_plans.dart';

enum TrainingScheduleState { empty, training, completed, rest }

class TrainingSchedule {
  final TrainingScheduleState state;
  final TrainingDay? day, nextTrainingDay;
  const TrainingSchedule(this.state, {this.day, this.nextTrainingDay});
}

/// Only rest entries consume calendar days. A training entry waits for a real
/// completed workout, regardless of the number of days the app was closed.
TrainingSchedule resolveTrainingSchedule({
  required List<TrainingDay> days,
  required LocalDate today,
  LocalDate? activatedOn,
  String? completedDayId,
  LocalDate? completedOn,
}) {
  if (days.isEmpty) return const TrainingSchedule(TrainingScheduleState.empty);
  final completedIndex = days.indexWhere((day) => day.id == completedDayId);
  final hasCompletion = completedIndex >= 0 && completedOn != null;
  var index = hasCompletion ? (completedIndex + 1) % days.length : 0;
  final nextTraining = <TrainingDay>[
    for (var i = 0; i < days.length; i++)
      if (days[(index + i) % days.length].kind == TrainingDayKind.training)
        days[(index + i) % days.length],
  ].firstOrNull;
  if (days[index].kind == TrainingDayKind.training) {
    return TrainingSchedule(TrainingScheduleState.training, day: days[index]);
  }
  var elapsed = today.daysSince(
    hasCompletion ? completedOn : activatedOn ?? today,
  );
  if (hasCompletion && elapsed <= 0) {
    return TrainingSchedule(TrainingScheduleState.completed,
      day: days[index], nextTrainingDay: nextTraining);
  }
  // The first rest after a completion is tomorrow; leading rest is today.
  elapsed = (elapsed - (hasCompletion ? 1 : 0)).clamp(0, 3652425);
  if (nextTraining == null) {
    index = (index + elapsed) % days.length;
  } else {
    while (elapsed > 0 && days[index].kind == TrainingDayKind.rest) {
      index = (index + 1) % days.length;
      elapsed--;
    }
  }
  final day = days[index];
  return TrainingSchedule(
    day.kind == TrainingDayKind.rest
        ? TrainingScheduleState.rest : TrainingScheduleState.training,
    day: day,
    nextTrainingDay: day.kind == TrainingDayKind.rest ? nextTraining : null,
  );
}
