import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/state/active_session_controller.dart';
import 'package:gym_tracker/domain/workout_edit.dart';

import '../support/workout_fixture.dart';
import '../support/workout_faults.dart';

void main() {
  test('batch preserves order, deduplicates one submission, permits later repetition and notifies once', () async {
    final f = await workoutFixture();
    var changes = 0;
    final c = ActiveSessionController(
      f.db,
      now: f.clock.call,
      onDataChanged: () => changes++,
    );
    addTearDown(c.dispose);
    await c.resume();
    expect(
      await c.addExercises([f.rowId, f.benchId, f.rowId]),
      WorkoutWriteResult.saved,
    );
    expect(c.exercises.map((e) => e.sessionExercise.exerciseId), [
      f.benchId,
      f.rowId,
      f.benchId,
    ]);
    expect(c.currentExercise!.sessionExercise.exerciseId, f.rowId);
    expect(changes, 1);
    await c.addExercises([f.rowId]);
    expect(c.exercises, hasLength(4));
    expect(changes, 2);
  });
  test('committed refresh failure cannot resubmit the batch before successful reload', () async {
    final f = await workoutFixture();
    final faults = WorkoutFaults();
    final c = ActiveSessionController(
      WorkoutFaultExecutor(f.db, faults),
      now: f.clock.call,
    );
    addTearDown(c.dispose);
    await c.resume();
    faults.failReload = true;
    expect(
      await c.addExercises([f.rowId]),
      WorkoutWriteResult.savedNeedsReload,
    );
    expect(
      await c.addExercises([f.rowId]),
      WorkoutWriteResult.savedNeedsReload,
    );
    await c.resume();
    expect(c.exercises, hasLength(2));
  });
  test('completion and finish cannot interleave', () async {
    final f = await workoutFixture();
    final completion = f.controller.completeCurrentSet(40, 8);
    expect(await f.controller.endWorkout(), isNull);
    await completion;
    expect(
      f.controller.currentExercise!.sets.where((s) => s.isCompleted),
      hasLength(1),
    );
    expect(await f.controller.endWorkout(), isNotNull);
  });
}
