import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:gym_tracker/app/providers.dart';
import 'package:gym_tracker/app/router.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/plugins/runtime/plugin_manager.dart';

import '../support/backup_fakes.dart';
import '../widget/backup_section_test.dart' show settle;

void main() {
  testWidgets(
    'cold launch keeps its guarded target through asynchronous bootstrap',
    (tester) async {
      final dispatcher = tester.binding.platformDispatcher;
      dispatcher.defaultRouteNameTestValue = '/calories';
      addTearDown(dispatcher.clearDefaultRouteNameTestValue);
      final db = (await tester.runAsync(FfiExecutor.openMigrated))!;
      addTearDown(db.close);
      await tester.pumpWidget(
        AppBootstrap(
          openDatabase: () async => db,
          backupFiles: MemoryBackupFiles(),
          pluginPlatform: 'web',
        ),
      );
      for (var i = 0; i < 20 && find.text('启用并继续').evaluate().isEmpty; i++) {
        await settle(tester);
      }
      expect(find.text('此功能尚未启用。启用后可继续，已有数据会保留。'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final context = tester.element(find.text('启用并继续'));
      expect(
        GoRouter.of(context)
            .routeInformationProvider
            .value
            .uri
            .queryParameters['from'],
        '/calories',
      );
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
      dispatcher.clearDefaultRouteNameTestValue();
    },
  );
  test('continuation destinations are validated before navigation', () {
    expect(
      validPluginDestination(
        'gym.motion',
        '/analysis/import?motion=bench_press',
      ),
      true,
    );
    expect(validPluginDestination('gym.motion', '/review/set-1'), true);
    for (final value in [
      'https://evil.test/analysis',
      '//evil.test/analysis',
      '/settings',
      '/analysis/unknown',
      '/analysis?redirect=https://evil.test',
    ]) {
      expect(validPluginDestination('gym.motion', value), false, reason: value);
    }
  });
  testWidgets('disabled deep links explain and continue only after enable', (
    tester,
  ) async {
    final db = (await tester.runAsync(FfiExecutor.openMigrated))!;
    addTearDown(db.close);
    await tester.pumpWidget(
      AppBootstrap(
        openDatabase: () async => db,
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
    final context = tester.element(find.byType(NavigationBar));
    final router = GoRouter.of(context);
    final manager = context.read<PluginManager>();
    router.go('/calories');
    await settle(tester);
    expect(find.text('此功能尚未启用。启用后可继续，已有数据会保留。'), findsOneWidget);
    expect(find.text('已记录饮料热量'), findsNothing);
    await tester.tap(find.text('启用并继续'));
    await settle(tester);
    expect(manager.isEnabled('gym.calories'), true);
    expect(router.routeInformationProvider.value.uri.path, '/calories');
    await tester.runAsync(() => manager.setEnabled('gym.calories', false));
    await settle(tester);
    expect(router.routeInformationProvider.value.uri.path, '/');
    router.go('/review/set-1');
    await settle(tester);
    expect(find.text('此功能尚未启用。启用后可继续，已有数据会保留。'), findsOneWidget);
    expect(manager.isEnabled('gym.motion'), false);
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });
}
