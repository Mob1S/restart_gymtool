import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gym_tracker/app/app_shell.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/sql_executor.dart';
import 'package:gym_tracker/data/repositories/session_repo.dart';
import 'package:gym_tracker/data/repositories/settings_repo.dart';
import 'package:gym_tracker/data/repositories/training_plan_repo.dart';
import 'package:gym_tracker/domain/training_plans.dart';
import 'package:gym_tracker/features/workout/training_calendar.dart';
import 'package:gym_tracker/features/workout/workout_home_page.dart';
import 'package:gym_tracker/state/active_session_controller.dart';
import 'package:gym_tracker/state/data_revision.dart';
import 'package:gym_tracker/ui/theme.dart';
import 'package:gym_tracker/ui/tokens.dart';
import 'package:provider/provider.dart';

import 'backup_section_test.dart' show settle;

class _GatedExecutor implements SqlExecutor {
  final SqlExecutor inner;
  Completer<void>? nextTransaction;
  _GatedExecutor(this.inner);
  @override
  Future<T> transaction<T>(Future<T> Function(SqlExecutor tx) action) async {
    final gate = nextTransaction;
    nextTransaction = null;
    if (gate != null) {
      await gate.future;
    }
    return inner.transaction(action);
  }

  @override
  Future<void> run(String sql, [List<Object?>? params]) =>
      inner.run(sql, params);
  @override
  Future<List<T>> all<T>(String sql, [List<Object?>? params]) =>
      inner.all<T>(sql, params);
  @override
  Future<T?> first<T>(String sql, [List<Object?>? params]) =>
      inner.first<T>(sql, params);
}

void main() {
  late FfiExecutor db;
  late ActiveSessionController active;
  late DataRevision revision;
  GoRouter? router;
  setUp(() async {
    db = await FfiExecutor.openMigrated();
    revision = DataRevision();
    active = ActiveSessionController(db, onDataChanged: revision.changed);
  });
  tearDown(() async {
    router?.dispose();
    router = null;
    active.dispose();
    revision.dispose();
    await db.close();
  });
  Future<void> boot(
    WidgetTester t, {
    Size size = const Size(360, 780),
    double scale = 1,
    SqlExecutor? homeExecutor,
    bool realShell = false,
  }) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => realShell
              ? const AppShell(child: WorkoutHomePage())
              : const Scaffold(
                  body: WorkoutHomePage(),
                  bottomNavigationBar: SizedBox(height: 80),
                ),
        ),
        GoRoute(
          path: '/history',
          builder: (_, state) => Scaffold(
            body: Text('history ${state.uri.queryParameters['date']}'),
          ),
        ),
        GoRoute(
          path: '/session/:id',
          builder: (_, _) => const Scaffold(body: Text('record')),
        ),
      ],
    );
    await t.pumpWidget(
      MultiProvider(
        providers: [
          Provider<SqlExecutor>.value(value: homeExecutor ?? db),
          ChangeNotifierProvider<ActiveSessionController>.value(value: active),
          ChangeNotifierProvider<DataRevision>.value(value: revision),
        ],
        child: MaterialApp.router(
          theme: buildTheme(AppColors.light),
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
        ),
      ),
    );
    await settle(t);
  }

  Future<void> tap(WidgetTester t, String text) async {
    await t.ensureVisible(find.text(text).last);
    await settle(t);
    await t.tap(find.text(text).last.hitTestable());
    await settle(t);
  }

  Future<TrainingPlanDetail> plan(String name, int dayCount) =>
      saveTrainingPlan(
        db,
        TrainingPlanDraft(
          name: name,
          days: [
            for (var i = 0; i < dayCount; i++)
              TrainingDayDraft(name: '$name 日${i + 1}', exerciseIds: []),
          ],
        ),
      );

  testWidgets(
    '360 by 780 central button stays centered in five and six-row months',
    (t) async {
      await t.runAsync(() => plan('力量进阶', 4));
      await boot(t);
      for (var i = 0; i < 14; i++) {
        final body = t.getRect(find.byKey(const ValueKey('training-content')));
        final button = t.getRect(
          find.byKey(const ValueKey('home-primary-action')),
        );
        expect(button.center.dy, closeTo(body.center.dy, 2));
        expect(
          t.getRect(find.byType(TrainingCalendar)).bottom,
          lessThan(button.top),
        );
        expect(
          t.getRect(find.byKey(const ValueKey('home-plan-card'))).top,
          greaterThan(button.bottom),
        );
        expect(t.takeException(), isNull);
        await t.tap(find.byTooltip('下个月'));
        await settle(t);
      }
      expect(find.text('新建计划'), findsNothing);
      await t.pumpWidget(const SizedBox());
      await settle(t);
    },
  );

  testWidgets('calendar click only navigates to that local date', (t) async {
    final parent = (await t.runAsync(() => plan('计划 A', 2)))!;
    await boot(t);
    final month = t
        .widget<TrainingCalendar>(find.byType(TrainingCalendar))
        .displayedMonth;
    final key = '${month.year}-${month.month.toString().padLeft(2, '0')}-01';
    await t.tap(find.byKey(ValueKey('calendar-day-$key')));
    await settle(t);
    expect(find.text('history $key'), findsOneWidget);
    await t.runAsync(() async {
      expect(await getSetting(db, activeTrainingPlanKey), parent.id);
      expect(await listSessions(db, 10), isEmpty);
    });
    await t.pumpWidget(const SizedBox());
    await settle(t);
  });

  testWidgets('marks persist until the last same-day completion is removed', (
    t,
  ) async {
    final now = DateTime.now();
    final key =
        '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    await t.runAsync(
      () => db.run(
        'INSERT INTO session(id,started_at,finished_at) VALUES(?,?,?),(?,?,?)',
        [
          'one',
          now.millisecondsSinceEpoch,
          now.millisecondsSinceEpoch + 1,
          'two',
          now.millisecondsSinceEpoch,
          now.millisecondsSinceEpoch + 2,
        ],
      ),
    );
    await boot(t);
    final marker = find.byKey(ValueKey('calendar-completed-$key'));
    expect(marker, findsOneWidget);
    await t.runAsync(() => db.run('DELETE FROM session WHERE id=?', ['one']));
    revision.changed();
    await settle(t);
    expect(marker, findsOneWidget);
    await t.runAsync(() => db.run('DELETE FROM session WHERE id=?', ['two']));
    revision.changed();
    await settle(t);
    expect(marker, findsNothing);
    await t.pumpWidget(const SizedBox());
    await settle(t);
  });

  testWidgets(
    'eight arbitrary plans and days select independently and restore only parent',
    (t) async {
      final parents = (await t.runAsync(
        () async => [
          for (var i = 0; i < 8; i++) await plan('计划 $i', i == 7 ? 8 : i % 4),
        ],
      ))!;
      await boot(t);
      await tap(t, '切换计划');
      await t.scrollUntilVisible(
        find.text('计划 7'),
        220,
        scrollable: find.byType(Scrollable).last,
      );
      await tap(t, '计划 7');
      await tap(t, '选择训练日');
      await t.scrollUntilVisible(
        find.text('计划 7 日8'),
        220,
        scrollable: find.byType(Scrollable).last,
      );
      await tap(t, '计划 7 日8');
      expect(find.text('计划 7 日8'), findsWidgets);
      await t.runAsync(() async {
        expect(await getSetting(db, activeTrainingPlanKey), parents.last.id);
      });
      await t.pumpWidget(const SizedBox());
      await settle(t);
      router!.dispose();
      router = null;
      await boot(t);
      expect(find.text('计划 7 日1'), findsWidgets);
      expect(find.text('计划 7 日8'), findsNothing);
      await tap(t, '切换计划');
      await t.scrollUntilVisible(
        find.text('自由训练'),
        220,
        scrollable: find.byType(Scrollable).last,
      );
      await t.drag(find.byType(Scrollable).last, const Offset(0, -220));
      await settle(t);
      await tap(t, '自由训练');
      expect(find.text('自由训练'), findsOneWidget);
      expect(find.text('不推进任何计划的轮换'), findsNothing);
      final button = t.widget<FilledButton>(
        find.descendant(
          of: find.byKey(const ValueKey('home-primary-action')),
          matching: find.byType(FilledButton),
        ),
      );
      expect(button.onPressed, isNotNull);
      await t.pumpWidget(const SizedBox());
      await settle(t);
    },
  );

  for (final viewport in [
    (const Size(320, 480), 1.0),
    (const Size(640, 360), 1.0),
    (const Size(360, 780), 2.0),
  ]) {
    testWidgets(
      'home controls remain reachable at ${viewport.$1} scale ${viewport.$2}',
      (t) async {
        await t.runAsync(() => plan('这是允许自由命名且能够完整显示的长训练计划名称', 4));
        await boot(t, size: viewport.$1, scale: viewport.$2);
        await t.ensureVisible(
          find.byKey(const ValueKey('home-primary-action')),
        );
        await settle(t);
        expect(t.takeException(), isNull);
        await t.ensureVisible(find.text('管理计划'));
        await settle(t);
        expect(
          t.getRect(find.text('管理计划')).bottom,
          lessThanOrEqualTo(viewport.$1.height),
        );
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await settle(t);
      },
    );
  }

  testWidgets('continuing is primary and does not create a second session', (
    t,
  ) async {
    await t.runAsync(() => active.startNew(freeTraining: true));
    final id = active.session!.id;
    await boot(t);
    expect(find.text('继续训练'), findsOneWidget);
    await tap(t, '继续训练');
    expect(find.text('record'), findsOneWidget);
    await t.runAsync(() async {
      expect(
        (await db.all<Map<String, Object?>>('SELECT id FROM session'))
            .single['id'],
        id,
      );
    });
    await t.pumpWidget(const SizedBox());
    await settle(t);
  });

  testWidgets(
    'no plan supports free training; zero-day parent requires configuration',
    (t) async {
      await boot(t);
      FilledButton primary() => t.widget<FilledButton>(
        find.descendant(
          of: find.byKey(const ValueKey('home-primary-action')),
          matching: find.byType(FilledButton),
        ),
      );
      expect(find.text('自由训练'), findsOneWidget);
      expect(primary().onPressed, isNotNull);
      final empty = (await t.runAsync(() => plan('稍后配置', 0)))!;
      revision.changed();
      await settle(t);
      expect(find.text('尚未配置训练日'), findsOneWidget);
      expect(find.text('0 个训练日 · 0 个休息日'), findsOneWidget);
      expect(primary().onPressed, isNull);
      await t.runAsync(() async {
        expect(await getSetting(db, activeTrainingPlanKey), empty.id);
      });
      await tap(t, '切换计划');
      await tap(t, '自由训练');
      expect(primary().onPressed, isNotNull);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await settle(t);
    },
  );

  testWidgets(
    'a delayed parent or day selection cannot start the old selection',
    (t) async {
      final parents = (await t.runAsync(
        () async => [await plan('A', 2), await plan('B', 2)],
      ))!;
      final gated = _GatedExecutor(db);
      await boot(t, homeExecutor: gated);
      FilledButton primary() => t.widget<FilledButton>(
        find.descendant(
          of: find.byKey(const ValueKey('home-primary-action')),
          matching: find.byType(FilledButton),
        ),
      );
      await tap(t, '切换计划');
      var gate = Completer<void>();
      gated.nextTransaction = gate;
      await tap(t, 'B');
      expect(primary().onPressed, isNull);
      await t.tap(find.text('开始训练'));
      await t.runAsync(() async {
        expect(await db.all('SELECT id FROM session'), isEmpty);
      });
      gate.complete();
      await settle(t);
      expect(find.text('B 日1'), findsWidgets);
      await tap(t, '选择训练日');
      gate = Completer<void>();
      gated.nextTransaction = gate;
      await tap(t, 'B 日2');
      expect(primary().onPressed, isNull);
      await t.tap(find.text('开始训练'));
      await t.runAsync(() async {
        expect(await db.all('SELECT id FROM session'), isEmpty);
      });
      gate.complete();
      await settle(t);
      await tap(t, '开始训练');
      expect(find.text('record'), findsOneWidget);
      expect(active.session!.planId, parents.last.id);
      expect(active.session!.templateId, parents.last.days.last.id);
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await settle(t);
    },
  );

  testWidgets(
    'real shell keeps home alive while ending the old workout and starting its next day',
    (t) async {
      final parent = (await t.runAsync(() => plan('A', 2)))!;
      await t.runAsync(() => active.startNew(planId: parent.id));
      final oldId = active.session!.id;
      final gated = _GatedExecutor(db);
      await boot(t, homeExecutor: gated, realShell: true);
      final homeState = t.state(find.byType(WorkoutHomePage));
      await tap(t, '开始新训练');
      final gate = Completer<void>();
      gated.nextTransaction = gate;
      await tap(t, '结束它，开始新的');
      expect(
        identical(t.state(find.byType(WorkoutHomePage)), homeState),
        isTrue,
      );
      expect(active.session, isNull);
      gate.complete();
      await settle(t);
      expect(find.text('record'), findsOneWidget);
      expect(active.session!.id, isNot(oldId));
      expect(active.session!.templateId, parent.days.last.id);
      await t.runAsync(() async {
        final rows = await db.all<Map<String, Object?>>(
          'SELECT id,finished_at FROM session',
        );
        expect(rows, hasLength(2));
        expect(
          rows.singleWhere((row) => row['id'] == oldId)['finished_at'],
          isNotNull,
        );
        expect(rows.where((row) => row['finished_at'] == null), hasLength(1));
      });
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
      await settle(t);
    },
  );
}
