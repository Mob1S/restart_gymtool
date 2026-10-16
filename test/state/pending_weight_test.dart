import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/repositories/backup_repo.dart';
import 'package:gym_tracker/state/active_session_controller.dart';
import 'package:gym_tracker/domain/workout_edit.dart';

import '../support/workout_fixture.dart';
import '../data/backup_repo_test.dart' show FailingExecutor;

void main() {
  test('unchanged prepared weight does not write or notify', () async {
    final f = await workoutFixture();
    final pending = f.controller.currentExercise!.sets.single;
    f.controller.stagePendingWeight(pending.id, pending.weight);
    expect(
      await f.controller.flushPendingWeight(),
      WorkoutWriteResult.unchanged,
    );
  });
  test('pending weight persists only weight, begin waits and actual reps are chosen on completion', () async {
    final f = await workoutFixture();
    await f.controller.completeCurrentSet(40, 8);
    final c = f.controller, pending = c.currentExercise!.sets.last;
    c.stagePendingWeight(pending.id, 42.5);
    f.clock.value += 30000;
    await c.beginNextSet();
    expect(c.currentExercise!.sets.last.weight, 42.5);
    expect(c.currentExercise!.sets.last.reps, 8);
    expect(c.currentExercise!.sets.first.weight, 40);
    expect(c.currentExercise!.sets.first.restSeconds, 30);
    await c.completeCurrentSet(42.5, 6);
    expect(c.currentExercise!.sets.where((s) => s.isCompleted).last.reps, 6);
    expect(
      c.currentExercise!.sets.where((s) => s.isCompleted).last.weight,
      42.5,
    );
  });
  test('reset invalidates staged generation, restore conflicts after prepared weight change', () async {
    final f = await workoutFixture();
    await f.controller.completeCurrentSet(40, 8);
    final c = f.controller, pending = c.currentExercise!.sets.last;
    c.stagePendingWeight(pending.id, 42.5);
    c.reset();
    await c.resume();
    expect(await c.flushPendingWeight(), WorkoutWriteResult.unchanged);
    expect(c.currentExercise!.sets.last.weight, 40);
    final backup = await exportBackup(f.db, exportedAt: 0);
    final preview = await inspectBackup(f.db, backup);
    c.stagePendingWeight(pending.id, 42.5);
    await c.flushPendingWeight();
    await expectLater(restoreBackup(f.db, preview), throwsException);
  });
  test(
    'failed pending save retains input and prevents starting next set',
    () async {
      final f = await workoutFixture();
      await f.controller.completeCurrentSet(40, 8);
      final faulty = ActiveSessionController(
        FailingExecutor(
          f.db,
          'UPDATE set_entry SET weight=',
          StateError('injected'),
        ),
        now: f.clock.call,
      );
      addTearDown(faulty.dispose);
      await faulty.resume();
      final pending = faulty.currentExercise!.sets.last;
      faulty.stagePendingWeight(pending.id, 42.5);
      await faulty.beginNextSet();
      expect(faulty.stagedWeight(pending.id), 42.5);
      expect(faulty.writeMessage, isNotNull);
      expect(faulty.currentExercise!.sets.first.restStartedAt, isNotNull);
    },
  );
}
