import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/sql_executor.dart';
import 'package:gym_tracker/data/repositories/exercise_repo.dart';
import 'package:gym_tracker/data/repositories/session_repo.dart';
import 'package:gym_tracker/data/repositories/set_repo.dart';
import 'package:gym_tracker/state/active_session_controller.dart';

class _ResumeExecutor implements SqlExecutor {
  final SqlExecutor inner;
  int activeReads = 0;
  bool failActiveRead = false;
  bool failExerciseRead = false;
  Completer<void>? gate;
  final entered = Completer<void>();
  _ResumeExecutor(this.inner);

  @override
  Future<T?> first<T>(String sql, [List<Object?>? params]) async {
    final active = sql.contains('WHERE finished_at IS NULL');
    if (active) {
      activeReads++;
      if (failActiveRead) {
        failActiveRead = false;
        throw StateError('injected active-session read failure');
      }
    }
    final value = await inner.first<T>(sql, params);
    if (active && gate != null) {
      if (!entered.isCompleted) entered.complete();
      final pending = gate!;
      gate = null;
      await pending.future;
    }
    return value;
  }

  @override
  Future<List<T>> all<T>(String sql, [List<Object?>? params]) {
    if (failExerciseRead && sql.contains('FROM session_exercise')) {
      failExerciseRead = false;
      throw StateError('injected exercise read failure');
    }
    return inner.all<T>(sql, params);
  }

  @override
  Future<void> run(String sql, [List<Object?>? params]) =>
      inner.run(sql, params);
  @override
  Future<T> transaction<T>(Future<T> Function(SqlExecutor tx) action) =>
      inner.transaction(action);
}

void main() {
  late FfiExecutor db;
  late _ResumeExecutor exec;
  late ActiveSessionController active;
  late String sessionId;

  setUp(() async {
    db = await FfiExecutor.openMigrated();
    exec = _ResumeExecutor(db);
    active = ActiveSessionController(exec, now: () => 100000);
    final bench = await createCustomExercise(db, name: '卧推');
    final row = await createCustomExercise(db, name: '划船');
    final session = await createSession(db, name: '推拉训练');
    sessionId = session.id;
    final first = await addExerciseToSession(db, sessionId, bench.id);
    final second = await addExerciseToSession(db, sessionId, row.id);
    final done = await addSet(db, first.id, 60, 8);
    await completeSet(db, done.id, 1000);
    await addSet(db, first.id, 60, 8);
    await addSet(db, second.id, 40, 10);
  });

  tearDown(() async {
    active.dispose();
    await db.close();
  });

  test(
    'concurrent first restores share one read and writes wait for it',
    () async {
      final gate = Completer<void>();
      exec.gate = gate;
      final first = active.ensureResumed();
      final second = active.ensureResumed();
      await exec.entered.future;
      expect(active.loading, isTrue);
      expect(active.writing, isTrue);
      var startResolved = false;
      final starting = active.startNew().then((result) {
        startResolved = true;
        return result;
      });
      await Future<void>.delayed(Duration.zero);
      expect(startResolved, isFalse);
      expect(await active.endWorkout(), isNull);
      gate.complete();
      expect(await first, isTrue);
      expect(await second, isTrue);
      expect(await starting, StartResult.conflict);
      expect(exec.activeReads, 1);
      expect(active.session!.id, sessionId);
      expect(active.loading, isFalse);
      expect(active.writing, isFalse);
      expect((await db.all('SELECT id FROM session')).length, 1);
    },
  );

  test(
    'starting during an empty bootstrap read queues one new workout',
    () async {
      await db.run('DELETE FROM session WHERE id = ?', [sessionId]);
      final gate = Completer<void>();
      exec.gate = gate;
      final restoring = active.ensureResumed();
      await exec.entered.future;
      final firstStart = active.startNew(freeTraining: true);
      final secondStart = active.startNew(freeTraining: true);
      expect(active.session, isNull);
      gate.complete();
      expect(await restoring, isFalse);
      final results = await Future.wait([firstStart, secondStart]);
      expect(results, contains(StartResult.started));
      expect(results, contains(StartResult.busy));
      expect(active.session, isNotNull);
      expect(
        await db.all('SELECT id FROM session WHERE finished_at IS NULL'),
        hasLength(1),
      );
    },
  );

  test(
    'navigation restore keeps selected action; explicit refresh still reads',
    () async {
      await active.ensureResumed();
      await active.setCurrentIndex(1);
      final chosen = active.currentSessionExerciseId;
      final reads = exec.activeReads;
      expect(await active.ensureResumed(), isTrue);
      expect(active.currentSessionExerciseId, chosen);
      expect(exec.activeReads, reads);
      await active.resume();
      expect(exec.activeReads, reads + 1);
      expect(
        active.currentIndex,
        0,
        reason: 'cold-style refresh follows persisted work',
      );
    },
  );

  test(
    'a first read failure is recoverable without creating a session',
    () async {
      exec.failActiveRead = true;
      expect(await active.ensureResumed(), isFalse);
      expect(active.resumeError, contains('训练读取失败'));
      expect(active.loading, isFalse);
      expect(await active.ensureResumed(), isTrue);
      expect(active.resumeError, isNull);
      expect(active.session!.id, sessionId);
      expect(exec.activeReads, 2);
      expect((await db.all('SELECT id FROM session')).length, 1);
    },
  );

  test('failed explicit read preserves the loaded workout and focus', () async {
    await active.ensureResumed();
    await active.setCurrentIndex(1);
    final selected = active.currentSessionExerciseId;
    final original = active.session;
    exec.failActiveRead = true;
    await expectLater(active.resume(), throwsStateError);
    expect(active.session, same(original));
    expect(active.currentSessionExerciseId, selected);
    expect(active.exercises, hasLength(2));
    expect(await active.ensureResumed(), isTrue);
    expect(active.resumeError, isNull);
  });

  test(
    'reset invalidates an old read so deleted training cannot reappear',
    () async {
      final gate = Completer<void>();
      exec.gate = gate;
      final restoring = active.ensureResumed();
      await exec.entered.future;
      await db.run('DELETE FROM session WHERE id = ?', [sessionId]);
      active.reset();
      gate.complete();
      expect(await restoring, isFalse);
      expect(active.session, isNull);
      expect(active.exercises, isEmpty);
      expect(active.loading, isFalse);
      expect(await active.ensureResumed(), isFalse);
      expect(exec.activeReads, 2);
    },
  );

  test(
    'an older completion cannot clear the loading state of a new restore',
    () async {
      final oldGate = Completer<void>();
      exec.gate = oldGate;
      final old = active.ensureResumed();
      await exec.entered.future;
      active.reset();
      final newGate = Completer<void>();
      exec.gate = newGate;
      final newer = active.ensureResumed();
      // Wait until the second query has taken its own snapshot.
      while (exec.activeReads < 2 || exec.gate != null) {
        await Future<void>.delayed(Duration.zero);
      }
      oldGate.complete();
      await old;
      expect(active.loading, isTrue);
      newGate.complete();
      await newer;
      expect(active.loading, isFalse);
      expect(active.session!.id, sessionId);
    },
  );

  test('ending a loaded workout clears the cached navigation result', () async {
    await active.ensureResumed();
    final id = await active.endWorkout();
    expect(id, sessionId);
    expect(await active.ensureResumed(), isFalse);
    expect(active.session, isNull);
    expect(active.exercises, isEmpty);
    expect((await getSession(db, sessionId))!.finishedAt, isNotNull);
  });

  test(
    'new workout with a failed reload can be recovered through navigation',
    () async {
      final original = (await getSession(db, sessionId))!;
      await finishSession(db, sessionId, original.startedAt + 1000);
      exec.failExerciseRead = true;
      expect(
        await active.startNew(freeTraining: true),
        StartResult.refreshFailed,
      );
      final created = active.session!.id;
      expect(active.resumeError, isNotNull);
      expect(await active.ensureResumed(), isTrue);
      expect(active.resumeError, isNull);
      expect(active.session!.id, created);
      expect(
        (await db.all('SELECT id FROM session WHERE finished_at IS NULL')),
        hasLength(1),
      );
    },
  );
}
