import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/repositories/training_plan_repo.dart';
import 'package:gym_tracker/domain/training_plans.dart';
import 'package:gym_tracker/state/plan_controller.dart';

void main() {
  test('draft cancel has no rows; stale save keeps local text; double save executes once', () async {
    final db = await FfiExecutor.openMigrated();
    var changes = 0;
    final c = PlanController(db, onChanged: () => changes++);
    try {
      await c.loadDraft(null);
      c.updateName('discarded');
      c.discardDraft();
      expect(await listTrainingPlans(db), isEmpty);
      await c.loadDraft(null);
      c.updateName('A');
      final first = c.saveDraft();
      expect(await c.saveDraft(), false);
      expect(await first, true);
      expect(changes, 1);
      final current = (await getTrainingPlan(db, c.draft!.id!))!;
      await saveTrainingPlan(
        db,
        TrainingPlanDraft(
          id: current.id,
          name: 'external',
          days: [],
          expectedToken: current.token,
        ),
      );
      c.updateName('local');
      expect(await c.saveDraft(), false);
      expect(c.draft!.name, 'local');
      expect(c.dirty, true);
      expect(c.message, contains('已变化'));
      expect(c.busy, false);
    } finally {
      c.dispose();
      await db.close();
    }
  });
}
