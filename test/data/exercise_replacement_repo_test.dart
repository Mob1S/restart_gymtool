import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/repositories/backup_repo.dart';
import 'package:gym_tracker/data/repositories/exercise_replacement_repo.dart';
import 'package:gym_tracker/data/repositories/set_repo.dart';
import 'package:gym_tracker/domain/workout_edit.dart';

import '../support/workout_fixture.dart';
import '../support/workout_faults.dart';

import 'package:gym_tracker/state/active_session_controller.dart';

import 'backup_repo_test.dart' show FailingExecutor;

void main() {
  test(
    'committed replacement refresh failure cannot create a second replacement',
    () async {
      final f = await workoutFixture();
      final faults = WorkoutFaults();
      final c = ActiveSessionController(
        WorkoutFaultExecutor(f.db, faults),
        now: f.clock.call,
      );
      addTearDown(c.dispose);
      await c.resume();
      final preview = (await c.previewReplacement(f.rowId))!;
      faults.failReload = true;
      expect(
        await c.replaceExercise(preview),
        WorkoutWriteResult.savedNeedsReload,
      );
      expect(
        await c.replaceExercise(preview),
        WorkoutWriteResult.savedNeedsReload,
      );
      await c.resume();
      expect(c.exercises, hasLength(1));
      expect(c.exercises.single.sessionExercise.exerciseId, f.rowId);
    },
  );
  test('failure after retaining old scores restores active source rest and placeholder', () async {
    final f = await workoutFixture();
    await f.controller.completeCurrentSet(40, 8);
    final preview = (await f.controller.previewReplacement(f.rowId))!;
    final before = (await exportBackup(f.db, exportedAt: 0)).data;
    final faulty = FailingExecutor(
      f.db,
      'UPDATE set_entry SET rest_started_at=NULL',
      StateError('injected'),
    );
    await expectLater(
      replaceWorkoutExercise(faulty, preview),
      throwsStateError,
    );
    expect((await exportBackup(f.db, exportedAt: 0)).data, before);
  });
  test('replacing sole zero-set exercise leaves exactly one independent pending item', () async {
    final f = await workoutFixture();
    final source = f.controller.currentSessionExerciseId!;
    final preview = (await f.controller.previewReplacement(f.rowId))!;
    expect(
      await f.controller.replaceExercise(preview),
      WorkoutWriteResult.saved,
    );
    expect(f.controller.recordingExercises, hasLength(1));
    expect(f.controller.currentExercise!.sessionExercise.exerciseId, f.rowId);
    expect(f.controller.currentSessionExerciseId, isNot(source));
    expect(await listSets(f.db, source), isEmpty);
  });
  test(
    'two completed sets retained byte-for-byte except cancelled active rest',
    () async {
      final f = await workoutFixture();
      await f.controller.completeCurrentSet(40, 8);
      f.clock.value += 30000;
      await f.controller.beginNextSet();
      f.clock.value += 1000;
      await f.controller.completeCurrentSet(40, 7);
      final source = f.controller.currentSessionExerciseId!;
      final before = await f.db.all<Map<String, Object?>>(
        'SELECT * FROM set_entry WHERE session_exercise_id=? AND is_completed=1 ORDER BY position,rowid',
        [source],
      );
      final preview = (await f.controller.previewReplacement(f.rowId))!;
      expect(
        await f.controller.replaceExercise(preview),
        WorkoutWriteResult.saved,
      );
      expect(
        await f.db.all(
          'SELECT * FROM set_entry WHERE session_exercise_id=? ORDER BY position,rowid',
          [source],
        ),
        before.map((r) => {...r, 'rest_started_at': null}).toList(),
      );
      expect(f.controller.currentExercise!.sets.single.weight, 20);
      expect(f.controller.exercises, hasLength(2));
    },
  );
  test(
    'existing target is a new occurrence and other active rest stays unchanged',
    () async {
      final f = await workoutFixture();
      await f.controller.addExercise(f.rowId);
      await f.controller.completeCurrentSet(25, 6);
      final row = f.controller.currentSessionExerciseId!;
      final before = await f.db.all(
        'SELECT * FROM set_entry WHERE session_exercise_id=? ORDER BY rowid',
        [row],
      );
      await f.controller.setCurrentIndex(0);
      await f.controller.replaceExercise(
        (await f.controller.previewReplacement(f.rowId))!,
      );
      expect(f.controller.recordingExercises, hasLength(2));
      expect(f.controller.currentSessionExerciseId, isNot(row));
      expect(
        await f.db.all(
          'SELECT * FROM set_entry WHERE session_exercise_id=? ORDER BY rowid',
          [row],
        ),
        before,
      );
      expect(f.controller.currentExercise!.sets.single.weight, 20);
    },
  );
  for (final prefix in [
    'INSERT INTO set_entry',
    'DELETE FROM session_exercise',
    'UPDATE session_exercise SET position',
  ]) {
    test('replacement failure at $prefix rolls all fields back', () async {
      final f = await workoutFixture();
      final preview = (await f.controller.previewReplacement(f.rowId))!;
      final before = (await exportBackup(f.db, exportedAt: 0)).data;
      await expectLater(
        replaceWorkoutExercise(
          FailingExecutor(f.db, prefix, StateError('injected')),
          preview,
        ),
        throwsStateError,
      );
      expect((await exportBackup(f.db, exportedAt: 0)).data, before);
    });
  }
  test('source itself is unchanged, stale replacement rejected', () async {
    final f = await workoutFixture();
    final before = (await exportBackup(f.db, exportedAt: 0)).data;
    expect(
      await f.controller.replaceExercise(
        (await f.controller.previewReplacement(f.benchId))!,
      ),
      WorkoutWriteResult.unchanged,
    );
    expect((await exportBackup(f.db, exportedAt: 0)).data, before);
    final preview = (await f.controller.previewReplacement(f.rowId))!;
    await f.controller.completeCurrentSet(40, 8);
    expect(
      await f.controller.replaceExercise(preview),
      WorkoutWriteResult.conflict,
    );
  });
}
