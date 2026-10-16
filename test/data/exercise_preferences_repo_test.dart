import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/repositories/exercise_preferences_repo.dart';
import 'package:gym_tracker/data/repositories/exercise_picker_repo.dart';
import 'package:gym_tracker/data/repositories/backup_repo.dart';
import 'package:gym_tracker/domain/record_management.dart';

import '../support/workout_fixture.dart';

void main() {
  test('partial preference writes preserve other fields and defaults remove the row', () async {
    final f = await workoutFixture();
    var p = (await readExercisePreferences(f.db, [f.benchId]))[f.benchId]!;
    expect(p.weightStepKg, 2.5);
    p = await saveExercisePreference(
      f.db,
      f.benchId,
      expectedToken: p.token,
      weightStepMilli: 1250,
      equipmentNote: '  座椅4\n😀  ',
    );
    p = await saveExercisePreference(
      f.db,
      f.benchId,
      expectedToken: p.token,
      isFavorite: true,
    );
    expect(p.equipmentNote, '座椅4\n😀');
    expect(p.weightStepKg, 1.25);
    await expectLater(
      saveExercisePreference(
        f.db,
        f.benchId,
        expectedToken: 'old',
        equipmentNote: 'wrong',
      ),
      throwsA(isA<RecordManagementException>()),
    );
    await saveExercisePreference(
      f.db,
      f.benchId,
      expectedToken: p.token,
      weightStepMilli: 2500,
      isFavorite: false,
      equipmentNote: '',
    );
    expect(await f.db.all('SELECT * FROM exercise_preference'), isEmpty);
  });
  test(
    'recent comes only from actual completed sets, not plans or placeholders',
    () async {
      final f = await workoutFixture();
      expect((await loadExercisePickerData(f.db)).recentIds, isEmpty);
      await f.controller.completeCurrentSet(40, 8);
      expect((await loadExercisePickerData(f.db)).recentIds, [f.benchId]);
      await f.controller.addExercise(f.rowId);
      expect((await loadExercisePickerData(f.db)).recentIds, [f.benchId]);
      f.clock.value += 1000;
      await f.controller.completeCurrentSet(20, 8);
      expect((await loadExercisePickerData(f.db)).recentIds, [
        f.rowId,
        f.benchId,
      ]);
    },
  );
  test('preference change conflicts with restore preview', () async {
    final f = await workoutFixture();
    final backup = await exportBackup(f.db, exportedAt: 0);
    final preview = await inspectBackup(f.db, backup);
    final p = (await readExercisePreferences(f.db, [f.benchId]))[f.benchId]!;
    await saveExercisePreference(
      f.db,
      f.benchId,
      expectedToken: p.token,
      isFavorite: true,
    );
    await expectLater(restoreBackup(f.db, preview), throwsException);
    expect(
      (await loadExercisePickerData(f.db)).preferences[f.benchId]!.isFavorite,
      true,
    );
  });
}
