import 'package:flutter_test/flutter_test.dart';

import '../support/workout_fixture.dart';
import '../support/workout_faults.dart';

import 'package:gym_tracker/data/repositories/workout_write_repo.dart';
import 'package:gym_tracker/data/repositories/backup_repo.dart';

void main() {
  test(
    'failure creating next placeholder rolls back completion, values and rest',
    () async {
      final f = await workoutFixture();
      final before = (await exportBackup(f.db, exportedAt: 0)).data;
      final faults = WorkoutFaults()..runPrefix = 'INSERT INTO set_entry';
      await expectLater(
        completeWorkoutSet(
          WorkoutFaultExecutor(f.db, faults),
          sessionId: f.controller.session!.id,
          pendingSetId: f.controller.currentExercise!.sets.single.id,
          weight: 40,
          reps: 8,
          now: f.clock.value,
        ),
        throwsStateError,
      );
      expect((await exportBackup(f.db, exportedAt: 0)).data, before);
    },
  );
  test('failure in second batch item rolls back every new occurrence and first set', () async {
    final f = await workoutFixture();
    final before = (await exportBackup(f.db, exportedAt: 0)).data;
    final faults = WorkoutFaults()
      ..runPrefix = 'INSERT INTO set_entry'
      ..occurrence = 2;
    await expectLater(
      addWorkoutExercises(
        WorkoutFaultExecutor(f.db, faults),
        f.controller.session!.id,
        [f.rowId, f.benchId],
      ),
      throwsStateError,
    );
    expect((await exportBackup(f.db, exportedAt: 0)).data, before);
  });
  test('并发完成只记一组', () async {
    final f = await workoutFixture();
    await Future.wait([
      f.controller.completeCurrentSet(40, 8),
      f.controller.completeCurrentSet(40, 8),
    ]);
    final rows = await f.db.all<Map<String, Object?>>(
      'SELECT * FROM set_entry ORDER BY position,rowid',
    );
    expect(rows.where((r) => r['is_completed'] == 1), hasLength(1));
    expect(rows.where((r) => r['is_completed'] == 0), hasLength(1));
  });
}
