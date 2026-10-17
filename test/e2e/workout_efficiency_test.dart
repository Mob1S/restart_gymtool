import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/app/providers.dart';
import 'package:gym_tracker/features/workout/next_set_weight.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/repositories/backup_repo.dart';
import 'package:gym_tracker/data/repositories/exercise_repo.dart';
import 'package:gym_tracker/data/repositories/template_repo.dart';
import 'package:gym_tracker/domain/plans.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

import '../support/backup_fakes.dart';
import '../widget/backup_section_test.dart' show settle;

class _Wakelock extends WakelockPlusPlatformInterface {
  @override
  Future<void> toggle({required bool enable}) async {}
  @override
  Future<bool> get enabled async => false;
}

void main() {
  testWidgets(
    'planned workout: edit actual set, prepare next weight, replace, finish; plan unchanged',
    (t) async {
      wakelockPlusPlatformInstance = _Wakelock();
      final db = (await t.runAsync(() => FfiExecutor.openMigrated()))!;
      addTearDown(db.close);
      await t.runAsync(() => seedExercisesIfEmpty(db));
      final exercises = (await t.runAsync(() => listExercises(db)))!;
      final bench = exercises.firstWhere((e) => e.name == '卧推');
      final row = exercises.firstWhere((e) => e.name == '坐姿绳索划船');
      final plan = (await t.runAsync(
        () => saveTemplate(
          db,
          TemplateDraft(name: '效率验收', exerciseIds: [bench.id]),
        ),
      ))!;
      await t.pumpWidget(
        AppBootstrap(
          openDatabase: () async => db,
          backupFiles: MemoryBackupFiles(),
        ),
      );
      await settle(t);
      Future<void> tap(String text) async {
        for (
          var attempt = 0;
          attempt < 30 && find.text(text).evaluate().isEmpty;
          attempt++
        ) {
          await settle(t);
        }
        await t.ensureVisible(find.text(text).first);
        await settle(t);
        await t.tap(find.text(text).first);
        await settle(t);
      }

      await tap('开始训练');
      await tap('✓ 完成这组');
      await t.drag(
        find.descendant(
          of: find.byType(NextSetWeight),
          matching: find.byKey(const ValueKey('weight-adjuster')),
        ),
        const Offset(0, -16),
      );
      await settle(t);
      await tap('开始第 2 组');
      await tap('✓ 完成这组');
      await tap('本场已记 2 组');
      await tap('第 1 组 · 20 kg × 8');
      await t.enterText(find.widgetWithText(TextField, '实际次数'), '6');
      await tap('保存');
      await t.tapAt(const Offset(10, 10));
      await settle(t);
      await tap('动作设置');
      await tap('1.25 kg');
      await t.enterText(find.widgetWithText(TextField, '器械备忘'), '座椅 4\n😀');
      await tap('保存');
      await tap('替换当前动作');
      await t.enterText(find.widgetWithText(TextField, '搜索动作'), '坐姿绳索划船');
      await settle(t);
      await t.tap(find.widgetWithText(ListTile, '坐姿绳索划船'));
      await settle(t);
      await tap('替换为 坐姿绳索划船');
      await tap('✓ 完成这组');
      await tap('结束训练');
      expect(find.text('总容量（重量 × 次数）'), findsOneWidget);
      await t.runAsync(() async {
        final backup = await exportBackup(db, exportedAt: 0);
        final source = backup
            .rows('sessionExercises')
            .singleWhere((e) => e['exerciseId'] == bench.id);
        final target = backup
            .rows('sessionExercises')
            .singleWhere((e) => e['exerciseId'] == row.id);
        expect(
          backup
              .rows('sets')
              .where((s) => s['sessionExerciseId'] == source['id']),
          hasLength(2),
        );
        expect(
          backup
              .rows('sets')
              .where((s) => s['sessionExerciseId'] == source['id'])
              .map((s) => s['weight']),
          [20, 22.5],
        );
        expect(
          backup
              .rows('sets')
              .where(
                (s) =>
                    s['sessionExerciseId'] == target['id'] &&
                    s['isCompleted'] == true,
              ),
          hasLength(1),
        );
        expect(
          backup
              .rows('sets')
              .where((s) => s['isCompleted'] == true)
              .map((s) => s['reps']),
          [6, 8, 8],
        );
        expect(
          (await getTemplate(
            db,
            plan.template.id,
          ))!.exercises.single.entry.exerciseId,
          bench.id,
        );
        expect(
          backup.rows('exercisePreferences').single['equipmentNote'],
          '座椅 4\n😀',
        );
      });
      await t.pumpWidget(const SizedBox());
      await settle(t);
      expect(t.takeException(), isNull);
    },
  );
}
