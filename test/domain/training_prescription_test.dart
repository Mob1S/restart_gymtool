import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/domain/training_prescription.dart';

void main() {
  test(
    'rest pause keeps each segment and effort independent of repetitions',
    () {
      final target = SetTarget(
        repsMin: 10,
        repsMax: 10,
        extraReps: [5],
        pauseSeconds: 5,
        effort: const Effort('rpe', 8),
      );
      final restored = SetTarget.fromJson(target.toJson());
      expect(restored.segmentReps, [10, 5]);
      expect(restored.effort!.value, 8);
      expect(restored.label, contains('5 秒'));
    },
  );
  test('strict codecs reject inverted ranges and unknown fields', () {
    expect(
      () => SetTarget.fromJson({
        ...SetTarget(repsMin: 8, repsMax: 12).toJson(),
        'repsMax': 7,
      }),
      throwsFormatException,
    );
    expect(
      () => SetTarget.fromJson({
        ...SetTarget(repsMin: 8, repsMax: 8).toJson(),
        'typo': true,
      }),
      throwsFormatException,
    );
  });
  test('unknown effort stays unknown and low RPE is not exact reserve', () {
    expect(const Effort('rpe', 8).reserveLowerBound, 2);
    expect(const Effort('rpe', 8.5).reserveLowerBound, 1);
    expect(const Effort('rpe', 6, bound: 'below').reserveLowerBound, isNull);
    expect(
      SetTarget.fromJson(SetTarget(repsMin: 12, repsMax: 12).toJson()).effort,
      isNull,
    );
  });
  test(
    'program round trip preserves duplicate exercise occurrence targets',
    () {
      final program = TrainingProgram(
        stages: [
          ProgramStage(
            id: 'one',
            name: '第一周',
            targets: {
              'occurrence-a': [SetTarget(repsMin: 8, repsMax: 8)],
              'occurrence-b': [SetTarget(repsMin: 12, repsMax: 12)],
            },
          ),
        ],
        currentStageId: 'one',
      );
      final copy = TrainingProgram.decode(program.encode());
      expect(copy.current.targets['occurrence-a']!.single.repsMin, 8);
      expect(copy.current.targets['occurrence-b']!.single.repsMin, 12);
    },
  );
}
