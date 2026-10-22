import 'dart:async';

import 'package:gym_tracker/plugins/api/plugin_manifest.dart';
import 'package:gym_tracker/plugins/api/plugin_runtime.dart';

/// A test-only plugin: no SQL, feature controller, platform or Flutter imports.
class ExamplePlugin implements PluginRuntime {
  ExamplePlugin(this.id);
  final String id;
  PluginHost? _host;
  StreamSubscription<JsonMap>? _changes;
  int receivedChanges = 0;

  PluginManifest get manifest => PluginManifest(
    id: id,
    name: '示例设置',
    description: '展示公共私有存储与数据事件。',
    version: '1.0.0',
    platforms: {'web', 'android'},
    requiredCapabilities: {'storage.private.read', 'storage.private.write'},
  );

  JsonMap get settingsContribution => {
    'id': '$id.preferences',
    'label': '示例设置',
    'pageId': 'preferences',
  };

  @override
  Future<void> start(PluginHost host) async {
    _host = host;
    final existing = await host.request('storage.private.read', {
      'key': 'preferences',
    });
    if (existing['value'] == null) {
      await host.request('storage.private.write', {
        'dataVersion': 1,
        'operations': [
          {
            'key': 'preferences',
            'value': {'displayUnit': 'kg'},
          },
        ],
      });
    }
    _changes = host.subscribe('storage.private.changed').listen((_) {
      receivedChanges++;
    });
  }

  @override
  Future<JsonMap> invoke(String method, JsonMap arguments) async {
    final host = _host;
    if (host == null) {
      throw const PluginException(PluginErrorCode.pluginDisabled, '示例尚未启用');
    }
    if (method == 'preferences') {
      return host.request('storage.private.read', {'key': 'preferences'});
    }
    throw const PluginException(PluginErrorCode.invalidData, '未知示例请求');
  }

  @override
  Future<void> cancel(String requestId) async {}
  @override
  Future<StopDecision> prepareStop() async => StopDecision.ready;
  @override
  Future<void> stop() async {
    await _changes?.cancel();
    _changes = null;
    _host = null;
  }
}
