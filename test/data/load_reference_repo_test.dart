import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/repositories/load_reference_repo.dart';
import 'package:gym_tracker/data/repositories/exercise_preferences_repo.dart';
import 'package:gym_tracker/data/repositories/set_detail_repo.dart';
import 'package:gym_tracker/data/repositories/set_repo.dart';
import 'package:gym_tracker/domain/set_detail.dart';
import 'package:gym_tracker/domain/training_prescription.dart';
import 'package:gym_tracker/domain/weight_value.dart';

import '../support/workout_fixture.dart';

void main() {
  late WorkoutFixture f;
  late String pid;
  setUp(() async {
    f = await workoutFixture();
    pid = f.controller.currentExercise!.sets.single.id;
    for (var i = 1; i <= 3; i++) {
      await f.db.run(
        'INSERT INTO session(id,started_at,finished_at,origin) VALUES(?,?,?,?)',
        [
          'h$i',
          f.clock.value - i * 86400000,
          f.clock.value - i * 86400000 + 1000,
          'manual',
        ],
      );
      await f.db.run(
        'INSERT INTO session_exercise(id,session_id,exercise_id,position) VALUES(?,?,?,0)',
        ['he$i', 'h$i', f.benchId],
      );
      await f.db.run(
        'INSERT INTO set_entry(id,session_exercise_id,position,weight,reps,is_completed,completed_at,source_weight,source_unit) VALUES(?,?,0,40,8,1,?,?,?)',
        ['hs$i', 'he$i', f.clock.value - i * 86400000 + 500, '40', 'kg'],
      );
      await writeSetDetail(
        f.db,
        'hs$i',
        SetDetail(role: 'work', effort: const Effort('rpe', 8)),
      );
    }
    await writeSetDetail(
      f.db,
      pid,
      SetDetail(
        role: 'work',
        target: SetTarget(repsMin: 8, repsMax: 8, loadKind: 'rm', loadValue: 8),
      ),
    );
  });
  test('adoption changes only pending reading and saves evidence; changed history invalidates token', () async {
    final reference = await loadReferenceForPending(
      f.db,
      pid,
      now: f.clock.value,
    );
    expect(reference.reading, isNotNull);
    expect(reference.evidence.length, 3);
    expect(
      (await listSets(
        f.db,
        f.controller.currentSessionExerciseId!,
      )).single.weight,
      20,
    );
    await applyLoadReference(
      f.db,
      pendingSetId: pid,
      expectedToken: reference.token,
      now: f.clock.value,
    );
    final set = (await listSets(
      f.db,
      f.controller.currentSessionExerciseId!,
    )).single;
    expect(set.reps, 8);
    expect(set.isCompleted, isFalse);
    expect(set.detail!.effort, isNull);
    expect(set.detail!.reference, contains('personal-v1'));
    final next = await loadReferenceForPending(f.db, pid, now: f.clock.value);
    await f.db.run("UPDATE set_entry SET reps=7 WHERE id='hs1'");
    await expectLater(
      applyLoadReference(
        f.db,
        pendingSetId: pid,
        expectedToken: next.token,
        now: f.clock.value,
      ),
      throwsException,
    );
  });
  test(
    'unit and step changes invalidate a previously displayed estimate',
    () async {
      final old = await loadReferenceForPending(f.db, pid, now: f.clock.value);
      final pref = (await readExercisePreferences(f.db, [
        f.benchId,
      ]))[f.benchId]!;
      await saveExercisePreference(
        f.db,
        f.benchId,
        expectedToken: pref.token,
        weightUnit: WeightUnit.lb,
        lbStep: DecimalReading.parse('5'),
      );
      await expectLater(
        applyLoadReference(
          f.db,
          pendingSetId: pid,
          expectedToken: old.token,
          now: f.clock.value,
        ),
        throwsException,
      );
      final next = await loadReferenceForPending(f.db, pid, now: f.clock.value);
      expect(next.reading!.unit, WeightUnit.lb);
      expect(next.reading!.amount.asDouble % 5, 0);
    },
  );
  test(
    'warmup-only recent sessions do not hide older comparable facts',
    () async {
      for (var i = 1; i <= 9; i++) {
        await f.db.run(
          'INSERT INTO session(id,started_at,finished_at) VALUES(?,?,?)',
          ['w$i', f.clock.value - i * 1000, f.clock.value - i * 1000 + 100],
        );
        await f.db.run(
          'INSERT INTO session_exercise(id,session_id,exercise_id,position) VALUES(?,?,?,0)',
          ['we$i', 'w$i', f.benchId],
        );
        await f.db.run(
          'INSERT INTO set_entry(id,session_exercise_id,position,weight,reps,is_completed) VALUES(?,?,0,10,8,1)',
          ['ws$i', 'we$i'],
        );
        await writeSetDetail(f.db, 'ws$i', SetDetail(role: 'warmup'));
      }
      final reference = await loadReferenceForPending(
        f.db,
        pid,
        now: f.clock.value,
      );
      expect(reference.evidence.length, 3);
      expect(reference.reading, isNotNull);
    },
  );
}
