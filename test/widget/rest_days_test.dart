import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/sql_executor.dart';
import 'package:gym_tracker/data/repositories/training_plan_repo.dart';
import 'package:gym_tracker/domain/training_plans.dart';
import 'package:gym_tracker/features/plans/day_editor_sheet.dart';
import 'package:gym_tracker/features/workout/workout_home_page.dart';
import 'package:gym_tracker/state/active_session_controller.dart';
import 'package:gym_tracker/state/data_revision.dart';
import 'package:provider/provider.dart';

import 'backup_section_test.dart' show settle;

void main() {
  late FfiExecutor db;
  late ActiveSessionController active;
  late DataRevision revision;
  late DateTime clock;
  setUp(() async {
    db = await FfiExecutor.openMigrated();
    clock = DateTime(2026, 10, 18, 23, 59, 50);
    revision = DataRevision();
    active = ActiveSessionController(
      db,
      now: () => clock.millisecondsSinceEpoch,
      onDataChanged: revision.changed,
    );
  });
  tearDown(() async {
    active.dispose();
    revision.dispose();
    await db.close();
  });
  Future<TrainingPlanDetail> make({
    bool onlyRest = false,
    bool completed = true,
  }) async {
    final p = await saveTrainingPlan(
      db,
      TrainingPlanDraft(
        name: '自然日周期',
        days: [
          if (!onlyRest) TrainingDayDraft(name: '上肢', exerciseIds: []),
          TrainingDayDraft(
            name: '恢复日',
            kind: TrainingDayKind.rest,
            exerciseIds: [],
          ),
          if (!onlyRest) TrainingDayDraft(name: '下肢', exerciseIds: []),
        ],
      ),
    );
    if (completed && !onlyRest) {
      await db.run(
        'INSERT INTO session(id,started_at,finished_at,plan_id,template_id,origin) VALUES(?,?,?,?,?,?)',
        [
          'done',
          DateTime(2026, 10, 18, 11).millisecondsSinceEpoch,
          DateTime(2026, 10, 18, 12).millisecondsSinceEpoch,
          p.id,
          p.days.first.id,
          'live',
        ],
      );
    }
    return p;
  }

  Future<void> boot(
    WidgetTester t, {
    Size size = const Size(390, 844),
    double scale = 1,
    Widget? child,
  }) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = size;
    addTearDown(t.view.resetDevicePixelRatio);
    addTearDown(t.view.resetPhysicalSize);
    await t.pumpWidget(
      MultiProvider(
        providers: [
          Provider<SqlExecutor>.value(value: db),
          ChangeNotifierProvider<ActiveSessionController>.value(value: active),
          ChangeNotifierProvider<DataRevision>.value(value: revision),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: child ?? WorkoutHomePage(now: () => clock),
            bottomNavigationBar: const SizedBox(height: 80),
          ),
        ),
      ),
    );
    await settle(t);
  }

  Future<void> tap(WidgetTester t, String label) async {
    final target = find.text(label).last;
    await t.ensureVisible(target);
    await t.tap(target);
    await settle(t);
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await settle(t);
  }

  testWidgets('completion today is centered status with tomorrow rest', (
    t,
  ) async {
    await t.runAsync(() => make());
    await boot(t);
    expect(find.text('今日已完成'), findsOneWidget);
    expect(find.text('明天休息'), findsOneWidget);
    expect(find.text('下一次：下肢'), findsOneWidget);
    expect(find.text('本次没有动作，可在训练中添加'), findsNothing);
    final area = t.getRect(find.byKey(const ValueKey('training-content')));
    final status = t.getRect(find.byKey(const ValueKey('home-primary-action')));
    expect((status.center.dy - area.center.dy).abs(), lessThan(1));
    expect(t.takeException(), isNull);
    await close(t);
  });
  testWidgets('midnight refreshes completed into rest and then training', (
    t,
  ) async {
    await t.runAsync(() => make());
    await boot(t);
    clock = DateTime(2026, 10, 19);
    await t.pump(const Duration(seconds: 11));
    await settle(t);
    expect(find.text('今天休息'), findsOneWidget);
    expect(find.text('明天休息'), findsNothing);
    clock = DateTime(2026, 10, 20);
    await t.pump(const Duration(days: 1));
    await settle(t);
    expect(find.text('开始训练'), findsOneWidget);
    expect(find.text('今天休息'), findsNothing);
    expect(find.text('下肢'), findsWidgets);
    expect(t.takeException(), isNull);
    await close(t);
  });
  testWidgets(
    'resume after multiple days stops at waiting training and clears manual override',
    (t) async {
      await t.runAsync(() => make());
      clock = DateTime(2026, 10, 19, 10);
      await boot(t);
      await tap(t, '选择训练日');
      await tap(t, '上肢');
      expect(find.text('开始训练'), findsOneWidget);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      clock = DateTime(2026, 10, 25, 10);
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(t);
      expect(find.text('下肢'), findsWidgets);
      expect(find.text('今天休息'), findsNothing);
      expect(t.takeException(), isNull);
      await close(t);
    },
  );
  testWidgets(
    'rest offers free training and picker contains training entries only',
    (t) async {
      final p = (await t.runAsync(() => make()))!;
      clock = DateTime(2026, 10, 19, 10);
      await boot(t);
      expect(find.text('今天休息'), findsOneWidget);
      await tap(t, '选择训练日');
      expect(find.widgetWithText(ListTile, '恢复日'), findsNothing);
      await tap(t, '取消');
      await tap(t, '自由训练');
      expect(find.text('开始训练'), findsOneWidget);
      expect(find.text('今天休息'), findsNothing);
      await t.runAsync(() async {
        expect((await getTrainingPlan(db, p.id))!.days.length, 3);
        expect(await db.all('SELECT id FROM session'), hasLength(1));
      });
      expect(t.takeException(), isNull);
      await close(t);
    },
  );
  testWidgets(
    'active workout takes priority on rest day and persists across midnight',
    (t) async {
      await t.runAsync(() async {
        await make();
        await db.run(
          "INSERT INTO session(id,started_at,origin) VALUES('ongoing',1,'live')",
        );
      });
      clock = DateTime(2026, 10, 19, 23, 59, 50);
      await boot(t);
      expect(find.text('继续训练'), findsOneWidget);
      expect(find.text('今天休息'), findsNothing);
      expect(find.text('恢复日'), findsOneWidget);
      clock = DateTime(2026, 10, 20);
      await t.pump(const Duration(seconds: 11));
      await settle(t);
      expect(find.text('继续训练'), findsOneWidget);
      expect(active.session!.id, 'ongoing');
      await t.runAsync(() async {
        expect(
          await db.all('SELECT id FROM session WHERE finished_at IS NULL'),
          hasLength(1),
        );
      });
      expect(t.takeException(), isNull);
      await close(t);
    },
  );
  for (final view in [
    (const Size(320, 568), 1.0),
    (const Size(640, 360), 1.0),
    (const Size(390, 844), 2.0),
  ]) {
    testWidgets('rest controls reachable in ${view.$1} scale ${view.$2}', (
      t,
    ) async {
      await t.runAsync(() => make(onlyRest: true));
      await boot(t, size: view.$1, scale: view.$2);
      expect(find.text('今天休息'), findsOneWidget);
      if (view.$2 == 2.0) {
        expect(
          t.getSize(find.byKey(const ValueKey('home-primary-action'))).height,
          greaterThan(56),
          reason: 'Large rest status text must not be clipped',
        );
      }
      expect(find.textContaining('下一次：'), findsNothing);
      await t.ensureVisible(find.text('管理计划'));
      await settle(t);
      expect(find.text('管理计划').hitTestable(), findsOneWidget);
      expect(t.takeException(), isNull);
      await close(t);
    });
  }
  testWidgets(
    'type conversion requires clearing confirmation and only changes draft',
    (t) async {
      final p = (await t.runAsync(() async {
        await db.run(
          "INSERT INTO exercise(id,name,created_at) VALUES('e','卧推',0)",
        );
        return saveTrainingPlan(
          db,
          TrainingPlanDraft(
            name: '转换',
            days: [
              TrainingDayDraft(name: '上肢', exerciseIds: ['e']),
            ],
          ),
        );
      }))!;
      TrainingDayDraft? result;
      await boot(
        t,
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDayEditorSheet(
                context,
                day: p.days.first.toDraft(),
              );
            },
            child: const Text('编辑'),
          ),
        ),
      );
      await tap(t, '编辑');
      await tap(t, '休息日');
      expect(find.text('改为休息日并清除动作？'), findsOneWidget);
      await tap(t, '取消');
      expect(find.text('1. 卧推'), findsOneWidget);
      await tap(t, '休息日');
      await tap(t, '清除并改为休息日');
      expect(find.text('添加动作'), findsNothing);
      await tap(t, '完成');
      expect(result!.kind, TrainingDayKind.rest);
      expect(result!.exerciseIds, isEmpty);
      await t.runAsync(() async {
        final saved = (await getTrainingPlan(db, p.id))!;
        expect(saved.days.first.kind, TrainingDayKind.training);
        expect(saved.days.first.exerciseIds, ['e']);
      });
      expect(t.takeException(), isNull);
      await close(t);
    },
  );
  testWidgets(
    'new rest day has no exercise editor; changing back creates empty training',
    (t) async {
      TrainingDayDraft? result;
      await boot(
        t,
        child: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              result = await showDayEditorSheet(
                context,
                initialKind: TrainingDayKind.rest,
              );
            },
            child: const Text('新增'),
          ),
        ),
      );
      await tap(t, '新增');
      expect(find.text('添加动作'), findsNothing);
      await tap(t, '训练日');
      expect(find.text('添加动作'), findsOneWidget);
      await tap(t, '完成');
      expect(result!.kind, TrainingDayKind.training);
      expect(result!.exerciseIds, isEmpty);
      expect(t.takeException(), isNull);
      await close(t);
    },
  );
}
