import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/repositories/backup_repo.dart';
import 'package:gym_tracker/data/repositories/exercise_repo.dart';
import 'package:gym_tracker/data/repositories/template_repo.dart';
import 'package:gym_tracker/domain/plans.dart';
import 'package:gym_tracker/state/active_session_controller.dart';

void main() {
  test('creating, editing, starting and deleting a push plan preserves every original library row', () async {
    final db = await FfiExecutor.openMigrated();
    final active = ActiveSessionController(db);
    try {
      await seedExercisesIfEmpty(db);
      final original = (await exportBackup(
        db,
        exportedAt: 0,
      )).rows('exercises');
      expect(original, hasLength(52));
      final names = ['卧推', '器械推胸', '绳索夹胸'];
      final ids = [
        for (final name in names)
          original.singleWhere((e) => e['name'] == name)['id'] as String,
      ];
      final plan = await saveTemplate(
        db,
        TemplateDraft(name: '推日', exerciseIds: ids),
      );
      expect(await active.startNew(), StartResult.started);
      expect(active.session!.name, '推日');
      expect(active.exercises.map((e) => e.exerciseName), names);
      expect(
        active.exercises.every(
          (e) => e.sets.length == 1 && !e.sets.single.isCompleted,
        ),
        true,
      );
      await saveTemplate(
        db,
        TemplateDraft(
          id: plan.template.id,
          name: '推日调整',
          exerciseIds: ids.reversed.toList(),
          expectedToken: plan.editToken,
        ),
      );
      expect(active.exercises.map((e) => e.exerciseName), names);
      await deleteTemplate(
        db,
        (await inspectTemplateDeletion(db, plan.template.id))!,
      );
      final after = await exportBackup(db, exportedAt: 0);
      expect(after.rows('exercises'), original);
      expect(after.rows('sessionExercises').map((e) => e['exerciseId']), ids);
      expect(after.rows('sets'), hasLength(3));
      expect(after.rows('sessions').single['finishedAt'], isNull);
      expect(after.rows('sessions').single['templateId'], isNull);
    } finally {
      active.dispose();
      await db.close();
    }
  });
}
