import 'types.dart';

const weightStepOptions = [500, 1000, 1250, 2500, 5000];

class ExercisePreference {
  final String exerciseId;
  final int weightStepMilli;
  final bool isFavorite;
  final String equipmentNote;
  final String token;
  const ExercisePreference({
    required this.exerciseId,
    this.weightStepMilli = 2500,
    this.isFavorite = false,
    this.equipmentNote = '',
    required this.token,
  });
  double get weightStepKg => weightStepMilli / 1000;
}

class ExercisePickerData {
  final List<Exercise> all;
  final Map<String, ExercisePreference> preferences;
  final List<String> recentIds;
  ExercisePickerData(
    List<Exercise> all,
    Map<String, ExercisePreference> preferences,
    List<String> recentIds,
  ) : all = List.unmodifiable(all),
      preferences = Map.unmodifiable(preferences),
      recentIds = List.unmodifiable(recentIds);
}

String normalizeEquipmentNote(String note) {
  final value = note.trim();
  if (value.runes.length > 500) throw const FormatException('器械备忘最多 500 个字符');
  return value;
}

double adjustWeight(
  double value,
  double stepKg,
  int steps, {
  double min = 0,
  double max = 500,
}) {
  final next = value + stepKg * steps;
  // Imported values beyond the normal range remain editable without truncation.
  final low = value < min ? value : min;
  final high = value > max ? value : max;
  return (next.clamp(low, high) * 1000000).round() / 1000000;
}
