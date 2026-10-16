import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/migrations.dart';
import 'package:gym_tracker/data/repositories/backup_repo.dart';
import 'package:gym_tracker/data/repositories/import_repo.dart';
import 'package:gym_tracker/data/repositories/session_repo.dart';
import 'package:gym_tracker/data/repositories/set_repo.dart';
import 'package:gym_tracker/domain/import_records.dart';
import 'package:gym_tracker/domain/import_preview.dart';
import 'package:gym_tracker/domain/workout_csv.dart';

import 'backup_repo_test.dart' show FailingExecutor;

const csv =
    'Date,Workout Name,Exercise Name,Weight,Reps\n2024-01-01 10:00,Push,Bench,20,8\n2024-01-02 10:00,Push,Bench,30,10';
void main() {
  late FfiExecutor db;
  setUp(() async {
    db = await FfiExecutor.openInMemory();
    await migrate(db);
  });
  tearDown(() async => db.close());
  Future<ImportDraft> draft() async =>
      buildImportDraft(parseWorkoutCsv(csv), await loadImportCatalog(db));
  Future<String> snapshot() async =>
      jsonEncode((await exportBackup(db, exportedAt: 0)).data);
  test('post-import backup byte limit rolls the entire append back', () async {
    final huge = 'x' * (20 * 1024 * 1024);
    final w = ImportedWorkout(
      sourceRow: 1,
      startedAt: 1,
      finishedAt: 2,
      name: huge,
      exercises: [
        ImportedExercise(
          name: 'new',
          sets: [const ImportedSet(weight: 20, reps: 8)],
        ),
      ],
    );
    final parsed = CsvParseResult(
      source: CsvSource.unknown,
      workouts: [w],
      statsByWorkout: [WorkoutImportStats([], 0, false)],
    );
    final d = buildImportDraft(parsed, await loadImportCatalog(db));
    final before = await snapshot();
    await expectLater(
      importWorkouts(db, confirmImportDraft(d, ImportSelection.defaults(d))),
      throwsA(anything),
    );
    expect(await snapshot(), before);
  });
  test(
    'append preserves active/settings; reuses one new exercise; round trips',
    () async {
      final active = await createSession(db);
      final before = await getSession(db, active.id);
      final d = await draft();
      final result = await importWorkouts(
        db,
        confirmImportDraft(d, ImportSelection.defaults(d)),
      );
      expect(result.sessions, 2);
      expect(result.sets, 2);
      expect(result.createdExercises, 1);
      expect((await getActiveSession(db))?.id, active.id);
      expect((await getSession(db, active.id))?.startedAt, before!.startedAt);
      final rows = await db.all('SELECT * FROM set_entry');
      expect(
        rows.every(
          (r) =>
              r['is_completed'] == 1 &&
              r['rest_seconds'] == null &&
              r['rest_started_at'] == null &&
              r['completed_at'] != null,
        ),
        true,
      );
      final se = await listSessionExercises(db, result.sessionIds.first);
      final history = await getLastPerformance(
        db,
        se.single.exerciseId,
        active.id,
      );
      expect(history.first.weight, 30);
      final backup = await exportBackup(db, exportedAt: 0);
      final preview = await inspectBackup(db, backup);
      await restoreBackup(db, preview);
      expect(await snapshot(), jsonEncode(backup.data));
      final repeated = await draft();
      expect(repeated.duplicates, {0, 1});
      expect(ImportSelection.defaults(repeated).selected, isEmpty);
    },
  );
  test(
    'stale preview and partial insert fail without changing database',
    () async {
      final d = await draft();
      await createSession(db);
      final before = await snapshot();
      await expectLater(
        importWorkouts(db, confirmImportDraft(d, ImportSelection.defaults(d))),
        throwsA(isA<ImportValidationException>()),
      );
      expect(await snapshot(), before);
      final fresh = await draft();
      await expectLater(
        importWorkouts(
          FailingExecutor(db, 'INSERT INTO set_entry', StateError('injected')),
          confirmImportDraft(fresh, ImportSelection.defaults(fresh)),
        ),
        throwsA(anything),
      );
      expect(await snapshot(), before);
    },
  );
  test('ambiguous archived names need explicit choice; bad rows need acknowledgment', () async {
    for (final id in ['one', 'two']) {
      await db.run(
        'INSERT INTO exercise(id,name,is_custom,is_archived,created_at) VALUES(?,?,1,1,0)',
        [id, 'Bench'],
      );
    }
    final parsed = parseWorkoutCsv('$csv\ninvalid,Push,Bench,2,3');
    final d = buildImportDraft(parsed, await loadImportCatalog(db));
    expect(
      () => confirmImportDraft(d, ImportSelection.defaults(d)),
      throwsA(isA<ImportValidationException>()),
    );
    final selection = ImportSelection(
      selected: {0},
      matches: {'bench': 'two'},
      acknowledgeSkipped: true,
    );
    final result = await importWorkouts(db, confirmImportDraft(d, selection));
    expect(result.createdExercises, 0);
    expect(
      (await listSessionExercises(
        db,
        result.sessionIds.single,
      )).single.exerciseId,
      'two',
    );
    expect(
      (await db.all('SELECT is_archived FROM exercise'))
          .every((e) => e['is_archived'] == 1),
      true,
    );
  });
}
