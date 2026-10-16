import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/repositories/backup_repo.dart';
import 'package:gym_tracker/data/repositories/set_repo.dart';
import 'package:gym_tracker/data/repositories/workout_edit_repo.dart';
import 'package:gym_tracker/data/repositories/workout_write_repo.dart';
import 'package:gym_tracker/domain/record_management.dart';
import 'package:gym_tracker/domain/workout_edit.dart';
import 'package:gym_tracker/data/repositories/session_repo.dart';

import '../support/workout_fixture.dart';
import 'backup_repo_test.dart' show FailingExecutor;

void main() {
  test('foreign completed set cannot be edited using a valid token from current session', () async {
    final f = await workoutFixture();
    await f.controller.completeCurrentSet(40, 8);
    final edit = (await f.controller.previewCompletedSet(
      f.controller.currentExercise!.sets.first.id,
    ))!;
    final foreign = await createSession(f.db);
    await finishSession(f.db, foreign.id, f.clock.value);
    final se = await addExerciseToSession(f.db, foreign.id, f.rowId);
    final set = await addSet(f.db, se.id, 25, 10);
    await completeSet(f.db, set.id, f.clock.value);
    final forged = CompletedSetEdit(edit.sessionId, set, edit.token);
    final before = (await exportBackup(f.db, exportedAt: 0)).data;
    await expectLater(
      updateCompletedSet(f.db, forged, weight: 99, reps: 1),
      throwsA(isA<RecordManagementException>()),
    );
    expect((await exportBackup(f.db, exportedAt: 0)).data, before);
  });
  test(
    'undo failure after resetting completion restores every original field',
    () async {
      final f = await workoutFixture();
      await f.controller.completeCurrentSet(40, 8);
      final preview = (await f.controller.previewUndo())!;
      final before = (await exportBackup(f.db, exportedAt: 0)).data;
      final faulty = FailingExecutor(
        f.db,
        'UPDATE set_entry SET is_completed=0',
        StateError('injected'),
      );
      await expectLater(
        undoCompletedSet(faulty, preview, now: f.clock.value),
        throwsStateError,
      );
      expect((await exportBackup(f.db, exportedAt: 0)).data, before);
    },
  );
  test('editing changes only actual values and leaves rest and prepared weight intact', () async {
    final f = await workoutFixture();
    await f.controller.completeCurrentSet(40, 10);
    final active = f.controller.currentExercise!;
    await savePendingWeight(
      f.db,
      sessionId: f.controller.session!.id,
      pendingSetId: active.sets.last.id,
      weight: 42.5,
    );
    final before = await f.db.all<Map<String, Object?>>(
      'SELECT * FROM set_entry ORDER BY rowid',
    );
    final edit = await inspectCompletedSet(
      f.db,
      f.controller.session!.id,
      active.sets.first.id,
    );
    await updateCompletedSet(f.db, edit, weight: 40, reps: 8);
    final after = await f.db.all<Map<String, Object?>>(
      'SELECT * FROM set_entry ORDER BY rowid',
    );
    expect(after, [
      {...before.first, 'reps': 8},
      before.last,
    ]);
    expect((after.first['weight'] as num) * (after.first['reps'] as num), 320);
    await expectLater(
      updateCompletedSet(f.db, edit, weight: 50, reps: 7),
      throwsA(isA<RecordManagementException>()),
    );
  });
  test('undo restores same id and values, deletes exact placeholder and permits recompletion', () async {
    final f = await workoutFixture();
    final original = f.controller.currentExercise!.sets.single;
    await f.controller.completeCurrentSet(40, 8);
    final sid = f.controller.session!.id,
        se = f.controller.currentSessionExerciseId!;
    final preview = (await inspectUndoSet(f.db, sid, se, now: f.clock.value))!;
    await undoCompletedSet(f.db, preview, now: f.clock.value);
    final restored = await listSets(f.db, se);
    expect(restored.single.id, original.id);
    expect(restored.single.weight, 40);
    expect(restored.single.isCompleted, false);
    expect(restored.single.restStartedAt, isNull);
    await expectLater(
      undoCompletedSet(f.db, preview, now: f.clock.value),
      throwsA(isA<RecordManagementException>()),
    );
    await f.controller.resume();
    await f.controller.completeCurrentSet(40, 7);
    expect(
      (await listSets(f.db, se)).where((s) => s.isCompleted),
      hasLength(1),
    );
  });
  test(
    'beginning next set invalidates old undo; 30 minute gate disallows undo',
    () async {
      final f = await workoutFixture();
      await f.controller.completeCurrentSet(40, 8);
      final sid = f.controller.session!.id,
          se = f.controller.currentSessionExerciseId!;
      final preview = (await inspectUndoSet(
        f.db,
        sid,
        se,
        now: f.clock.value,
      ))!;
      expect(
        await inspectUndoSet(f.db, sid, se, now: f.clock.value + 31 * 60000),
        isNull,
      );
      await f.controller.beginNextSet();
      final before = (await exportBackup(f.db, exportedAt: 0)).data;
      await expectLater(
        undoCompletedSet(f.db, preview, now: f.clock.value),
        throwsA(isA<RecordManagementException>()),
      );
      expect((await exportBackup(f.db, exportedAt: 0)).data, before);
    },
  );
  test(
    'undo failure after deleting placeholder rolls entire session back',
    () async {
      final f = await workoutFixture();
      await f.controller.completeCurrentSet(40, 8);
      final preview = (await f.controller.previewUndo())!;
      final before = (await exportBackup(f.db, exportedAt: 0)).data;
      final faulty = FailingExecutor(
        f.db,
        'DELETE FROM set_entry',
        StateError('injected'),
      );
      await expectLater(
        undoCompletedSet(faulty, preview, now: f.clock.value),
        throwsStateError,
      );
      expect((await exportBackup(f.db, exportedAt: 0)).data, before);
    },
  );
  test('same millisecond and tied positions use rowid to identify last completed set', () async {
    final f = await workoutFixture();
    await f.controller.completeCurrentSet(40, 8);
    await f.controller.beginNextSet();
    await f.controller.completeCurrentSet(40, 7);
    final se = f.controller.currentSessionExerciseId!;
    await f.db.run(
      'UPDATE set_entry SET position=0 WHERE session_exercise_id=?',
      [se],
    );
    await f.db.run('PRAGMA reverse_unordered_selects=ON');
    final sets = await listSets(f.db, se);
    final preview = (await inspectUndoSet(
      f.db,
      f.controller.session!.id,
      se,
      now: f.clock.value,
    ))!;
    expect(preview.setId, sets[1].id);
    expect(preview.pendingSetId, sets[2].id);
    await undoCompletedSet(f.db, preview, now: f.clock.value);
    expect((await listSets(f.db, se)).first.isCompleted, true);
  });
}
