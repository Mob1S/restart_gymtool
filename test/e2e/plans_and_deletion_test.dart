import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/repositories/backup_repo.dart';
import 'package:gym_tracker/data/repositories/import_repo.dart';
import 'package:gym_tracker/data/repositories/template_repo.dart';
import 'package:gym_tracker/data/repositories/training_plan_repo.dart';
import 'package:gym_tracker/data/repositories/workout_plan_repo.dart';
import 'package:gym_tracker/data/repositories/record_management_repo.dart';
import 'package:gym_tracker/data/repositories/progress_repo.dart';
import 'package:gym_tracker/domain/import_preview.dart';
import 'package:gym_tracker/domain/workout_csv.dart';
import 'package:gym_tracker/domain/plans.dart';
import 'package:gym_tracker/state/active_session_controller.dart';
import 'package:gym_tracker/state/plan_controller.dart';

import '../data/backup_repo_test.dart' show loadFixture;

void main() {
  test('legacy plans, archived prefill, CSV, current-plan edit/delete, PR deletion and backup round trip', () async {
    final db = await FfiExecutor.openMigrated();
    final target = await FfiExecutor.openMigrated();
    final active = ActiveSessionController(db);
    final plans = PlanController(
      db,
      onChanged: () {},
      onDayDeleted: active.detachTemplate,
      onPlanDeleted: active.detachPlan,
    );
    try {
      await restoreBackup(
        db,
        await inspectBackup(db, loadFixture('legacy-v2')),
      );
      final old = (await getTemplate(db, 'plan-p'))!;
      expect(old.exercises.single.isArchived, true);
      final b = await saveTemplate(
        db,
        TemplateDraft(name: 'B', exerciseIds: ['custom-e']),
      );
      expect(await active.startNew(), StartResult.conflict);
      expect(active.session!.id, 'active-s');
      await active.completeCurrentSet(50, 8);
      await active.endWorkout();
      expect((await loadNextWorkout(db)).templateId, b.template.id);
      await active.startNew();
      expect(active.exercises.single.sets.single.weight, 50);
      final currentId = active.session!.id;
      final parsed = parseWorkoutCsv(
        'Date,Workout Name,Exercise Name,Weight,Reps\n2030-01-01,PR,我的推胸,100,8',
      );
      final draft = buildImportDraft(parsed, await loadImportCatalog(db));
      final imported = await importWorkouts(
        db,
        confirmImportDraft(draft, ImportSelection.defaults(draft)),
      );
      expect((await loadNextWorkout(db)).templateId, b.template.id);
      expect(active.session!.id, currentId);
      await saveTemplate(
        db,
        TemplateDraft(
          id: b.template.id,
          name: 'empty B',
          exerciseIds: [],
          expectedToken: b.editToken,
        ),
      );
      expect(active.exercises, hasLength(1));
      expect(active.session!.name, 'B');
      final parent = (await listTrainingPlans(db)).single;
      await plans.loadDraft(parent.id);
      plans.removeDay(
        plans.draft!.days.indexWhere((day) => day.id == b.template.id),
      );
      expect(await plans.saveDraft(), true);
      expect(active.session!.templateId, isNull);
      expect(active.exercises.single.sets.single.weight, 50);
      expect(
        (await listAllCompletedSetFacts(db)).map((s) => s.weight),
        contains(100),
      );
      await deleteSession(
        db,
        (await inspectSessionDeletion(db, imported.sessionIds.single))!,
      );
      expect((await listAllCompletedSetFacts(db)).map((s) => s.weight), [
        50,
        50,
      ]);
      await active.completeCurrentSet(50, 8);
      await active.endWorkout();
      await deleteTemplate(db, (await inspectTemplateDeletion(db, 'plan-p'))!);
      expect(
        await plans.confirmDelete((await getTrainingPlan(db, parent.id))!),
        true,
      );
      expect((await loadNextWorkout(db)).exerciseIds, ['custom-e']);
      final backup = await exportBackup(db, exportedAt: 0);
      await restoreBackup(target, await inspectBackup(target, backup));
      expect((await exportBackup(target, exportedAt: 0)).data, backup.data);
      expect(await target.all('PRAGMA foreign_key_check'), isEmpty);
    } finally {
      plans.dispose();
      active.dispose();
      await db.close();
      await target.close();
    }
  });
}
