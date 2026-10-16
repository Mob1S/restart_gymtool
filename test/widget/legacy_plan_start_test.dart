import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/app/providers.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/repositories/backup_repo.dart';
import 'package:gym_tracker/data/repositories/template_repo.dart';
import 'package:gym_tracker/features/workout/record_page.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

import '../data/backup_repo_test.dart' show loadFixture;
import '../support/backup_fakes.dart';
import 'backup_section_test.dart' show settle;

class _Wake extends WakelockPlusPlatformInterface {
  @override
  Future<void> toggle({required bool enable}) async {}
  @override
  Future<bool> get enabled async => false;
}

void main() {
  late FfiExecutor db;
  late WakelockPlusPlatformInterface previousWake;
  setUp(() async {
    previousWake = wakelockPlusPlatformInstance;
    wakelockPlusPlatformInstance = _Wake();
    db = await FfiExecutor.openMigrated();
  });
  tearDown(() async {
    wakelockPlusPlatformInstance = previousWake;
    await db.close();
  });
  testWidgets(
    'restored push plan creates its archived exercise and a usable first set',
    (tester) async {
      await tester.runAsync(() async {
        await restoreBackup(db, await inspectBackup(db, loadFixture()));
        expect(
          (await getTemplate(db, 'plan-p'))!.exercises.single.exerciseName,
          '我的推胸',
        );
      });
      await tester.pumpWidget(
        AppBootstrap(
          openDatabase: () async => db,
          backupFiles: MemoryBackupFiles(),
        ),
      );
      await settle(tester);
      Future<void> tap(String label) async {
        await tester.ensureVisible(find.text(label).first);
        await tester.tap(find.text(label).first);
        await settle(tester);
      }

      await tap('开始新训练');
      expect(find.text('上一场训练还没结束'), findsOneWidget);
      await tap('结束它，开始新的');
      expect(find.byType(RecordPage), findsOneWidget);
      expect(find.text('推日'), findsOneWidget);
      expect(find.text('我的推胸'), findsWidgets);
      expect(find.textContaining('完成这组'), findsOneWidget);
      expect(find.text('这次训练还没有动作'), findsNothing);
      await tester.runAsync(() async {
        final snapshot = await exportBackup(db, exportedAt: 0);
        final active = snapshot
            .rows('sessions')
            .singleWhere((s) => s['finishedAt'] == null);
        final items = snapshot
            .rows('sessionExercises')
            .where((e) => e['sessionId'] == active['id'])
            .toList();
        expect(items, hasLength(1));
        expect(items.single['exerciseId'], 'custom-e');
        expect(
          snapshot
              .rows('sets')
              .where((s) => s['sessionExerciseId'] == items.single['id'])
              .single['isCompleted'],
          false,
        );
      });
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    },
  );
}
