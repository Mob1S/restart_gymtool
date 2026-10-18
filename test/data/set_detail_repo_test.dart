import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/migrations.dart';
import 'package:gym_tracker/data/builtin_programs.dart';
import 'package:gym_tracker/data/repositories/builtin_program_repo.dart';
import 'package:gym_tracker/data/repositories/exercise_repo.dart';
import 'package:gym_tracker/data/repositories/set_repo.dart';
import 'package:gym_tracker/data/repositories/set_detail_repo.dart';
import 'package:gym_tracker/data/repositories/workout_write_repo.dart';
import 'package:gym_tracker/domain/training_prescription.dart';
import 'package:gym_tracker/domain/weight_value.dart';
import 'package:gym_tracker/state/active_session_controller.dart';

void main() {
  late FfiExecutor db;
  late ActiveSessionController c;
  late String seid, pid;
  setUp(() async {
    db = await FfiExecutor.openInMemory();
    await migrate(db);
    await seedExercisesIfEmpty(db);
    final plan = await importBuiltinProgram(db, builtinPrograms.first);
    c = ActiveSessionController(db);
    await c.startNew(planId: plan.id);
    seid = c.exercises.last.sessionExercise.id;
    pid = (await listSets(db, seid)).single.id;
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });
  test(
    'first segment is durable, changing next weight cannot overwrite it',
    () async {
      await completeWorkoutSet(
        db,
        sessionId: c.session!.id,
        pendingSetId: pid,
        weight: 30,
        reps: 10,
        now: 1000,
        effort: const Effort('rpe', 9),
      );
      expect((await listSets(db, seid)).single.isCompleted, isFalse);
      expect((await readSetDetail(db, pid)).firstCompletedAt, 1000);
      await savePendingWeight(
        db,
        sessionId: c.session!.id,
        pendingSetId: pid,
        weight: 35,
      );
      expect((await listSets(db, seid)).single.weight, 30);
      await completeWorkoutSet(
        db,
        sessionId: c.session!.id,
        pendingSetId: pid,
        weight: 35,
        reps: 10,
        now: 6000,
        reading: EquipmentWeight.kg(35),
      );
      final sets = await listSets(db, seid);
      expect(sets.length, 2);
      expect(sets.first.isCompleted, isTrue);
      expect(sets.first.reps, 10);
      expect(sets.first.detail!.continuations.single.reps, 10);
      expect(sets.first.detail!.extraVolume, 350);
      expect(sets.first.detail!.continuations.single.pauseSeconds, 5);
      expect(sets.last.detail!.targetIndex, 1);
    },
  );
  test('ending a workout retains already performed first segment', () async {
    await recordWorkoutSegment(
      db,
      sessionId: c.session!.id,
      setId: pid,
      reading: EquipmentWeight.kg(20),
      reps: 8,
      now: 1000,
    );
    await finishActiveWorkout(db, sessionId: c.session!.id, now: 3000);
    final done = (await listSets(db, seid)).single;
    expect(done.isCompleted, isTrue);
    expect(done.reps, 8);
    expect(done.detail!.endedEarly, isTrue);
    expect(done.detail!.continuations, isEmpty);
  });
}
