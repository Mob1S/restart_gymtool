import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/domain/weight_value.dart';
import 'package:gym_tracker/domain/workout_csv.dart';
import 'package:gym_tracker/domain/workout_csv_export.dart';

void main() {
  final start = DateTime.utc(2026, 10, 17, 2).millisecondsSinceEpoch;
  WorkoutCsvRow row(String id, String amount, WeightUnit unit) => WorkoutCsvRow(
    sessionId: id,
    sessionName: '上肢, "进阶"\nA',
    startedAt: start,
    finishedAt: start + 600000,
    exerciseName: '卧推,"器械"',
    setPosition: 0,
    reading: EquipmentWeight(DecimalReading.parse(amount), unit),
    reps: 8,
  );

  test('native CSV preserves source readings, exact kg and escaped fields', () {
    final csv = encodeWorkoutCsv([row('one', '50', WeightUnit.lb)]);
    expect(csv, contains(',50,lb,22.6796185,8\r\n'));
    final parsed = parseWorkoutCsv(csv);
    expect(parsed.source, CsvSource.gymTracker);
    expect(parsed.skipped, isEmpty);
    final workout = parsed.workouts.single;
    expect(workout.name, '上肢, "进阶"\nA');
    expect(workout.startedAt, start);
    final exercise = workout.exercises.single;
    expect(exercise.name, '卧推,"器械"');
    expect(exercise.sets.single.equipmentWeight.label, '50 lb');
    expect(exercise.sets.single.weight, closeTo(22.6796185, 1e-12));
  });

  test('native CSV keeps separate sessions with the same title and time', () {
    final parsed = parseWorkoutCsv(
      encodeWorkoutCsv([
        row('one', '50', WeightUnit.lb),
        row('two', '25', WeightUnit.kg),
      ]),
    );
    expect(parsed.workouts, hasLength(2));
    expect(
      parsed.workouts[1].exercises.single.sets.single.equipmentWeight.label,
      '25 kg',
    );
  });

  test(
    'native CSV rejects mismatched converted kg instead of changing original',
    () {
      final csv = encodeWorkoutCsv([row('one', '50', WeightUnit.lb)])
          .replaceFirst('22.6796185', '50');
      final parsed = parseWorkoutCsv(csv);
      expect(parsed.workouts, isEmpty);
      expect(parsed.skipped.single.reason, contains('不一致'));
    },
  );
}
