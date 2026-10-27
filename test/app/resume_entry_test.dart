import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gym_tracker/app/providers.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/sql_executor.dart';
import 'package:gym_tracker/data/repositories/exercise_repo.dart';
import 'package:gym_tracker/data/repositories/session_repo.dart';
import 'package:gym_tracker/data/repositories/set_repo.dart';
import 'package:gym_tracker/features/workout/record_page.dart';
import 'package:gym_tracker/plugins/runtime/plugin_manager.dart';
import 'package:gym_tracker/state/active_session_controller.dart';
import 'package:provider/provider.dart';
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

class _BootReads implements SqlExecutor {
  final SqlExecutor inner;
  bool failOnce = false;
  bool failAll = false;
  Completer<void>? gate;
  _BootReads(this.inner);
  @override
  Future<T?> first<T>(String sql, [List<Object?>? params]) async {
    if (sql.contains('WHERE finished_at IS NULL')) {
      if (failOnce || failAll) {
        failOnce = false;
        throw StateError('injected startup read failure');
      }
      if (gate != null) await gate!.future;
    }
    return inner.first<T>(sql, params);
  }

  @override
  Future<List<T>> all<T>(String sql, [List<Object?>? params]) =>
      inner.all<T>(sql, params);
  @override
  Future<void> run(String sql, [List<Object?>? params]) =>
      inner.run(sql, params);
  @override
  Future<T> transaction<T>(Future<T> Function(SqlExecutor tx) action) =>
      inner.transaction(action);
}

void main() {
  late FfiExecutor db;
  late String sid;
  late String firstSetId;
  setUp(() async {
    wakelockPlusPlatformInstance = _Wakelock();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('gym_tracker/review'),
      (_) async => <String, Object?>{},
    );
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        const MethodChannel('gym_tracker/review'),
        null,
      ),
    );
    db = await FfiExecutor.openMigrated();
    final a = await createCustomExercise(db, name: '卧推');
    final b = await createCustomExercise(db, name: '划船');
    sid = (await createSession(db, name: '离线训练')).id;
    final first = await addExerciseToSession(db, sid, a.id);
    final second = await addExerciseToSession(db, sid, b.id);
    firstSetId = (await addSet(db, first.id, 60, 8)).id;
    final now = DateTime.now().millisecondsSinceEpoch;
    await completeSet(db, firstSetId, now);
    await startRest(db, firstSetId, now);
    await addSet(db, first.id, 60, 8);
    await addSet(db, second.id, 40, 10);
  });
  tearDown(() async => db.close());

  Future<BuildContext> boot(
    WidgetTester tester, {
    SqlExecutor? executor,
  }) async {
    tester.platformDispatcher.defaultRouteNameTestValue = '/history';
    addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
    await tester.pumpWidget(
      AppBootstrap(
        openDatabase: () async => executor ?? db,
        backupFiles: MemoryBackupFiles(),
        pluginPlatform: 'web',
      ),
    );
    for (
      var i = 0;
      i < 10 && find.byType(NavigationBar).evaluate().isEmpty;
      i++
    ) {
      await settle(tester);
    }
    expect(find.byType(NavigationBar), findsOneWidget);
    return tester.element(find.byType(NavigationBar));
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  }

  testWidgets(
    'direct history boot restores once; real recorder roundtrips preserve focus and rest',
    (tester) async {
      final context = await boot(tester);
      final router = GoRouter.of(context);
      expect(router.state.uri.path, '/history');
      final active = context.read<ActiveSessionController>();
      expect(active.session!.id, sid);
      final rest = active.exercises.first.sets.first.restStartedAt;
      await tester.runAsync(() => active.setCurrentIndex(1));
      await tester.pump();
      for (final route in ['/history', '/progress']) {
        router.go(route);
        await settle(tester);
        await tester.tap(find.byKey(const ValueKey('active-workout-resume')));
        await settle(tester);
        expect(find.byType(RecordPage), findsOneWidget);
        expect(active.currentIndex, 1);
        expect(active.currentExercise!.exerciseName, '划船');
        expect(active.exercises.first.sets.first.restStartedAt, rest);
        expect(active.session!.id, sid);
      }
      expect(
        (await tester.runAsync(() => db.all('SELECT id FROM session')))!,
        hasLength(1),
      );
      await unmount(tester);
    },
  );

  testWidgets(
    'three and five destination layouts keep the resume entry; finishing removes it',
    (tester) async {
      final context = await boot(tester);
      final manager = context.read<PluginManager>();
      final active = context.read<ActiveSessionController>();
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).destinations,
        hasLength(3),
      );
      expect(
        find.byKey(const ValueKey('active-workout-resume')),
        findsOneWidget,
      );
      await tester.runAsync(() => manager.setEnabled('gym.calories', true));
      await tester.runAsync(() => manager.setEnabled('gym.motion', true));
      await settle(tester);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).destinations,
        hasLength(5),
      );
      expect(
        find.byKey(const ValueKey('active-workout-resume')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.runAsync(active.endWorkout);
      await settle(tester);
      expect(find.byKey(const ValueKey('active-workout-resume')), findsNothing);
      await unmount(tester);
    },
  );

  testWidgets(
    'startup read failure leaves the app usable and retries without a new session',
    (tester) async {
      final reads = _BootReads(db)..failOnce = true;
      final context = await boot(tester, executor: reads);
      expect(find.text('重试读取训练'), findsOneWidget);
      expect(find.textContaining('数据库打开失败'), findsNothing);
      expect(context.read<ActiveSessionController>().session, isNull);
      await tester.tap(find.text('重试读取训练'));
      await settle(tester);
      expect(find.text('重试读取训练'), findsNothing);
      expect(
        find.byKey(const ValueKey('active-workout-resume')),
        findsOneWidget,
      );
      expect(context.read<ActiveSessionController>().session!.id, sid);
      expect(
        (await tester.runAsync(() => db.all('SELECT id FROM session')))!,
        hasLength(1),
      );
      await unmount(tester);
    },
  );

  testWidgets('pending startup read shows loading on a non-home deep link', (
    tester,
  ) async {
    final gate = Completer<void>();
    final reads = _BootReads(db)..gate = gate;
    await boot(tester, executor: reads);
    expect(find.text('正在读取训练…'), findsOneWidget);
    expect(find.byKey(const ValueKey('active-workout-resume')), findsNothing);
    gate.complete();
    await settle(tester);
    expect(find.byKey(const ValueKey('active-workout-resume')), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('recorder retry initializes values before completing a group', (
    tester,
  ) async {
    await tester.runAsync(
      () => db.run('UPDATE set_entry SET rest_started_at = NULL WHERE id = ?', [
        firstSetId,
      ]),
    );
    final reads = _BootReads(db)..failAll = true;
    tester.platformDispatcher.defaultRouteNameTestValue = '/session/$sid';
    addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
    await tester.pumpWidget(
      AppBootstrap(
        openDatabase: () async => reads,
        backupFiles: MemoryBackupFiles(),
        pluginPlatform: 'web',
      ),
    );
    await settle(tester);
    expect(find.text('重试读取训练'), findsOneWidget);
    reads.failAll = false;
    await tester.tap(find.text('重试读取训练'));
    await settle(tester);
    expect(find.text('重试读取训练'), findsNothing);
    await tester.ensureVisible(find.textContaining('完成这组'));
    await tester.tap(find.textContaining('完成这组'));
    await settle(tester);
    final result = await tester.runAsync(
      () => db.first<Map<String, Object?>>(
        'SELECT COUNT(*) AS n FROM set_entry WHERE is_completed = 1',
      ),
    );
    expect(
      result!['n'],
      2,
      reason:
          'retry must initialize actual weight/reps, not just render defaults',
    );
    expect(find.text('组间休息'), findsOneWidget);
    await unmount(tester);
  });
}
