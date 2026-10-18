import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/domain/set_detail.dart';
import 'package:gym_tracker/domain/training_prescription.dart';
import 'package:gym_tracker/domain/weight_value.dart';

void main() {
  test('actual continuation survives a codec round trip without first-part duplication', () {
    final detail = SetDetail(
      target: SetTarget(
        repsMin: 10,
        repsMax: 10,
        extraReps: [5],
        pauseSeconds: 5,
      ),
      firstCompletedAt: 1000,
      effort: const Effort('rpe', 9),
      continuations: [
        RecordedSegment(
          reading: EquipmentWeight.kg(30),
          reps: 5,
          completedAt: 7000,
          pauseSeconds: 5,
        ),
      ],
    );
    final copy = SetDetail.decode(detail.encode());
    expect(copy.firstCompletedAt, 1000);
    expect(copy.continuations.single.reps, 5);
    expect(copy.continuations.single.reading.kilograms, 30);
  });
}
