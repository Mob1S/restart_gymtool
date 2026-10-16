import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/repositories/session_repo.dart';
import 'package:gym_tracker/state/active_session_controller.dart';
import 'package:gym_tracker/state/record_management_controller.dart';

void main() {
  test('deleting another history preserves active state; deleting active resets once', () async {
    final db = await FfiExecutor.openMigrated();
    final active = ActiveSessionController(db);
    var notifications = 0;
    final c = RecordManagementController(
      db,
      active: active,
      onChanged: () => notifications++,
    );
    try {
      final history = await createSession(db);
      await finishSession(
        db,
        history.id,
        DateTime.now().millisecondsSinceEpoch,
      );
      await active.startNew();
      final activeId = active.session!.id;
      final p = (await c.previewDelete(history.id))!;
      expect(await c.confirmDelete(p), true);
      expect(active.session!.id, activeId);
      expect(notifications, 1);
      final current = (await c.previewDelete(activeId))!;
      final first = c.confirmDelete(current);
      expect(await c.confirmDelete(current), false);
      expect(await first, true);
      expect(active.session, isNull);
      expect(notifications, 2);
      expect(c.busy, false);
    } finally {
      c.dispose();
      active.dispose();
      await db.close();
    }
  });
}
