import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/repositories/exercise_preferences_repo.dart';
import 'package:gym_tracker/data/repositories/workout_settings_repo.dart';
import 'package:gym_tracker/domain/record_management.dart';
import 'package:gym_tracker/domain/weight_value.dart';
import 'package:gym_tracker/domain/workout_edit.dart';
import 'package:gym_tracker/state/data_revision.dart';
import 'package:gym_tracker/state/exercise_preferences_controller.dart';

import '../support/workout_fixture.dart';
import '../support/workout_faults.dart';

void main() {
  test(
    'preference and pending native reading commit together with one revision',
    () async {
      final f = await workoutFixture();
      var original = (await readExercisePreferences(f.db, [
        f.benchId,
      ]))[f.benchId]!;
      original = await saveExercisePreference(
        f.db,
        f.benchId,
        expectedToken: original.token,
        equipmentNote: '座椅 4',
        isFavorite: true,
      );
      final revision = DataRevision();
      var changes = 0;
      revision.addListener(() => changes++);
      final prefs = ExercisePreferencesController(f.db, revision: revision);
      addTearDown(prefs.dispose);
      await prefs.load([f.benchId]);
      final result = await prefs.save(
        f.benchId,
        expectedToken: original.token,
        sessionId: f.controller.session!.id,
        pendingSetId: f.controller.currentExercise!.sets.single.id,
        pendingReading: EquipmentWeight(
          DecimalReading.parse('40'),
          WeightUnit.lb,
        ),
        kgStep: DecimalReading.parse('1.25'),
        lbStep: DecimalReading.parse('10'),
        showKgEquivalent: true,
      );
      expect(result, WorkoutWriteResult.saved);
      expect(changes, 1);
      final p = (await readExercisePreferences(f.db, [f.benchId, f.rowId]));
      expect(p[f.benchId]!.isFavorite, isTrue);
      expect(p[f.benchId]!.equipmentNote, '座椅 4');
      expect(p[f.benchId]!.weightUnit, WeightUnit.lb);
      expect(p[f.rowId]!.weightUnit, WeightUnit.kg);
      await f.controller.resume();
      expect(
        f.controller.currentExercise!.sets.single.equipmentWeight.label,
        '40 lb',
      );
      expect(
        f.controller.currentExercise!.sets.single.weight,
        closeTo(18.1436948, 1e-10),
      );
    },
  );

  test(
    'stale token, wrong owner and failed second write roll back both halves',
    () async {
      final f = await workoutFixture();
      final pending = f.controller.currentExercise!.sets.single;
      final original = (await readExercisePreferences(f.db, [
        f.benchId,
      ]))[f.benchId]!;
      Future<void> apply({
        String? token,
        String? exercise,
        bool fail = false,
      }) async {
        await applyPendingWeightSettings(
          fail
              ? WorkoutFaultExecutor(
                  f.db,
                  WorkoutFaults()..runPrefix = 'UPDATE set_entry',
                )
              : f.db,
          sessionId: f.controller.session!.id,
          pendingSetId: pending.id,
          exerciseId: exercise ?? f.benchId,
          expectedPreferenceToken: token ?? original.token,
          reading: EquipmentWeight(DecimalReading.parse('40'), WeightUnit.lb),
          kgStep: DecimalReading.parse('2.5'),
          lbStep: DecimalReading.parse('10'),
          showKgEquivalent: true,
        );
      }

      await expectLater(
        apply(token: 'stale'),
        throwsA(isA<RecordManagementException>()),
      );
      await expectLater(
        apply(exercise: f.rowId),
        throwsA(isA<RecordManagementException>()),
      );
      await expectLater(apply(fail: true), throwsStateError);
      expect(
        (await readExercisePreferences(f.db, [f.benchId]))[f.benchId]!.token,
        original.token,
      );
      await f.controller.resume();
      expect(
        f.controller.currentExercise!.sets.single.equipmentWeight.label,
        pending.equipmentWeight.label,
      );
      await f.controller.completeCurrentReading(EquipmentWeight.kg(20), 8);
      await expectLater(apply(), throwsA(isA<RecordManagementException>()));
      expect(
        (await readExercisePreferences(f.db, [f.benchId]))[f.benchId]!.token,
        original.token,
      );
    },
  );
}
