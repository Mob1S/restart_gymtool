import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/sql_executor.dart';
import 'package:gym_tracker/state/active_session_controller.dart';
import 'package:gym_tracker/domain/workout_edit.dart';

import '../support/workout_fixture.dart';

class _Gate {
  bool enabled = false;
  final entered = Completer<void>();
  final release = Completer<void>();
}

class _WeightGate implements SqlExecutor {
  final SqlExecutor inner;
  final _Gate gate;
  _WeightGate(this.inner, this.gate);
  @override
  Future<T> transaction<T>(Future<T> Function(SqlExecutor) action) =>
      inner.transaction((tx) => action(_WeightGate(tx, gate)));
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
    'in-flight weight coalesces latest target and begin waits for commit',
    () async {
      final f = await workoutFixture();
      await f.controller.completeCurrentSet(40, 8);
      final gate = _Gate();
      final c = ActiveSessionController(
        _WeightGate(f.db, gate),
        now: f.clock.call,
      );
      addTearDown(c.dispose);
      await c.resume();
      gate.enabled = true;
      final pending = c.currentExercise!.sets.last;
      c.stagePendingWeight(pending.id, 42.5);
      final saving = c.flushPendingWeight();
      await gate.entered.future;
      c.stagePendingWeight(pending.id, 43.75);
      final begin = c.beginNextSet();
      gate.release.complete();
      expect(await saving, WorkoutWriteResult.saved);
      await begin;
      expect(c.currentExercise!.sets.last.weight, 43.75);
      expect(c.currentExercise!.sets.last.reps, 8);
      expect(c.currentExercise!.sets.first.restStartedAt, isNull);
      expect(c.currentExercise!.sets.first.weight, 40);
    },
  );
  test('reset during old save prevents its completion from repopulating new memory', () async {
    final f = await workoutFixture();
    await f.controller.completeCurrentSet(40, 8);
    final gate = _Gate();
    final c = ActiveSessionController(
      _WeightGate(f.db, gate),
      now: f.clock.call,
    );
    addTearDown(c.dispose);
    await c.resume();
    gate.enabled = true;
    c.stagePendingWeight(c.currentExercise!.sets.last.id, 42.5);
    final saving = c.flushPendingWeight();
    await gate.entered.future;
    c.reset();
    gate.release.complete();
    await saving;
    expect(c.session, isNull);
    expect(c.exercises, isEmpty);
    expect(c.hasPendingWeight, false);
  });
}
