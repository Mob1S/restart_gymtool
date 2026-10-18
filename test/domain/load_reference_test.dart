import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/domain/load_reference.dart';
import 'package:gym_tracker/domain/training_prescription.dart';
import 'package:gym_tracker/domain/weight_value.dart';

void main() {
  test('rest-pause references use the selected segment reading and never infer a continuous RM', () {
    final target = SetTarget(
      repsMin: 10,
      repsMax: 10,
      extraReps: [5],
      pauseSeconds: 5,
    );
    final result = suggestLoad(
      history: [
        LoadObservation(
          sessionId: 's',
          setId: 'g',
          at: 1000,
          reps: 5,
          firstReps: 10,
          segmentIndex: 1,
          reading: EquipmentWeight.kg(25),
          pattern: [5],
          pauseSeconds: 5,
        ),
      ],
      target: target,
      segmentIndex: 1,
      unit: WeightUnit.kg,
      step: DecimalReading.parse('2.5'),
      now: 2000,
    );
    expect(result.reading!.kilograms, 25);
    expect(result.evidence.single, contains('第 2 段'));
  });
  test(
    'high RM direct evidence stays independent of prescribed work repetitions',
    () {
      final result = suggestLoad(
        history: [
          LoadObservation(
            sessionId: 's',
            setId: 'g',
            at: 1000,
            reps: 15,
            reading: EquipmentWeight.kg(40),
            effort: const Effort('rpe', 10),
          ),
        ],
        target: SetTarget(
          repsMin: 8,
          repsMax: 8,
          loadKind: 'rm',
          loadValue: 15,
        ),
        unit: WeightUnit.kg,
        step: DecimalReading.parse('2.5'),
        now: 2000,
      );
      expect(result.reading!.kilograms, 40);
    },
  );
  final now = DateTime(2026, 10, 18).millisecondsSinceEpoch;
  LoadReference run(
    List<LoadObservation> rows, {
    String meaning = 'external',
    SetTarget? target,
    WeightUnit unit = WeightUnit.kg,
  }) => suggestLoad(
    history: rows,
    target: target ?? SetTarget(repsMin: 8, repsMax: 8),
    unit: unit,
    step: DecimalReading.parse(unit == WeightUnit.kg ? '2.5' : '5'),
    now: now,
    loadMeaning: meaning,
  );
  LoadObservation point(int i, double kg, {Effort? effort}) => LoadObservation(
    sessionId: 's$i',
    setId: 'set$i',
    at: now - i * 86400000,
    reps: 8,
    reading: EquipmentWeight.kg(kg),
    effort: effort,
  );
  test('no history and assisted exercises never invent a number', () {
    expect(run([]).reading, isNull);
    expect(run([point(1, 50)], meaning: 'assistance').reading, isNull);
  });
  test('a single spike cannot replace recent median', () {
    expect(
      run([point(1, 200), point(2, 50), point(3, 50)]).reading!.amount.asDouble,
      50,
    );
  });
  test('lb output follows equipment five-pound steps', () {
    final result = run([point(1, 50), point(2, 50)], unit: WeightUnit.lb);
    expect(result.reading!.amount.asDouble % 5, 0);
    expect(result.reading!.unit, WeightUnit.lb);
  });
  test('stale and high-rep unsupported estimates are explicit', () {
    expect(run([point(40, 50)]).reading, isNull);
    expect(
      run(
        [point(1, 50)],
        target: SetTarget(
          repsMin: 15,
          repsMax: 15,
          loadKind: 'rm',
          loadValue: 15,
        ),
      ).reading,
      isNull,
    );
  });
  test(
    'trend uses multiple sessions, but absent effort cannot trigger a forecast',
    () {
      final rows = [for (var i = 1; i <= 6; i++) point(i, i <= 3 ? 60 : 50)];
      expect(run(rows).trend, '近期上升');
      expect(run(rows).message, isNot(contains('提高一个档位')));
    },
  );
  test('known effort does not create a false trend against unknown older performances', () {
    final result = run([
      point(1, 50, effort: const Effort('rpe', 8)),
      for (var i = 2; i <= 6; i++) point(i, 50),
    ]);
    expect(result.trend, isNot('近期上升'));
  });
}
