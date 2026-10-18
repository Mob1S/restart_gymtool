import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/migrations.dart';
import 'package:gym_tracker/data/builtin_programs.dart';
import 'package:gym_tracker/data/repositories/exercise_repo.dart';
import 'package:gym_tracker/data/repositories/builtin_program_repo.dart';
import 'package:gym_tracker/data/repositories/training_program_repo.dart';
import 'package:gym_tracker/data/repositories/training_plan_repo.dart';
import 'package:gym_tracker/data/repositories/set_repo.dart';
import 'package:gym_tracker/state/active_session_controller.dart';

void main() {
  late FfiExecutor db;
  setUp(() async {
    db = await FfiExecutor.openInMemory();
    await migrate(db);
    await seedExercisesIfEmpty(db);
  });
  tearDown(() async => db.close());
  test(
    'three independent source-attributed programs import arbitrary day cycles',
    () async {
      for (final preset in builtinPrograms) {
        final plan = await importBuiltinProgram(db, preset);
        expect(plan.days.length, preset.days.length);
        final p = (await readTrainingProgram(db, plan.id))!;
        expect(p.stages.length, preset.stages.length);
        expect(
          p.current.targets.length,
          plan.days.fold<int>(0, (n, d) => n + d.exerciseIds.length),
        );
      }
    },
  );
  test(
    'stage changes preserve active targets and rest-cycle activation',
    () async {
      final plan = await importBuiltinProgram(db, builtinPrograms.first);
      final c = ActiveSessionController(db);
      addTearDown(c.dispose);
      expect(await c.startNew(planId: plan.id), StartResult.started);
      final se = c.exercises.first.sessionExercise.id;
      final snapshot = (await readSessionPrescription(db, se))!.encode();
      final p = (await readTrainingProgram(db, plan.id))!;
      await selectProgramStage(
        db,
        plan.id,
        p.stages[5].id,
        expectedPayload: p.encode(),
      );
      expect((await readSessionPrescription(db, se))!.encode(), snapshot);
      expect(
        (await readTrainingProgram(db, plan.id))!
            .current
            .targets[plan.days.first.occurrenceIds.first]!
            .map((t) => t.repsMin),
        [15, 6, 6],
      );
      expect(
        (await getTrainingPlan(db, plan.id))!.activatedOn,
        plan.activatedOn,
      );
      final pending = (await listSets(db, se)).single;
      expect(pending.detail!.target!.role, 'warmup');
      expect(pending.detail!.effort, isNull);
    },
  );
}
