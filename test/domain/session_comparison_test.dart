import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/domain/session_comparison.dart';
import 'package:gym_tracker/domain/session_summary.dart';
import 'package:gym_tracker/domain/set_detail.dart';
import 'package:gym_tracker/domain/training_prescription.dart';
import 'package:gym_tracker/domain/types.dart';
import 'package:gym_tracker/domain/weight_value.dart';

SetEntry set(
  String id, {
  double weight = 60,
  int reps = 8,
  bool completed = true,
  EquipmentWeight? reading,
  SetDetail? detail,
}) => SetEntry(
  id: id,
  sessionExerciseId: 'occurrence-$id',
  position: 0,
  weight: reading?.kilograms ?? weight,
  recordedWeight: reading,
  reps: reps,
  isCompleted: completed,
  detail: detail,
);

ExerciseSummary occurrence(
  String id,
  List<SetEntry> sets, {
  String name = '卧推',
}) => ExerciseSummary(exerciseId: id, exerciseName: name, sets: sets);

SessionSummary summary(
  String id,
  int at,
  List<ExerciseSummary> exercises, {
  bool finished = true,
}) => SessionSummary(
  session: WorkoutSession(
    id: id,
    startedAt: at,
    finishedAt: finished ? at + 100 : null,
  ),
  exercises: exercises,
  durationSeconds: 0,
  totalSets: exercises.fold(0, (n, e) => n + e.sets.length),
  volumeLoad: 0,
);

void main() {
  test(
    'groups repeated occurrences by stable ID in first-occurrence order',
    () {
      final first = occurrence('bench', [set('one')]);
      final second = occurrence('bench', [set('two')]);
      final current = summary('current', 300, [
        first,
        occurrence('row', [set('row')], name: '划船'),
        second,
      ]);
      final previous = summary('previous', 200, [
        occurrence('bench', [set('old', weight: 50, reps: 10)]),
      ]);

      final result = buildSessionComparisons(current, [previous]);

      expect(result.map((e) => e.exerciseId), ['bench', 'row']);
      final bench = result.first;
      expect(bench.current.occurrences, [same(first), same(second)]);
      expect(bench.current.logicalSetCount, 2);
      expect(bench.current.volumeLoad, 960);
      expect(bench.previous!.session.id, 'previous');
      expect(bench.previous!.volumeLoad, 500);
      expect(result.last.previous, isNull);
    },
  );

  test(
    'uses the latest strictly earlier completed session, with stable ID ties',
    () {
      final current = summary('current', 300, [
        occurrence('bench', [set('now')]),
      ]);
      SessionSummary record(String id, int at, {bool finished = true}) =>
          summary(id, at, [
            occurrence('bench', [set(id)]),
          ], finished: finished);
      final history = [
        record('current', 100),
        record('old', 100),
        record('a-tie', 200),
        record('z-tie', 200),
        record('in-progress', 250, finished: false),
        record('same-time', 300),
        record('future', 400),
      ];

      expect(
        buildSessionComparisons(current, history).single.previous!.session.id,
        'z-tie',
      );
      expect(
        buildSessionComparisons(
          current,
          history.reversed,
        ).single.previous!.session.id,
        'z-tie',
      );
    },
  );

  test('same names never merge different exercise IDs and an empty recent occurrence is ignored', () {
    final current = summary('current', 300, [
      occurrence('bench', [set('now')]),
    ]);
    final result = buildSessionComparisons(current, [
      summary('wrong-id', 250, [
        occurrence('another-bench', [set('other')]),
      ]),
      summary('empty', 240, [occurrence('bench', [])]),
      summary('pending', 230, [
        occurrence('bench', [set('pending', completed: false)]),
      ]),
      summary('correct', 200, [
        occurrence('bench', [set('old')]),
      ]),
    ]);

    expect(result.single.previous!.session.id, 'correct');
  });

  test(
    'keeps first records honest and does not compare an unfinished workout',
    () {
      final current = summary('first', 300, [
        occurrence('bench', [set('first')]),
      ]);
      expect(buildSessionComparisons(current, []).single.previous, isNull);
      expect(
        buildSessionComparisons(
          summary('running', 300, [
            occurrence('bench', [set('one')]),
          ], finished: false),
          [current],
        ),
        isEmpty,
      );
      expect(
        buildSessionComparisons(summary('empty', 300, []), [current]),
        isEmpty,
      );
    },
  );

  test('preserves native units, efforts, role, early ending and each recorded segment', () {
    final detail = SetDetail(
      role: 'work',
      effort: const Effort('rir', 2),
      target: SetTarget(
        repsMin: 5,
        repsMax: 5,
        extraReps: [4, 3, 2],
        pauseSeconds: 5,
      ),
      firstCompletedAt: 10,
      endedEarly: true,
      continuations: [
        RecordedSegment(
          reading: EquipmentWeight.kg(30),
          reps: 4,
          completedAt: 20,
          pauseSeconds: 5,
        ),
        RecordedSegment(
          reading: EquipmentWeight(DecimalReading.parse('50'), WeightUnit.lb),
          reps: 3,
          completedAt: 30,
          pauseSeconds: 7,
          effort: const Effort('rpe', 9),
        ),
      ],
    );
    final segmented = set(
      'segmented',
      reading: EquipmentWeight(DecimalReading.parse('100'), WeightUnit.lb),
      reps: 5,
      detail: detail,
    );
    final warmup = set(
      'warmup',
      weight: 10,
      reps: 10,
      detail: SetDetail(role: 'warmup'),
    );
    final unknown = set('legacy', weight: 20);
    final result = buildSessionComparisons(
      summary('current', 300, [
        occurrence('bench', [warmup, unknown, segmented]),
      ]),
      [],
    ).single.current;

    expect(result.logicalSetCount, 3);
    expect(result.volumeLoad, closeTo(674.8350405, 1e-8));
    final stored = result.occurrences.single.sets;
    expect(stored[0].detail!.role, 'warmup');
    expect(stored[1].detail, isNull);
    expect(stored[2].equipmentWeight.amount.text, '100');
    expect(stored[2].equipmentWeight.unit, WeightUnit.lb);
    expect(stored[2].detail, same(detail));
    expect(stored[2].detail!.continuations[0].effort, isNull);
    expect(stored[2].detail!.continuations[1].effort!.label, 'RPE 9');
    expect(stored[2].detail!.endedEarly, isTrue);
  });

  test(
    'pending parents and their partial work never count as completed groups',
    () {
      final pending = set(
        'pending',
        weight: 999,
        reps: 99,
        completed: false,
        detail: SetDetail(
          firstCompletedAt: 10,
          continuations: [
            RecordedSegment(
              reading: EquipmentWeight.kg(999),
              reps: 99,
              completedAt: 20,
            ),
          ],
        ),
      );
      final done = set('done', weight: 20);
      final result = buildSessionComparisons(
        summary('current', 300, [
          occurrence('bench', [pending, done]),
        ]),
        [],
      ).single.current;

      expect(result.logicalSetCount, 1);
      expect(result.occurrences.single.sets, [same(done)]);
      expect(result.volumeLoad, 160);
      expect(recordedSetsVolume([pending, done]), 160);
    },
  );
}
