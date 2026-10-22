import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:gym_tracker/app/providers.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/repositories/plugin_state_repo.dart';
import 'package:gym_tracker/plugins/runtime/plugin_manager.dart';
import 'package:gym_tracker/state/active_session_controller.dart';

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
  Future<BuildContext> boot(WidgetTester tester) async {
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
    expect(find.byType(NavigationBar), findsOneWidget);
    return tester.element(find.byType(NavigationBar));
  }

  testWidgets(
    'fresh install has three destinations; toggling preserves active training',
    (tester) async {
      final context = await boot(tester);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).destinations,
        hasLength(3),
      );
      final active = context.read<ActiveSessionController>();
      await tester.runAsync(() => active.startNew(freeTraining: true));
      final sessionId = active.session!.id;
      final manager = context.read<PluginManager>();
      await tester.runAsync(() => manager.setEnabled('gym.calories', true));
      await settle(tester);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).destinations,
        hasLength(4),
      );
      expect(context.read<ActiveSessionController>(), same(active));
      expect(active.session!.id, sessionId);
      await tester.runAsync(() => manager.setEnabled('gym.calories', false));
      await settle(tester);
      expect(
        tester.widget<NavigationBar>(find.byType(NavigationBar)).destinations,
        hasLength(3),
      );
      expect(active.session!.id, sessionId);
      expect(
        (await tester.runAsync(
          () => loadPluginPreferences(db),
        ))!['gym.calories'],
        false,
      );
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    },
  );
  testWidgets('plugin settings show required training and persistent toggles', (
    tester,
  ) async {
    final context = await boot(tester);
    GoRouter.of(context).go('/settings/plugins');
    await settle(tester);
    expect(find.text('插件管理'), findsOneWidget);
    expect(find.text('必需能力 · 始终启用'), findsOneWidget);
    final switches = find.byType(SwitchListTile);
    expect(tester.widget<SwitchListTile>(switches.first).onChanged, isNull);
    await tester.tap(switches.at(1));
    await settle(tester);
    expect(
      (await tester.runAsync(() => loadPluginPreferences(db)))!['gym.calories'],
      true,
    );
    await tester.pumpWidget(const SizedBox());
    await settle(tester);
  });
}
