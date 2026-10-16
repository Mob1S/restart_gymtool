import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/repositories/backup_repo.dart';
import 'package:gym_tracker/data/repositories/exercise_repo.dart';
import 'package:gym_tracker/data/repositories/exercise_picker_repo.dart';
import 'package:gym_tracker/data/repositories/exercise_preferences_repo.dart';
import 'package:gym_tracker/data/repositories/record_management_repo.dart';
import 'package:gym_tracker/data/repositories/session_repo.dart';
import 'package:gym_tracker/data/repositories/set_repo.dart';
import 'package:gym_tracker/data/repositories/workout_edit_repo.dart';
import 'package:gym_tracker/data/repositories/workout_write_repo.dart';
import 'package:gym_tracker/domain/backup.dart';
import 'package:gym_tracker/domain/record_management.dart';

import '../support/workout_fixture.dart';
import 'backup_repo_test.dart' show FailingExecutor;

void main() {
  test('another exercise completion invalidates previous undo without changing either score', () async {
    final f = await workoutFixture();
    await f.controller.completeCurrentSet(40, 8);
    final preview = (await f.controller.previewUndo())!;
    await f.controller.addExercise(f.rowId);
    await f.controller.completeCurrentSet(25, 6);
    final before = (await exportBackup(f.db, exportedAt: 0)).data;
    await expectLater(
      undoCompletedSet(f.db, preview, now: f.clock.value),
      throwsA(isA<RecordManagementException>()),
    );
    expect((await exportBackup(f.db, exportedAt: 0)).data, before);
  });
  test('finished workout rejects previously valid edit and undo', () async {
    final f = await workoutFixture();
    await f.controller.completeCurrentSet(40, 8);
    final edit = (await f.controller.previewCompletedSet(
      f.controller.currentExercise!.sets.first.id,
    ))!;
    final undo = (await f.controller.previewUndo())!;
    await f.controller.endWorkout();
    final before = (await exportBackup(f.db, exportedAt: 0)).data;
    await expectLater(
      updateCompletedSet(f.db, edit, weight: 50, reps: 1),
      throwsA(isA<RecordManagementException>()),
    );
    await expectLater(
      undoCompletedSet(f.db, undo, now: f.clock.value),
      throwsA(isA<RecordManagementException>()),
    );
    expect((await exportBackup(f.db, exportedAt: 0)).data, before);
  });
  test('hidden source can be corrected but has no undo placeholder', () async {
    final f = await workoutFixture();
    await f.controller.completeCurrentSet(40, 8);
    final sid = f.controller.session!.id,
        se = f.controller.currentSessionExerciseId!,
        set = f.controller.currentExercise!.sets.first.id;
    await f.db.transaction((tx) => retainCompletedSets(tx, se));
    expect(await inspectUndoSet(f.db, sid, se, now: f.clock.value), isNull);
    await updateCompletedSet(
      f.db,
      await inspectCompletedSet(f.db, sid, set),
      weight: 40,
      reps: 7,
    );
    expect((await listSets(f.db, se)).single.reps, 7);
  });
  test(
    'prepared weight changes invalidate an earlier undo confirmation',
    () async {
      final f = await workoutFixture();
      await f.controller.completeCurrentSet(40, 8);
      final preview = (await f.controller.previewUndo())!;
      await savePendingWeight(
        f.db,
        sessionId: f.controller.session!.id,
        pendingSetId: preview.pendingSetId,
        weight: 42.5,
      );
      final before = (await exportBackup(f.db, exportedAt: 0)).data;
      await expectLater(
        undoCompletedSet(f.db, preview, now: f.clock.value),
        throwsA(isA<RecordManagementException>()),
      );
      expect((await exportBackup(f.db, exportedAt: 0)).data, before);
    },
  );
  for (final missing in [true, false]) {
    test(
      'batch ${missing ? 'missing' : 'archived'} target leaves all existing data unchanged',
      () async {
        final f = await workoutFixture();
        if (!missing) {
          await f.db.run('UPDATE exercise SET is_archived=1 WHERE id=?', [
            f.rowId,
          ]);
        }
        final before = (await exportBackup(f.db, exportedAt: 0)).data;
        await expectLater(
          addWorkoutExercises(f.db, f.controller.session!.id, [
            f.benchId,
            missing ? 'absent' : f.rowId,
          ]),
          throwsA(isA<RecordManagementException>()),
        );
        expect((await exportBackup(f.db, exportedAt: 0)).data, before);
      },
    );
  }
  test('partial preference failure rolls back original note, favorite and row order', () async {
    final f = await workoutFixture();
    var p = (await readExercisePreferences(f.db, [f.benchId]))[f.benchId]!;
    p = await saveExercisePreference(
      f.db,
      f.benchId,
      expectedToken: p.token,
      equipmentNote: '原文',
    );
    final before = (await exportBackup(f.db, exportedAt: 0)).data;
    await expectLater(
      saveExercisePreference(
        FailingExecutor(
          f.db,
          'INSERT INTO exercise_preference',
          StateError('injected'),
        ),
        f.benchId,
        expectedToken: p.token,
        isFavorite: true,
      ),
      throwsStateError,
    );
    expect((await exportBackup(f.db, exportedAt: 0)).data, before);
  });
  test('same-name IDs have independent preferences, archive keeps preferences and removes picker entry', () async {
    final f = await workoutFixture();
    final other = await createCustomExercise(f.db, name: '杠铃卧推');
    final p = (await readExercisePreferences(f.db, [f.benchId]))[f.benchId]!;
    await saveExercisePreference(
      f.db,
      f.benchId,
      expectedToken: p.token,
      weightStepMilli: 1250,
      isFavorite: true,
      equipmentNote: '座椅4',
    );
    final values = await readExercisePreferences(f.db, [f.benchId, other.id]);
    expect(values[other.id]!.weightStepMilli, 2500);
    expect(values[other.id]!.equipmentNote, '');
    await f.db.run('UPDATE exercise SET is_archived=1 WHERE id=?', [f.benchId]);
    expect(
      (await loadExercisePickerData(f.db)).all.any((e) => e.id == f.benchId),
      false,
    );
    expect(
      (await readExercisePreferences(f.db, [
        f.benchId,
      ]))[f.benchId]!.equipmentNote,
      '座椅4',
    );
  });
  test('historical fallback times participate in recents and deleting scores removes recency', () async {
    final f = await workoutFixture();
    await f.controller.completeCurrentSet(40, 8);
    final history = await createSession(f.db);
    await finishSession(f.db, history.id, f.clock.value);
    await f.db.run('UPDATE session SET started_at=? WHERE id=?', [
      f.clock.value - 86400000,
      history.id,
    ]);
    final se = await addExerciseToSession(f.db, history.id, f.rowId);
    final set = await addSet(f.db, se.id, 25, 8);
    await f.db.run('UPDATE set_entry SET is_completed=1 WHERE id=?', [set.id]);
    expect((await loadExercisePickerData(f.db)).recentIds, [
      f.benchId,
      f.rowId,
    ]);
    await f.db.run('DELETE FROM set_entry WHERE is_completed=1');
    expect((await loadExercisePickerData(f.db)).recentIds, isEmpty);
  });
  test(
    '500 Unicode codepoints save and 501 reject without overwriting',
    () async {
      final f = await workoutFixture();
      var p = (await readExercisePreferences(f.db, [f.rowId]))[f.rowId]!;
      p = await saveExercisePreference(
        f.db,
        f.rowId,
        expectedToken: p.token,
        equipmentNote: '😀' * 500,
      );
      await expectLater(
        saveExercisePreference(
          f.db,
          f.rowId,
          expectedToken: p.token,
          equipmentNote: '😀' * 501,
        ),
        throwsFormatException,
      );
      expect(
        (await readExercisePreferences(f.db, [
          f.rowId,
        ]))[f.rowId]!.equipmentNote,
        '😀' * 500,
      );
      await f.db.run('DELETE FROM exercise WHERE id=?', [f.rowId]);
      expect(await f.db.all('SELECT * FROM exercise_preference'), isEmpty);
    },
  );
  test('v3 preference rows count toward the total record limit before row validation', () async {
    final f = await workoutFixture();
    final raw = (await exportBackup(f.db, exportedAt: 0)).toJson();
    final data = Map<String, Object?>.from(raw['data'] as Map);
    data['exercisePreferences'] = List.filled(maxBackupRecords, {
      'exerciseId': f.benchId,
      'weightStepMilli': 2500,
      'isFavorite': false,
      'equipmentNote': '',
    });
    expect(
      () => validateBackup({...raw, 'data': data}),
      throwsA(
        isA<BackupValidationException>().having(
          (e) => e.message,
          'limit',
          contains('记录总数'),
        ),
      ),
    );
  });
}
