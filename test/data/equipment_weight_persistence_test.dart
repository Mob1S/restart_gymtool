import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/sql_executor.dart';
import 'package:gym_tracker/data/repositories/backup_repo.dart';
import 'package:gym_tracker/data/repositories/exercise_preferences_repo.dart';
import 'package:gym_tracker/data/repositories/set_repo.dart';
import 'package:gym_tracker/data/repositories/workout_edit_repo.dart';
import 'package:gym_tracker/data/repositories/workout_write_repo.dart';
import 'package:gym_tracker/data/repositories/training_plan_repo.dart';
import 'package:gym_tracker/domain/training_plans.dart';
import 'package:gym_tracker/domain/weight_value.dart';
import 'package:gym_tracker/domain/workout_edit.dart';
import 'package:gym_tracker/state/active_session_controller.dart';

import '../support/workout_fixture.dart';

EquipmentWeight lb(String value) =>
    EquipmentWeight(DecimalReading.parse(value), WeightUnit.lb);

Future<void> preferUnit(WorkoutFixture f, String id, WeightUnit unit) async {
  final preference = (await readExercisePreferences(f.db, [id]))[id]!;
  await saveExercisePreference(
    f.db,
    id,
    expectedToken: preference.token,
    weightUnit: unit,
  );
}

class _Gate {
  bool enabled = false;
  final entered = Completer<void>();
  final release = Completer<void>();
}

class _GatedWeight implements SqlExecutor {
  final SqlExecutor inner;
  final _Gate gate;
  _GatedWeight(this.inner, this.gate);
  @override
  Future<T> transaction<T>(Future<T> Function(SqlExecutor) action) =>
      inner.transaction((tx) => action(_GatedWeight(tx, gate)));
  @override
  Future<void> run(String sql, [List<Object?>? params]) async {
    if (gate.enabled && sql.startsWith('UPDATE set_entry SET weight=')) {
      gate.enabled = false;
      gate.entered.complete();
      await gate.release.future;
    }
    await inner.run(sql, params);
  }

  @override
  Future<T?> first<T>(String sql, [List<Object?>? params]) =>
      inner.first<T>(sql, params);
  @override
  Future<List<T>> all<T>(String sql, [List<Object?>? params]) =>
      inner.all<T>(sql, params);
}

void main() {
  test(
    'start stores parent/day snapshots and detach preserves historical names',
    () async {
      final f = await workoutFixture();
      await f.controller.endWorkout();
      final plan = await saveTrainingPlan(
        f.db,
        TrainingPlanDraft(
          name: '力量循环',
          days: [
            TrainingDayDraft(name: '下肢 B', exerciseIds: [f.benchId]),
          ],
        ),
      );
      expect(
        await f.controller.startNew(
          planId: plan.id,
          preferredDayId: plan.days.single.id,
        ),
        StartResult.started,
      );
      final session = f.controller.session!;
      expect(session.planId, plan.id);
      expect(session.templateId, plan.days.single.id);
      expect(session.planNameSnapshot, '力量循环');
      expect(session.dayNameSnapshot, '下肢 B');
      expect(session.origin, 'live');
      f.controller.detachTemplate(plan.days.single.id);
      expect(f.controller.session!.templateId, isNull);
      expect(f.controller.session!.planId, plan.id);
      expect(f.controller.session!.dayNameSnapshot, '下肢 B');
      f.controller.detachPlan(plan.id);
      expect(f.controller.session!.planId, isNull);
      expect(f.controller.session!.planNameSnapshot, '力量循环');
      expect(f.controller.session!.dayNameSnapshot, '下肢 B');
      expect(f.controller.session!.origin, 'live');
    },
  );

  test('zero-day plan rejects start without creating a session', () async {
    final f = await workoutFixture();
    await f.controller.endWorkout();
    final plan = await saveTrainingPlan(
      f.db,
      TrainingPlanDraft(name: '待编排', days: []),
    );
    expect(
      await f.controller.startNew(planId: plan.id),
      StartResult.planChanged,
    );
    expect(
      await f.db.first("SELECT id FROM session WHERE finished_at IS NULL"),
      isNull,
    );
  });

  test(
    'native lb survives pending, complete, reload, edit, undo and rest',
    () async {
      final f = await workoutFixture();
      final c = f.controller;
      final pendingId = c.currentExercise!.sets.single.id;
      c.stagePendingReading(pendingId, lb('50'));
      expect(c.stagedReading(pendingId)!.label, '50 lb');
      expect(await c.flushPendingWeight(), WorkoutWriteResult.saved);
      final stored = await f.db.first<Map<String, Object?>>(
        'SELECT * FROM set_entry WHERE id=?',
        [pendingId],
      );
      expect(stored!['source_weight'], '50');
      expect(stored['source_unit'], 'lb');
      expect(stored['weight'], closeTo(22.6796185, 1e-10));
      await c.completeCurrentReading(lb('50'), 8);
      await c.resume();
      expect(c.currentExercise!.sets.map((s) => s.equipmentWeight.label), [
        '50 lb',
        '50 lb',
      ]);
      await preferUnit(f, f.benchId, WeightUnit.kg);
      final edit = (await c.previewCompletedSet(pendingId))!;
      expect(
        await c.editCompletedSet(
          edit,
          lb('52.5').kilograms,
          7,
          reading: lb('52.5'),
        ),
        WorkoutWriteResult.saved,
      );
      expect(c.currentExercise!.sets.first.equipmentWeight.label, '52.5 lb');
      expect(c.currentExercise!.sets.last.equipmentWeight.label, '50 lb');
      final undo = (await c.previewUndo())!;
      expect(await c.undoLastCompletion(undo), WorkoutWriteResult.saved);
      expect(c.currentExercise!.sets.single.equipmentWeight.label, '52.5 lb');
      expect(c.currentExercise!.sets.single.isCompleted, false);
      await c.completeCurrentReading(lb('52.5'), 7);
      f.clock.value += 30000;
      await c.beginNextSet();
      expect(c.currentExercise!.sets.first.restSeconds, 30);
      expect(c.currentExercise!.sets.last.equipmentWeight.label, '52.5 lb');
      expect(await exportBackup(f.db, exportedAt: 0), isNotNull);
    },
  );

  test('mismatched canonical/source values reject every entry point', () async {
    final f = await workoutFixture();
    final c = f.controller;
    final id = c.currentExercise!.sets.single.id;
    final before = (await exportBackup(f.db, exportedAt: 0)).data;
    await expectLater(
      savePendingWeight(
        f.db,
        sessionId: c.session!.id,
        pendingSetId: id,
        weight: 50,
        reading: lb('50'),
      ),
      throwsA(anything),
    );
    await expectLater(
      completeWorkoutSet(
        f.db,
        sessionId: c.session!.id,
        pendingSetId: id,
        weight: 50,
        reading: lb('50'),
        reps: 8,
        now: f.clock.value,
      ),
      throwsA(anything),
    );
    expect((await exportBackup(f.db, exportedAt: 0)).data, before);
    await c.completeCurrentReading(lb('50'), 8);
    final edit = (await c.previewCompletedSet(id))!;
    await expectLater(
      updateCompletedSet(f.db, edit, weight: 50, reading: lb('50'), reps: 9),
      throwsA(anything),
    );
    expect(
      (await listSets(
        f.db,
        c.currentSessionExerciseId!,
      )).first.equipmentWeight.label,
      '50 lb',
    );
  });

  test(
    'replacement uses target preferred native unit and retains source lb',
    () async {
      final f = await workoutFixture();
      await f.controller.completeCurrentReading(lb('50'), 8);
      await preferUnit(f, f.rowId, WeightUnit.lb);
      final sourceId = f.controller.currentSessionExerciseId!;
      expect(
        await f.controller.replaceExercise(
          (await f.controller.previewReplacement(f.rowId))!,
        ),
        WorkoutWriteResult.saved,
      );
      expect(
        (await listSets(f.db, sourceId)).single.equipmentWeight.label,
        '50 lb',
      );
      expect(
        f.controller.currentExercise!.sets.single.equipmentWeight.label,
        '45 lb',
      );
    },
  );

  test(
    'first set finds older matching unit instead of converting recent kg',
    () async {
      final f = await workoutFixture();
      await f.controller.completeCurrentReading(lb('50'), 6);
      await f.controller.endWorkout();
      await f.controller.startNew(freeTraining: true);
      await f.db.run('UPDATE session SET started_at=? WHERE id=?', [
        f.clock.value + 1000,
        f.controller.session!.id,
      ]);
      await f.controller.completeCurrentSet(80, 8);
      await f.controller.endWorkout();
      await preferUnit(f, f.benchId, WeightUnit.lb);
      await f.controller.startNew(freeTraining: true);
      expect(
        f.controller.currentExercise!.sets.single.equipmentWeight.label,
        '50 lb',
      );
      expect(f.controller.currentExercise!.sets.single.reps, 6);
    },
  );

  test(
    'no matching native history uses 45 lb rather than converted kg',
    () async {
      final f = await workoutFixture();
      await f.controller.completeCurrentSet(80, 8);
      await f.controller.endWorkout();
      await preferUnit(f, f.benchId, WeightUnit.lb);
      await f.controller.startNew(freeTraining: true);
      expect(
        f.controller.currentExercise!.sets.single.equipmentWeight.label,
        '45 lb',
      );
    },
  );

  test('typed queue coalesces delayed lb edits before completion; old ID cannot overwrite next set', () async {
    final f = await workoutFixture();
    final gate = _Gate();
    final c = ActiveSessionController(
      _GatedWeight(f.db, gate),
      now: f.clock.call,
    );
    addTearDown(c.dispose);
    await c.resume();
    final id = c.currentExercise!.sets.single.id;
    gate.enabled = true;
    c.stagePendingReading(id, lb('50'));
    final saving = c.flushPendingWeight();
    await gate.entered.future;
    c.stagePendingReading(id, lb('52.5'));
    final completing = c.completeCurrentReading(lb('55'), 8);
    gate.release.complete();
    expect(await saving, WorkoutWriteResult.saved);
    await completing;
    expect(c.currentExercise!.sets.map((s) => s.equipmentWeight.label), [
      '55 lb',
      '55 lb',
    ]);
    c.stagePendingReading(id, lb('50'));
    expect(c.hasPendingWeight, false);
    await c.flushPendingWeight();
    expect(c.currentExercise!.sets.last.equipmentWeight.label, '55 lb');
  });
}
