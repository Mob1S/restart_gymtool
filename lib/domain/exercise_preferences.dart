import 'types.dart';
import 'weight_value.dart';

const weightStepOptions = [500, 1000, 1250, 2500, 5000];

class ExercisePreference {
  final String exerciseId;
  final int _legacyWeightStepMilli;
  final DecimalReading? _kgStep;
  final DecimalReading? _lbStep;
  final WeightUnit weightUnit;
  final bool showKgEquivalent;
  final bool isFavorite;
  final String equipmentNote;
  final String token;
  const ExercisePreference({
    required this.exerciseId,
    int weightStepMilli = 2500,
    DecimalReading? kgStep,
    DecimalReading? lbStep,
    this.weightUnit = WeightUnit.kg,
    this.showKgEquivalent = false,
    this.isFavorite = false,
    this.equipmentNote = '',
    required this.token,
  }) : _legacyWeightStepMilli = weightStepMilli,
       // Keep the public kgStep/lbStep parameter names for repository callers.
       // ignore: prefer_initializing_formals
       _kgStep = kgStep,
       // ignore: prefer_initializing_formals
       _lbStep = lbStep;
  DecimalReading get kgStep =>
      _kgStep ??
      DecimalReading.parse((_legacyWeightStepMilli / 1000).toString());
  DecimalReading get lbStep => _lbStep ?? DecimalReading.parse('5');
  int get weightStepMilli => (kgStep.asDouble * 1000).round();
  double get weightStepKg => kgStep.asDouble;
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
