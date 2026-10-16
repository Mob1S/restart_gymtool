import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/repositories/backup_repo.dart';
import 'package:gym_tracker/data/repositories/session_repo.dart';
import 'package:gym_tracker/data/repositories/set_repo.dart';
import 'package:gym_tracker/domain/record_management.dart';
import 'package:gym_tracker/state/active_session_controller.dart';

void main() {
  late FfiExecutor db;
  late ActiveSessionController c;
  setUp(() async {
    db = await FfiExecutor.openMigrated();
    c = ActiveSessionController(db);
    for (final id in ['a', 'b', 'c']) {
      await db.run(
        'INSERT INTO exercise(id,name,is_custom,is_archived,created_at) VALUES(?,?,1,0,0)',
        [id, id],
      );
    }
    await c.startNew();
    for (final id in ['a', 'b', 'c']) {
      await c.addExercise(id);
    }
    c.setCurrentIndex(0);
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });
  test(
    'keep recorded sets survives resume, excludes focus, cancels rest',
    () async {
      await c.completeCurrentSet(50, 8);
      final id = c.currentSessionExerciseId!;
      final p = (await c.previewExerciseRemoval(id))!;
      expect(p.completedSets, 1);
      expect(
        await c.removeExercise(p, RemoveExerciseChoice.keepRecorded),
        true,
      );
      expect(c.exercises, hasLength(3));
      expect(c.recordingExercises, hasLength(2));
      expect(c.currentExercise!.exerciseName, 'b');
      final groups = await listSets(db, id);
      expect(groups, hasLength(1));
      expect(groups.single.weight, 50);
      expect(groups.single.restStartedAt, isNull);
      c.reset();
      await c.resume();
      expect(c.currentExercise!.exerciseName, 'b');
      expect(c.recordingExercises, hasLength(2));
      await c.completeCurrentSet(20, 8);
      expect(c.currentExercise!.sets.first.weight, 20);
      expect((await listSets(db, id)).single.weight, 50);
      await exportBackup(db, exportedAt: 0);
    },
  );
  test('hard deletion reindexes and protects last visible action', () async {
    c.setCurrentIndex(2);
    final last = (await c.previewExerciseRemoval(c.currentSessionExerciseId!))!;
    await c.removeExercise(last, RemoveExerciseChoice.deleteRecorded);
    expect(c.currentIndex, 1);
    expect(c.currentExercise!.exerciseName, 'b');
    final middle = (await c.previewExerciseRemoval(
      c.currentSessionExerciseId!,
    ))!;
    await c.removeExercise(middle, RemoveExerciseChoice.deleteRecorded);
    final only = (await c.previewExerciseRemoval(c.currentSessionExerciseId!))!;
    await expectLater(
      c.removeExercise(only, RemoveExerciseChoice.deleteRecorded),
      throwsA(isA<RecordManagementException>()),
    );
    expect(
      (await listSessionExercises(db, c.session!.id)).map((e) => e.position),
      [0],
    );
  });
  test(
    'cancel writes nothing and changed group count invalidates confirmation',
    () async {
      final id = c.currentSessionExerciseId!;
      final p = (await c.previewExerciseRemoval(id))!;
      final before = (await exportBackup(db, exportedAt: 0)).data;
      expect(await c.removeExercise(p, RemoveExerciseChoice.cancel), false);
      expect((await exportBackup(db, exportedAt: 0)).data, before);
      await c.completeCurrentSet(50, 8);
      await expectLater(
        c.removeExercise(p, RemoveExerciseChoice.deleteRecorded),
        throwsA(isA<RecordManagementException>()),
      );
      expect(c.recordingExercises, hasLength(3));
    },
  );
}
