import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/domain/local_date.dart';
import 'package:gym_tracker/domain/training_plans.dart';
import 'package:gym_tracker/domain/training_schedule.dart';

TrainingDay day(String id, {bool rest = false}) => TrainingDay(
  id: id,
  name: id,
  kind: rest ? TrainingDayKind.rest : TrainingDayKind.training,
  exerciseIds: [],
);

void main() {
  final completed = LocalDate(2026, 10, 18);
  TrainingSchedule schedule(
    List<TrainingDay> days,
    LocalDate today, {
    String? completedId = 'a',
    LocalDate? activation,
  }) => resolveTrainingSchedule(
    days: days,
    today: today,
    completedDayId: completedId,
    completedOn: completed,
    activatedOn: activation,
  );

  test(
    'completion day, tomorrow rest, then next training waits indefinitely',
    () {
      final days = [day('a'), day('r', rest: true), day('b')];
      expect(schedule(days, completed).state, TrainingScheduleState.completed);
      expect(
        schedule(days, LocalDate(2026, 10, 19)).state,
        TrainingScheduleState.rest,
      );
      expect(schedule(days, LocalDate(2026, 10, 19)).nextTrainingDay?.id, 'b');
      expect(schedule(days, LocalDate(2026, 10, 20)).day?.id, 'b');
      expect(schedule(days, LocalDate(2027, 1, 1)).day?.id, 'b');
    },
  );
  test('consecutive rest wraps across cycle boundary', () {
    final days = [
      day('r2', rest: true),
      day('b'),
      day('a'),
      day('r1', rest: true),
    ];
    expect(schedule(days, LocalDate(2026, 10, 19)).day?.id, 'r1');
    expect(schedule(days, LocalDate(2026, 10, 20)).day?.id, 'r2');
    expect(schedule(days, LocalDate(2026, 10, 21)).day?.id, 'b');
  });
  test('training followed by training stays immediately available', () {
    expect(schedule([day('a'), day('b')], completed).day?.id, 'b');
    expect(
      schedule([day('a'), day('b')], completed).state,
      TrainingScheduleState.training,
    );
  });
  test(
    'leading rest starts activation day and never skips waiting training',
    () {
      final days = [day('r', rest: true), day('b'), day('r2', rest: true)];
      expect(
        schedule(
          days,
          completed,
          completedId: null,
          activation: completed,
        ).day?.id,
        'r',
      );
      expect(
        schedule(
          days,
          LocalDate(2026, 10, 19),
          completedId: null,
          activation: completed,
        ).day?.id,
        'b',
      );
      expect(
        schedule(
          days,
          LocalDate(2027, 1, 1),
          completedId: null,
          activation: completed,
        ).day?.id,
        'b',
      );
    },
  );
  test('deleted completion falls back to activation and first entry', () {
    final days = [day('r', rest: true), day('b')];
    expect(
      schedule(
        days,
        LocalDate(2026, 10, 19),
        completedId: 'deleted',
        activation: completed,
      ).day?.id,
      'b',
    );
  });
  test(
    'all-rest cycles from activation and from a usable historical completion',
    () {
      final days = [day('a', rest: true), day('b', rest: true)];
      expect(
        schedule(
          days,
          completed,
          completedId: null,
          activation: completed,
        ).day?.id,
        'a',
      );
      expect(
        schedule(
          days,
          LocalDate(2026, 10, 21),
          completedId: null,
          activation: completed,
        ).day?.id,
        'b',
      );
      expect(schedule(days, completed).state, TrainingScheduleState.completed);
      expect(schedule(days, LocalDate(2026, 10, 19)).day?.id, 'b');
      expect(schedule(days, LocalDate(2026, 10, 20)).day?.id, 'a');
      expect(schedule(days, LocalDate(2026, 10, 20)).nextTrainingDay, isNull);
    },
  );
  test('empty, missing activation and clock rollback are bounded', () {
    expect(schedule([], completed).state, TrainingScheduleState.empty);
    expect(
      schedule([day('r', rest: true)], completed, completedId: null).state,
      TrainingScheduleState.rest,
    );
    expect(
      schedule(
        [day('r', rest: true), day('b')],
        LocalDate(2026, 10, 17),
        completedId: null,
        activation: completed,
      ).day?.id,
      'r',
    );
    expect(
      schedule([day('a'), day('r', rest: true)], LocalDate(2026, 10, 17)).state,
      TrainingScheduleState.completed,
    );
  });
  test(
    'civil dates cross year and leap day without elapsed-hour arithmetic',
    () {
      expect(LocalDate(2027, 1, 1).daysSince(LocalDate(2026, 12, 31)), 1);
      expect(LocalDate(2024, 3, 1).daysSince(LocalDate(2024, 2, 28)), 2);
    },
  );
}
