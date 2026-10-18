import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/sql_executor.dart';
import 'package:gym_tracker/data/builtin_programs.dart';
import 'package:gym_tracker/data/repositories/builtin_program_repo.dart';
import 'package:gym_tracker/data/repositories/exercise_repo.dart';
import 'package:gym_tracker/data/repositories/exercise_catalog_repo.dart';
import 'package:gym_tracker/data/repositories/training_program_repo.dart';
import 'package:gym_tracker/data/repositories/training_plan_repo.dart';
import 'package:gym_tracker/features/plans/builtin_plan_page.dart';
import 'package:gym_tracker/features/plans/program_editor.dart';
import 'package:gym_tracker/features/workout/effort_input.dart';
import 'package:gym_tracker/features/workout/exercise_picker.dart';
import 'package:gym_tracker/domain/training_prescription.dart';
import 'package:gym_tracker/state/data_revision.dart';
import 'package:gym_tracker/app/providers.dart';

import '../support/workout_faults.dart';

import 'backup_section_test.dart' show settle;

void main() {
  late FfiExecutor db;
  late DataRevision revision;
  setUp(() async {
    db = await FfiExecutor.openMigrated();
    await seedExercisesIfEmpty(db);
    await syncExerciseCatalog(db);
    revision = DataRevision();
  });
  tearDown(() async {
    revision.dispose();
    await db.close();
  });
  testWidgets(
    'catalog synchronization failure preserves access to existing records',
    (t) async {
      await t.runAsync(() async {
        await db.run('DELETE FROM exercise_catalog_binding');
      });
      final faulty = WorkoutFaultExecutor(
        db,
        WorkoutFaults()..runPrefix = 'INSERT INTO exercise_catalog_binding',
      );
      await t.pumpWidget(AppBootstrap(openDatabase: () async => faulty));
      for (var i = 0; i < 40 && find.text('管理计划').evaluate().isEmpty; i++) {
        await settle(t);
      }
      expect(find.text('管理计划'), findsOneWidget);
      expect(find.textContaining('动作库扩充暂未完成'), findsOneWidget);
      expect((await t.runAsync(() => readCatalogBindings(db)))!, isEmpty);
      expect((await t.runAsync(() => listExercises(db)))!, hasLength(71));
      await t.pumpWidget(const SizedBox());
      await settle(t);
    },
  );
  Future<void> boot(WidgetTester t, Widget child) async {
    t.view.physicalSize = const Size(360, 780);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    await t.pumpWidget(
      MultiProvider(
        providers: [
          Provider<SqlExecutor>.value(value: db),
          ChangeNotifierProvider<DataRevision>.value(value: revision),
        ],
        child: MaterialApp(home: child),
      ),
    );
    await settle(t);
  }

  testWidgets(
    'built-in preview imports editable multi-day program without narrow overflow',
    (t) async {
      await boot(t, const BuiltinPlanPage());
      expect(find.text('StrongLifts 5×5'), findsOneWidget);
      await t.tap(find.text('凯谭三分化 · 整理参考版'));
      await settle(t);
      expect(find.text('调整周期与休息'), findsOneWidget);
      await t.tap(find.text('调整周期与休息'));
      await t.pumpAndSettle();
      await t.tap(find.text('后加休息').first);
      await t.pumpAndSettle();
      await t.tap(find.text('调整周期与休息'));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('导入为我的计划'),
        450,
        scrollable: find.byType(Scrollable).first,
      );
      await t.pumpAndSettle();
      await t.tap(find.text('导入为我的计划'));
      await settle(t);
      final plans = (await t.runAsync(() => listTrainingPlans(db)))!;
      expect(plans.length, 1);
      expect(plans.single.days.length, 5);
      final p = (await t.runAsync(
        () => readTrainingProgram(db, plans.single.id),
      ))!;
      expect(p.stages.length, 11);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await settle(t);
    },
  );
  testWidgets(
    'manual stage advancement and per-occurrence targets are editable',
    (t) async {
      final plan = (await t.runAsync(
        () => importBuiltinProgram(db, builtinPrograms.first),
      ))!;
      await boot(t, ProgramEditor(planId: plan.id));
      await t.tap(find.text('进入下一阶段'));
      await settle(t);
      final p = (await t.runAsync(() => readTrainingProgram(db, plan.id)))!;
      expect(p.current.name, '第 2 周');
      expect(find.text('当前执行：第 2 周'), findsOneWidget);
      await t.scrollUntilVisible(
        find.text('卧推'),
        220,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(find.text('卧推'));
      await t.pumpAndSettle();
      expect(find.text('应用组次'), findsOneWidget);
      expect(find.text('添加一组目标'), findsOneWidget);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await settle(t);
    },
  );
  testWidgets(
    'optional RPE accepts half-steps and clears feedback without inventing a default',
    (t) async {
      Effort? value;
      await boot(
        t,
        Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => EffortInput(
              value: value,
              onChanged: (v) => setState(() => value = v),
            ),
          ),
        ),
      );
      expect(value, isNull);
      await t.tap(find.byKey(const ValueKey('effort-picker')));
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('RPE 9.5'),
        200,
        scrollable: find.byType(Scrollable).last,
      );
      await t.tap(find.text('RPE 9.5'));
      await t.pumpAndSettle();
      expect(value!.value, 9.5);
      await t.tap(find.byKey(const ValueKey('effort-picker')));
      await t.pumpAndSettle();
      await t.tap(find.text('不记录用力程度'));
      await t.pumpAndSettle();
      expect(value, isNull);
      await t.pumpWidget(const SizedBox());
      await settle(t);
    },
  );
  testWidgets(
    'catalog aliases resolve in shared exercise picker without plan import',
    (t) async {
      await boot(
        t,
        Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showExercisePicker(context),
              child: const Text('选择'),
            ),
          ),
        ),
      );
      await t.tap(find.text('选择'));
      await settle(t);
      await t.enterText(find.byType(TextField).first, '颈前深蹲');
      await t.pumpAndSettle();
      expect(find.text('前蹲'), findsOneWidget);
      expect(find.text('高脚杯深蹲'), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await settle(t);
    },
  );
}
