import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/migrations.dart';
import 'package:gym_tracker/data/repositories/exercise_repo.dart';
import 'package:gym_tracker/data/repositories/exercise_catalog_repo.dart';
import 'package:gym_tracker/domain/exercise_catalog.dart';

import '../support/workout_faults.dart';

void main() {
  late FfiExecutor db;
  setUp(() async {
    db = await FfiExecutor.openInMemory();
    await migrate(db);
    await seedExercisesIfEmpty(db);
  });
  tearDown(() async => db.close());
  test(
    'catalog batch and v8 migration failures roll back atomically',
    () async {
      await expectLater(
        syncExerciseCatalog(
          WorkoutFaultExecutor(
            db,
            WorkoutFaults()..runPrefix = 'INSERT INTO exercise_catalog_binding',
          ),
        ),
        throwsStateError,
      );
      expect(await listExercises(db), hasLength(52));
      expect(await readCatalogBindings(db), isEmpty);
      for (final table in [
        'set_detail',
        'session_prescription',
        'training_program',
        'exercise_catalog_binding',
      ]) {
        await db.run('DROP TABLE $table');
      }
      await db.run("UPDATE app_meta SET value='7' WHERE key='schema_version'");
      await expectLater(
        migrate(
          WorkoutFaultExecutor(
            db,
            WorkoutFaults()..runPrefix = 'CREATE TABLE session_prescription',
          ),
        ),
        throwsStateError,
      );
      expect(await getSchemaVersion(db), 7);
      expect(
        await db.all(
          "SELECT name FROM sqlite_master WHERE name='training_program'",
        ),
        isEmpty,
      );
      await migrate(db);
      expect(await getSchemaVersion(db), 9);
      await syncExerciseCatalog(db);
      expect(await listExercises(db), hasLength(71));
    },
  );
  test('upgrade exposes the shared catalog without importing a plan and is idempotent', () async {
    final front = (await listExercises(db)).firstWhere((e) => e.name == '前蹲');
    await db.run('UPDATE exercise SET is_archived=1 WHERE id=?', [front.id]);
    await syncExerciseCatalog(db);
    await syncExerciseCatalog(db);
    expect(await listExercises(db, includeArchived: true), hasLength(71));
    expect((await getExercise(db, front.id))!.isArchived, isTrue);
    expect(matchesExerciseQuery(front, '颈前深蹲'), isTrue);
    final cable = (await listExercises(db))
        .firstWhere((e) => e.name == '单臂绳索下拉');
    expect(matchesExerciseQuery(cable, '单手钢线下拉'), isTrue);
  });
  test(
    'existing custom identity and explicit archives are not overwritten',
    () async {
      final custom = await createCustomExercise(
        db,
        name: '哑铃上斜卧推',
        equipment: '哑铃',
        muscleGroup: '胸',
      );
      await syncExerciseCatalog(db);
      expect((await readCatalogBindings(db))['哑铃上斜卧推|哑铃'], custom.id);
      expect((await getExercise(db, custom.id))!.isCustom, isTrue);
    },
  );
}
