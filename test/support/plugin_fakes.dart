import 'dart:async';

import 'package:gym_tracker/plugins/api/plugin_manifest.dart';
import 'package:gym_tracker/plugins/api/plugin_runtime.dart';
import 'package:gym_tracker/plugins/host/plugin_host.dart';
import 'package:gym_tracker/plugins/runtime/plugin_catalog.dart';
import 'package:gym_tracker/plugins/runtime/plugin_manager.dart';
import 'package:gym_tracker/plugins/runtime/plugin_scope.dart';

PluginManifest fakePluginManifest(
  String id, {
  bool requiredByHost = false,
  Set<String> requiredCapabilities = const {},
  Set<String> optionalCapabilities = const {},
  Set<String> platforms = const {'web', 'android'},
  List<PluginDependency> dependencies = const [],
  int apiMin = 1,
  int apiMax = 1,
}) => PluginManifest(
  id: id,
  name: id,
  description: '测试插件',
  version: '1.0.0',
  platforms: platforms,
  requiredByHost: requiredByHost,
  requiredCapabilities: requiredCapabilities,
  optionalCapabilities: optionalCapabilities,
  dependencies: dependencies,
  apiMin: apiMin,
  apiMax: apiMax,
);

class FakePluginRuntime implements PluginRuntime {
  PluginHost? host;
  int startCount = 0;
  int stopCount = 0;
  int activeSubscriptions = 0;
  int pendingRequests = 0;
  Object? startError;
  Object? stopError;
  Completer<void>? startCompleter;
  Completer<void>? stopCompleter;
  Completer<JsonMap>? invokeCompleter;
  StopDecision decision = StopDecision.ready;
  final List<String> cancelledRequests = [];

  @override
  Future<void> start(PluginHost host) async {
    this.host = host;
    startCount++;
    if (startError != null) throw startError!;
    await startCompleter?.future;
    activeSubscriptions++;
  }

  @override
  Future<StopDecision> prepareStop() async => decision;

  @override
  Future<void> stop() async {
    stopCount++;
    if (stopError != null) throw stopError!;
    await stopCompleter?.future;
    activeSubscriptions = 0;
  }

  @override
  Future<void> cancel(String requestId) async {
    cancelledRequests.add(requestId);
  }

  @override
  Future<JsonMap> invoke(String method, JsonMap arguments) async {
    pendingRequests++;
    try {
      return await (invokeCompleter?.future ?? Future.value(arguments));
    } finally {
      pendingRequests--;
    }
  }
}

class FakePluginEnvironment {
  FakePluginEnvironment({
    Map<String, bool>? preferences,
    this.controlTimeout = const Duration(seconds: 10),
  }) : preferences = preferences ?? {};

  final Map<String, bool> preferences;
  final Duration controlTimeout;
  final Map<String, List<FakePluginRuntime>> runtimes = {};
  final Map<String, PluginScope> scopes = {};
  final Map<String, void Function(FakePluginRuntime)> configure = {};
  final List<(String, bool)> preferenceWrites = [];
  final List<PluginDefinition> definitions = [];
  bool failSave = false;
  Set<String>? grantedCapabilities;
  Future<void> Function(PluginDefinition definition)? validateData;

  void add(PluginManifest manifest) {
    definitions.add(
      PluginDefinition(
        manifest: manifest,
        createRuntime: () {
          final runtime = FakePluginRuntime();
          configure[manifest.id]?.call(runtime);
          runtimes.putIfAbsent(manifest.id, () => []).add(runtime);
          return runtime;
        },
      ),
    );
  }

  FakePluginRuntime latest(String id) => runtimes[id]!.last;

  PluginManager manager() => PluginManager(
    catalog: StaticPluginCatalog(definitions),
    platform: 'web',
    loadPreferences: () async => Map.of(preferences),
    savePreference: (id, enabled) async {
      if (failSave) throw StateError('storage failed');
      preferenceWrites.add((id, enabled));
      preferences[id] = enabled;
    },
    hostFactory: (manifest, scope) {
      scopes[manifest.id] = scope;
      return BoundPluginHost(
        scope: scope,
        grantedCapabilities:
            grantedCapabilities ?? manifest.requiredCapabilities,
      );
    },
    controlTimeout: controlTimeout,
    validateData: validateData,
  );
}
