import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/domain/exercise_preferences.dart';
import 'package:gym_tracker/domain/format.dart';

void main() {
  test('relative adjustment preserves imported off-grid weights', () {
    expect(adjustWeight(21.3, 2.5, 1), 23.8);
    expect(adjustWeight(21.3, 2.5, -1), 18.8);
    expect(adjustWeight(0, 1.25, -1), 0);
    expect(adjustWeight(499, 2.5, 1), 500);
    expect(adjustWeight(620, 1.25, -1), 618.75);
  });
  test('actual weight supports quarter increments and marks rounding', () {
    expect(formatWeightKg(20), '20');
    expect(formatWeightKg(21.25), '21.25');
    expect(formatWeightKg(21.5), '21.5');
    expect(formatWeightKg(21.333), '≈21.33');
    expect(formatWeightKg(0), '0');
  });
  test('note limits count Unicode code points and preserve internal lines', () {
    expect(normalizeEquipmentNote('  座椅4\n短握把  '), '座椅4\n短握把');
    expect(normalizeEquipmentNote('😀' * 500).runes.length, 500);
    expect(() => normalizeEquipmentNote('😀' * 501), throwsFormatException);
    expect(normalizeEquipmentNote('  '), '');
  });
}
