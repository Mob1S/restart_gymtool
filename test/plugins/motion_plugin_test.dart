import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/plugins/api/feature_clients.dart';
import 'package:gym_tracker/plugins/api/plugin_runtime.dart';
import 'package:gym_tracker/plugins/bundled/motion_plugin.dart';
import 'package:gym_tracker/plugins/host/legacy_feature_services.dart';
import 'package:gym_tracker/plugins/host/plugin_host.dart';
import 'package:gym_tracker/plugins/runtime/feature_activity.dart';
import 'package:gym_tracker/plugins/runtime/plugin_catalog.dart';
import 'package:gym_tracker/plugins/runtime/plugin_manager.dart';

void main() {
  late FfiExecutor db;
  late FeaturePluginRuntime runtime;
  late PluginManager manager;
  late int activations;
  late int deactivations;
  Object? closeFailure;
  setUp(() async {
    db = await FfiExecutor.openMigrated();
    activations = 0;
    deactivations = 0;
    closeFailure = null;
    runtime = FeaturePluginRuntime(
      FeatureActivityRegistry(),
      onStart: () async {
        activations++;
      },
      onStop: () async {
        deactivations++;
        if (closeFailure != null) throw closeFailure!;
      },
    );
    final services = LegacyFeatureServices(db);
    const methods = [
      'motion.projects.list',
      'motion.projects.load',
      'motion.projects.forSet',
      'motion.projects.completedSets',
      'motion.projects.save',
      'motion.projects.delete',
      'motion.projects.resultFiles',
      'training.set.read',
    ];
    manager = PluginManager(
      catalog: StaticPluginCatalog([
        PluginDefinition(
          manifest: motionManifest,
          createRuntime: () => runtime,
        ),
      ]),
      platform: 'web',
      loadPreferences: () async => {},
      savePreference: (_, _) async {},
      hostFactory: (manifest, scope) => BoundPluginHost(
        scope: scope,
        grantedCapabilities: manifest.requiredCapabilities,
        methods: {
          for (final method in methods)
            method: HostMethod(
              capability: method == 'training.set.read'
                  ? 'training.set.read'
                  : 'motion.projects',
              handle: (args) => services.request(
                method,
                args,
                ensureActive: scope.ensureActive,
              ),
            ),
        },
      ),
    );
    await manager.initialize();
  });
  tearDown(() async {
    closeFailure = null;
    await manager.shutdown();
    manager.dispose();
    await db.close();
  });

  test('停用不创建媒体，重新启用保留项目且旧实例无法覆盖', () async {
    expect(activations, 0);
    await manager.setEnabled('gym.motion', true);
    final old = MotionProjectsClient(runtime.host);
    await old.save(
      id: 'project',
      mode: 'import',
      folder: 'managed-video',
      payload: {'version': 3, 'result': 'managed-result', 'reps': []},
    );
    final original = await old.load('project');
    expect(await old.trainingSet('deleted-set'), isNull);
    await manager.setEnabled('gym.motion', false);
    await manager.setEnabled('gym.motion', true);
    final current = MotionProjectsClient(runtime.host);
    expect(await current.load('project'), original);
    await expectLater(
      old.save(
        id: 'project',
        mode: 'import',
        folder: 'stale',
        payload: {'version': 3},
      ),
      throwsA(
        isA<PluginException>().having(
          (e) => e.code,
          'code',
          PluginErrorCode.pluginDisabled,
        ),
      ),
    );
    expect(await current.load('project'), original);
    expect(await current.resultFiles(), {'managed-video': 'managed-result'});
    expect(activations, 2);
    expect(deactivations, 1);
  });

  test('忙碌与未保存活动拒绝停用，ready后等待closeSession完成', () async {
    await manager.setEnabled('gym.motion', true);
    var decision = StopDecision.busy;
    final closed = Completer<void>();
    final unregister = runtime.activities.register(
      () => decision,
      () => closed.future,
    );
    for (final value in [StopDecision.busy, StopDecision.unsavedChanges]) {
      decision = value;
      await expectLater(
        manager.setEnabled('gym.motion', false),
        throwsA(isA<PluginException>()),
      );
      expect(manager.isEnabled('gym.motion'), isTrue);
      expect(deactivations, 0);
    }
    decision = StopDecision.ready;
    var finished = false;
    final stopping = manager.setEnabled('gym.motion', false).then((_) {
      finished = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(manager.stateOf('gym.motion'), PluginState.stopping);
    expect(finished, isFalse);
    expect(deactivations, 0);
    closed.complete();
    await stopping;
    expect(deactivations, 1);
    expect(manager.stateOf('gym.motion'), PluginState.disabled);
    unregister();
    unregister();
  });

  test('平台资源关闭失败显示failed并可在清理成功后重新激活', () async {
    await manager.setEnabled('gym.motion', true);
    closeFailure = StateError('platform close failed');
    await expectLater(
      manager.setEnabled('gym.motion', false),
      throwsA(
        isA<PluginException>().having(
          (e) => e.code,
          'code',
          PluginErrorCode.internalError,
        ),
      ),
    );
    expect(manager.stateOf('gym.motion'), PluginState.failed);
    closeFailure = null;
    await manager.setEnabled('gym.motion', true);
    expect(manager.isEnabled('gym.motion'), isTrue);
    expect(deactivations, 2);
    expect(activations, 2);
  });
}
