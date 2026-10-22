import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/repositories/plugin_document_repo.dart';
import 'package:gym_tracker/plugins/flutter/plugin_ui_adapter.dart';
import 'package:gym_tracker/plugins/host/plugin_host.dart';
import 'package:gym_tracker/plugins/host/scoped_plugin_store.dart';
import 'package:gym_tracker/plugins/runtime/plugin_catalog.dart';
import 'package:gym_tracker/plugins/runtime/plugin_manager.dart';

import 'example_plugin.dart';

void main() {
  for (final id in ['community.example', 'another.author']) {
    test('任意目录插件 $id 可使用同一宿主组合与设置适配入口', () async {
      final exec = await FfiExecutor.openMigrated();
      addTearDown(exec.close);
      final repository = PluginDocumentRepo(exec);
      final events = StreamController<Map<String, Object?>>.broadcast();
      addTearDown(events.close);
      final instances = <ExamplePlugin>[];
      final example = ExamplePlugin(id);
      final manager = PluginManager(
        catalog: StaticPluginCatalog([
          PluginDefinition(
            manifest: example.manifest,
            createRuntime: () {
              final instance = ExamplePlugin(id);
              instances.add(instance);
              return instance;
            },
          ),
        ]),
        platform: 'web',
        loadPreferences: () async => {id: true},
        savePreference: (_, _) async {},
        hostFactory: (manifest, scope) => BoundPluginHost(
          scope: scope,
          grantedCapabilities: manifest.requiredCapabilities,
          methods: ScopedPluginStore(
            repository: repository,
            scope: scope,
          ).methods,
          topics: {
            'storage.private.changed': HostTopic(
              capability: 'storage.private.read',
              events: events.stream,
            ),
          },
        ),
      );
      await manager.initialize();
      expect(manager.isEnabled(id), isTrue);
      expect(await manager.invoke(id, 'preferences', {}), {
        'value': {'displayUnit': 'kg'},
      });
      final contribution = example.settingsContribution;
      final ui = PluginUiRegistry([
        PluginUiAdapter(
          pluginId: id,
          settingsSections: [
            PluginSettingsSection(
              label: contribution['label'] as String,
              route: '/settings/${contribution['pageId']}',
            ),
          ],
          routes: [
            GoRoute(
              path: '/settings/${contribution['pageId']}',
              builder: (_, _) => Text(contribution['label'] as String),
            ),
          ],
        ),
      ]);
      expect(ui.adapters.single.routes, hasLength(1));
      expect(ui.settingsSections(manager).single.label, '示例设置');
      events.add({'type': 'changed'});
      await Future<void>.delayed(Duration.zero);
      expect(instances.single.receivedChanges, 1);
      await manager.setEnabled(id, false);
      expect(ui.settingsSections(manager), isEmpty);
      events.add({'type': 'old'});
      await Future<void>.delayed(Duration.zero);
      expect(instances.first.receivedChanges, 1);
      expect(await repository.read(id, 'preferences'), {'displayUnit': 'kg'});
      await manager.setEnabled(id, true);
      events.add({'type': 'new'});
      await Future<void>.delayed(Duration.zero);
      expect(instances.last.receivedChanges, 1);
      expect(instances.first.receivedChanges, 1);
      await manager.shutdown();
      manager.dispose();
    });
  }
}
