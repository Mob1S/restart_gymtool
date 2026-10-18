import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/builtin_programs.dart';
import 'package:gym_tracker/data/repositories/builtin_program_repo.dart';
import 'package:gym_tracker/data/repositories/exercise_repo.dart';
import 'package:gym_tracker/data/repositories/set_repo.dart';
import 'package:gym_tracker/data/repositories/set_detail_repo.dart';
import 'package:gym_tracker/data/repositories/workout_write_repo.dart';
import 'package:gym_tracker/data/repositories/workout_edit_repo.dart';
import 'package:gym_tracker/data/repositories/workout_settings_repo.dart';
import 'package:gym_tracker/data/repositories/exercise_preferences_repo.dart';
import 'package:gym_tracker/data/repositories/session_summary_loader.dart';
import 'package:gym_tracker/data/repositories/session_repo.dart';
import 'package:gym_tracker/data/repositories/progress_repo.dart';
import 'package:gym_tracker/data/repositories/csv_export_repo.dart';
import 'package:gym_tracker/data/repositories/backup_repo.dart';
import 'package:gym_tracker/domain/backup_codec.dart';
import 'package:gym_tracker/domain/training_prescription.dart';
import 'package:gym_tracker/domain/weight_value.dart';
import 'package:gym_tracker/domain/workout_csv_export.dart';
import 'package:gym_tracker/domain/workout_csv.dart';
import 'package:gym_tracker/state/active_session_controller.dart';

import '../support/workout_faults.dart';

void main() {
  late FfiExecutor db;
  late ActiveSessionController c;
  late String sid, seid, pending;
  setUp(() async {
    db = await FfiExecutor.openMigrated();
    await seedExercisesIfEmpty(db);
    final plan = await importBuiltinProgram(db, builtinPrograms.first);
    c = ActiveSessionController(db);
    await c.startNew(planId: plan.id);
    sid = c.session!.id;
    await db.run('UPDATE session SET started_at=0 WHERE id=?', [sid]);
    seid = c.exercises.last.sessionExercise.id;
    pending = (await listSets(db, seid)).single.id;
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });
  Future<void> segment(int reps, int now, double kg) => recordWorkoutSegment(
    db,
    sessionId: sid,
    setId: pending,
    reading: EquipmentWeight.kg(kg),
    reps: reps,
    now: now,
    effort: const Effort('rpe', 9),
  );
  test('restart, undo continuation, finish and edit retain logical counts, source values and targets', () async {
    await segment(10, 1000, 30);
    await c.resume();
    expect(c.currentSessionExerciseId, seid);
    final partial = (await listSets(db, seid)).single;
    expect(partial.hasRecordedWork, isTrue);
    expect(partial.pendingReps, 10);
    await segment(10, 6000, 35);
    final undo = (await inspectUndoSet(db, sid, seid, now: 7000))!;
    await undoCompletedSet(db, undo, now: 7000);
    expect((await listSets(db, seid)).single.detail!.continuations, isEmpty);
    expect((await listSets(db, seid)).single.detail!.firstCompletedAt, 1000);
    await segment(10, 12000, 35);
    await finishActiveWorkout(db, sessionId: sid, now: 13000);
    final summary = (await loadSessionSummary(db, sid))!;
    expect(summary.totalSets, 1);
    expect(summary.volumeLoad, 650);
    expect((await listSessionSummaries(db)).single.volumeLoad, 650);
    final facts = await listAllCompletedSetFacts(db);
    expect(facts.length, 2);
    expect(facts.every((f) => !f.e1rmEligible), isTrue);
    final edit = await inspectHistoricalSet(db, sid, pending);
    final originalTarget = edit.original.detail!.target!.toJson();
    await updateHistoricalSet(
      db,
      edit,
      EquipmentWeight.kg(32.5),
      9,
      edit.original.detail!.copyWith(effort: const Effort('rir', 1)),
    );
    expect(
      (await listSets(db, seid)).first.detail!.target!.toJson(),
      originalTarget,
    );
    expect((await loadSessionSummary(db, sid))!.volumeLoad, 642.5);
    await expectLater(
      updateHistoricalSet(
        db,
        edit,
        EquipmentWeight.kg(40),
        9,
        edit.original.detail,
      ),
      throwsException,
    );
    final csv = encodeWorkoutCsv(await readWorkoutCsvRows(db));
    final parsed = parseWorkoutCsv(csv);
    expect(parsed.skipped, isEmpty);
    final set = parsed.workouts.single.exercises.single.sets.single;
    expect(set.reps, 9);
    expect(set.detail!.continuations.single.reps, 10);
    expect(set.detail!.continuations.single.reading.amount.text, '35');
    final clone = await FfiExecutor.openMigrated();
    try {
      final backup = await exportBackup(db, exportedAt: 0);
      await restoreBackup(
        clone,
        await inspectBackup(clone, decodeBackup(encodeBackup(backup))),
      );
      expect((await exportBackup(clone, exportedAt: 0)).data, backup.data);
    } finally {
      await clone.close();
    }
  });
  test(
    'intra-set rest stops at segment start rather than its completion',
    () async {
      await segment(10, 1000, 30);
      await beginWorkoutSegment(db, sessionId: sid, setId: pending, now: 6000);
      await c.resume();
      expect((await readSetDetail(db, pending)).segmentStartedAt, 6000);
      await segment(10, 26000, 30);
      expect(
        (await readSetDetail(db, pending)).continuations.single.pauseSeconds,
        5,
      );
    },
  );
  test(
    'changing native unit after first segment preserves first reading',
    () async {
      await segment(10, 1000, 30);
      final exercise = c.exercises.last.sessionExercise.exerciseId;
      final pref = (await readExercisePreferences(db, [exercise]))[exercise]!;
      await applyPendingWeightSettings(
        db,
        sessionId: sid,
        pendingSetId: pending,
        exerciseId: exercise,
        expectedPreferenceToken: pref.token,
        reading: EquipmentWeight(DecimalReading.parse('70'), WeightUnit.lb),
        kgStep: pref.kgStep,
        lbStep: pref.lbStep,
        showKgEquivalent: true,
      );
      final set = (await listSets(db, seid)).single;
      expect(set.weight, 30);
      expect(set.recordedWeight!.unit, WeightUnit.kg);
      expect(set.equipmentWeight.label, '70 lb');
    },
  );
  test(
    'failed continuation is atomic and can be retried without duplication',
    () async {
      await segment(10, 1000, 30);
      final before = (await exportBackup(db, exportedAt: 0)).data;
      final faulty = WorkoutFaultExecutor(
        db,
        WorkoutFaults()..runPrefix = 'INSERT INTO set_entry',
      );
      await expectLater(
        recordWorkoutSegment(
          faulty,
          sessionId: sid,
          setId: pending,
          reading: EquipmentWeight.kg(35),
          reps: 10,
          now: 6000,
        ),
        throwsStateError,
      );
      expect((await exportBackup(db, exportedAt: 0)).data, before);
      await segment(10, 6000, 35);
      expect((await listSets(db, seid)).first.detail!.continuations.length, 1);
    },
  );
  test('CSV cannot silently import a half missing continuation', () async {
    await segment(10, 1000, 30);
    await segment(10, 6000, 35);
    await finishActiveWorkout(db, sessionId: sid, now: 7000);
    final csv = encodeWorkoutCsv(await readWorkoutCsvRows(db));
    final missing = csv.split('\r\n').take(2).join('\r\n');
    final result = parseWorkoutCsv(missing);
    expect(result.workouts, isEmpty);
    expect(result.skipped.single.reason, contains('不完整'));
  });
}
