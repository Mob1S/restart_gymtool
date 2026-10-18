import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/app/providers.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/sql_executor.dart';
import 'package:gym_tracker/data/repositories/training_plan_repo.dart';
import 'package:gym_tracker/features/plans/plan_editor_page.dart';
import 'package:gym_tracker/features/plans/day_editor_sheet.dart';
import 'package:gym_tracker/domain/training_plans.dart';
import 'package:provider/provider.dart';

import '../support/backup_fakes.dart';
import 'backup_section_test.dart' show settle;

void main() {
  late FfiExecutor db;
  setUp(() async {
    db = await FfiExecutor.openMigrated();
  });
  tearDown(() async {
    await db.close();
  });
  Future<void> tap(WidgetTester t, String label) async {
    await t.ensureVisible(find.text(label).last);
    await t.tap(find.text(label).last);
    await settle(t);
  }

  Future<void> boot(WidgetTester t) async {
    await t.pumpWidget(
      AppBootstrap(
        openDatabase: () async => db,
        backupFiles: MemoryBackupFiles(),
      ),
    );
    await settle(t);
  }

  Future<void> addDay(WidgetTester t, String name, String exercise) async {
    await tap(t, '添加训练日');
    await t.enterText(find.widgetWithText(TextField, '训练日名称'), name);
    await tap(t, '添加动作');
    await t.enterText(find.widgetWithText(TextField, '搜索动作'), exercise);
    await settle(t);
    await t.tap(find.widgetWithText(ListTile, exercise));
    await settle(t);
    await tap(t, '添加 1 个动作');
    await tap(t, '完成');
  }

  testWidgets(
    'parent plan saves two independent days and local edits cancel cleanly',
    (t) async {
      await boot(t);
      expect(find.text('新建计划'), findsNothing);
      await tap(t, '管理计划');
      await tap(t, '新建计划');
      await t.enterText(find.widgetWithText(TextField, '计划名称'), '力量进阶');
      await addDay(t, '上肢 A', '卧推');
      await addDay(t, '下肢 A', '深蹲');
      await t.runAsync(() async {
        expect(await listTrainingPlans(db), isEmpty);
      });
      await tap(t, '保存');
      late String id;
      await t.runAsync(() async {
        final plan = (await listTrainingPlans(db)).single;
        id = plan.id;
        expect(
          plan.activatedOn,
          isNull,
          reason: 'Management alone must not activate leading rest',
        );
        expect(plan.days.map((day) => day.name), ['上肢 A', '下肢 A']);
        expect(plan.days.first.exerciseIds, isNot(plan.days.last.exerciseIds));
      });
      await tap(t, '力量进阶');
      await tap(t, '1. 上肢 A');
      await t.enterText(find.widgetWithText(TextField, '训练日名称'), '未保存修改');
      await tap(t, '取消');
      await tap(t, '丢弃');
      expect(find.text('1. 上肢 A'), findsOneWidget);
      expect(find.text('未保存修改'), findsNothing);
      await t.tap(find.byTooltip('下移训练日').first);
      await settle(t);
      expect(find.text('1. 下肢 A'), findsOneWidget);
      await t.enterText(find.widgetWithText(TextField, '计划名称'), '未保存父计划');
      await t.pageBack();
      await settle(t);
      await tap(t, '丢弃');
      await t.runAsync(() async {
        final plan = (await getTrainingPlan(db, id))!;
        expect(plan.name, '力量进阶');
        expect(plan.days.map((day) => day.name), ['上肢 A', '下肢 A']);
      });
      expect(find.byType(PlanEditorPage), findsNothing);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await settle(t);
    },
  );

  testWidgets('discarding a new parent leaves no plan or training-day shells', (
    t,
  ) async {
    await boot(t);
    await tap(t, '管理计划');
    await tap(t, '新建计划');
    await t.enterText(find.widgetWithText(TextField, '计划名称'), '草稿');
    await addDay(t, '任意日', '深蹲');
    await t.pageBack();
    await settle(t);
    await tap(t, '丢弃');
    await t.runAsync(() async {
      expect(await listTrainingPlans(db), isEmpty);
      expect(await db.all('SELECT id FROM split_template'), isEmpty);
    });
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
    await settle(t);
  });

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'landscape day editor can finish above a 300px keyboard at scale $scale',
      (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = const Size(640, 360);
        t.view.padding = const FakeViewPadding(top: 24);
        t.view.viewPadding = const FakeViewPadding(top: 24);
        addTearDown(t.view.resetPhysicalSize);
        addTearDown(t.view.resetDevicePixelRatio);
        addTearDown(t.view.resetPadding);
        addTearDown(t.view.resetViewPadding);
        addTearDown(t.view.resetViewInsets);
        TrainingDayDraft? result;
        await t.pumpWidget(
          Provider<SqlExecutor>.value(
            value: db,
            child: MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!,
              ),
              home: Scaffold(
                body: Builder(
                  builder: (context) => TextButton(
                    onPressed: () async {
                      result = await showDayEditorSheet(context);
                    },
                    child: const Text('打开日编辑'),
                  ),
                ),
              ),
            ),
          ),
        );
        await t.tap(find.text('打开日编辑'));
        await settle(t);
        await t.enterText(find.widgetWithText(TextField, '训练日名称'), '横屏日');
        t.view.viewInsets = const FakeViewPadding(bottom: 300);
        await settle(t);
        expect(t.takeException(), isNull);
        await t.scrollUntilVisible(
          find.text('完成'),
          -60,
          scrollable: find
              .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable),
              )
              .first,
        );
        await settle(t);
        expect(find.text('完成').hitTestable(), findsOneWidget);
        await t.tap(find.text('完成').hitTestable());
        await settle(t);
        expect(result?.name, '横屏日');
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await settle(t);
      },
    );
  }
}
