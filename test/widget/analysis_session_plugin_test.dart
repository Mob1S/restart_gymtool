import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/sql_executor.dart';
import 'package:gym_tracker/features/analysis/analysis_session_page.dart';
import 'package:gym_tracker/plugins/flutter/plugin_ui_adapter.dart';

import '../support/async_ui.dart';

class _PendingProject implements SqlExecutor {
  final result = Completer<Map<String, Object?>?>();
  @override
  Future<T?> first<T>(String sql, [List<Object?>? params]) async =>
      await result.future as T?;
  @override
  Future<List<T>> all<T>(String sql, [List<Object?>? params]) =>
      throw UnimplementedError();
  @override
  Future<void> run(String sql, [List<Object?>? params]) =>
      throw UnimplementedError();
  @override
  Future<T> transaction<T>(Future<T> Function(SqlExecutor tx) action) =>
      throw UnimplementedError();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'analysis route registers its own exit after inherited context is ready',
    (tester) async {
      final db = (await tester.runAsync(FfiExecutor.openMigrated))!;
      addTearDown(db.close);
      var closes = 0;
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('gym_tracker/review_progress'),
        (_) async => null,
      );
      messenger.setMockMethodCallHandler(
        const MethodChannel('gym_tracker/review'),
        (call) async {
          if (call.method == 'close') closes++;
          return <String, Object?>{};
        },
      );
      addTearDown(() {
        messenger.setMockMethodCallHandler(
          const MethodChannel('gym_tracker/review_progress'),
          null,
        );
        messenger.setMockMethodCallHandler(
          const MethodChannel('gym_tracker/review'),
          null,
        );
      });
      final exits = PluginExitRegistry();
      final router = GoRouter(
        initialLocation: '/analysis/import',
        routes: [
          GoRoute(
            path: '/',
            builder: (_, _) => const Scaffold(body: Text('training')),
          ),
          GoRoute(
            path: '/analysis/import',
            builder: (_, _) => const AnalysisSessionPage(),
            onExit: (_, state) => exits.leave(state.uri.path),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            Provider<SqlExecutor>.value(value: db),
            Provider<PluginExitRegistry>.value(value: exits),
          ],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('视频分析'), findsOneWidget);
      router.go('/');
      await pumpUntil(
        tester,
        () => find.text('training').evaluate().isNotEmpty,
        description: 'completed analysis exit',
      );
      expect(find.text('training'), findsOneWidget);
      expect(closes, 1);
      await exits.leave('/analysis/import');
      expect(closes, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'a failed project lookup after disposal cannot revive the editor',
    (tester) async {
      final pending = _PendingProject();
      await tester.pumpWidget(
        Provider<SqlExecutor>.value(
          value: pending,
          child: const MaterialApp(
            home: AnalysisSessionPage(projectId: 'pending'),
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      pending.result.completeError(StateError('private/native/path'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(AnalysisSessionPage), findsNothing);
    },
  );
}
