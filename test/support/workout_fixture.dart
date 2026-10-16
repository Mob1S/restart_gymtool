import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/repositories/exercise_repo.dart';
import 'package:gym_tracker/state/active_session_controller.dart';

class WorkoutClock {
  int value = DateTime.utc(2026, 10, 16, 2).millisecondsSinceEpoch;
  int call() => value;
}

class WorkoutFixture {
  final FfiExecutor db;
  final ActiveSessionController controller;
  final WorkoutClock clock;
  final String benchId, rowId;
  const WorkoutFixture(
    this.db,
    this.controller,
    this.clock,
    this.benchId,
    this.rowId,
  );
}

Future<WorkoutFixture> workoutFixture() async {
  final db = await FfiExecutor.openMigrated();
  addTearDown(db.close);
  final bench = await createCustomExercise(db, name: '杠铃卧推');
  final row = await createCustomExercise(db, name: '坐姿划船');
  final clock = WorkoutClock();
  final controller = ActiveSessionController(db, now: clock.call);
  addTearDown(controller.dispose);
  await controller.startNew();
  await db.run('UPDATE session SET started_at=? WHERE id=?', [
    clock.value,
    controller.session!.id,
  ]);
  await controller.resume();
  await controller.addExercise(bench.id);
  return WorkoutFixture(db, controller, clock, bench.id, row.id);
}
