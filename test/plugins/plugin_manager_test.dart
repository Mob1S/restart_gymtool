import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/plugins/api/plugin_manifest.dart';
import 'package:gym_tracker/plugins/api/plugin_protocol.dart';
import 'package:gym_tracker/plugins/runtime/plugin_manager.dart';

import '../support/plugin_fakes.dart';

Matcher code(PluginErrorCode expected) =>
    isA<PluginException>().having((e) => e.code, 'code', expected);

Future<PluginManager> setup(FakePluginEnvironment env) async {
  env.add(fakePluginManifest('gym.training', requiredByHost: true));
  env.add(fakePluginManifest('community.example'));
  final manager = env.manager();
  await manager.initialize();
  return manager;
}

void main() {
  test('平台不支持和依赖循环明确报告，可选能力缺失仍启动', () async {
    final env = FakePluginEnvironment(
      preferences: {
        'community.platform': true,
        'community.first': true,
        'community.second': true,
        'community.optional': true,
      },
    );
    env.add(fakePluginManifest('community.platform', platforms: {'android'}));
    env.add(
      fakePluginManifest(
        'community.first',
        dependencies: [const PluginDependency(id: 'community.second')],
      ),
    );
    env.add(
      fakePluginManifest(
        'community.second',
        dependencies: [const PluginDependency(id: 'community.first')],
      ),
    );
    env.add(
      fakePluginManifest(
        'community.optional',
        optionalCapabilities: {'network.foodSearch'},
      ),
    );
    final manager = await setup(env);
    expect(
      manager.errorOf('community.platform')!.code,
      PluginErrorCode.unsupportedPlatform,
    );
    expect(
      manager.errorOf('community.first')!.code,
      PluginErrorCode.missingDependency,
    );
    expect(
      manager.errorOf('community.second')!.code,
      PluginErrorCode.missingDependency,
    );
    expect(manager.isEnabled('community.optional'), isTrue);
    expect(manager.isEnabled('gym.training'), isTrue);
    await manager.shutdown();
  });

  test('激活前使用definition支持版本校验，不兼容数据不构造运行实例', () async {
    final env = FakePluginEnvironment(preferences: {'community.example': true});
    env.validateData = (definition) async {
      final storedVersion = definition.manifest.id == 'community.example'
          ? 2
          : 1;
      if (!definition.supportedDataVersions.contains(storedVersion)) {
        throw const PluginException(PluginErrorCode.invalidData, '插件数据版本不兼容');
      }
    };
    final manager = await setup(env);
    expect(
      manager.errorOf('community.example')!.code,
      PluginErrorCode.invalidData,
    );
    expect(env.runtimes['community.example'], isNull);
    expect(env.scopes['community.example'], isNull);
    expect(manager.isEnabled('gym.training'), isTrue);
    await manager.shutdown();
  });

  test('默认仅基础能力，重复启用串行且只有一个运行实例', () async {
    final env = FakePluginEnvironment();
    final manager = await setup(env);
    expect(manager.isEnabled('gym.training'), isTrue);
    expect(env.runtimes['community.example'], isNull);
    await Future.wait([
      manager.setEnabled('community.example', true),
      manager.setEnabled('community.example', true),
    ]);
    expect(env.runtimes['community.example'], hasLength(1));
    expect(env.latest('community.example').activeSubscriptions, 1);
    await expectLater(
      manager.setEnabled('gym.training', false),
      throwsA(code(PluginErrorCode.permissionDenied)),
    );
    await manager.shutdown();
  });

  test('启用失败撤销实例，不影响基础训练且可以重试', () async {
    final env = FakePluginEnvironment();
    env.configure['community.example'] = (r) =>
        r.startError = StateError('failed');
    final manager = await setup(env);
    await expectLater(
      manager.setEnabled('community.example', true),
      throwsA(code(PluginErrorCode.internalError)),
    );
    expect(env.scopes['community.example']!.isActive, isFalse);
    expect(manager.stateOf('community.example'), PluginState.failed);
    expect(manager.isEnabled('gym.training'), isTrue);
    expect(env.preferences['community.example'], isNull);
    env.configure.clear();
    await manager.setEnabled('community.example', true);
    expect(manager.isEnabled('community.example'), isTrue);
    await manager.shutdown();
  });

  test('停用重开没有重复订阅，旧token不能复活', () async {
    final env = FakePluginEnvironment();
    final manager = await setup(env);
    await manager.setEnabled('community.example', true);
    final old = env.latest('community.example');
    final scope = env.scopes['community.example']!;
    await manager.setEnabled('community.example', false);
    await manager.setEnabled('community.example', true);
    expect(old.activeSubscriptions, 0);
    expect(scope.isActive, isFalse);
    expect(env.latest('community.example').activeSubscriptions, 1);
    expect(
      identical(scope.token, env.scopes['community.example']!.token),
      isFalse,
    );
    await manager.shutdown();
  });

  test('安全点拒绝丢弃未保存内容或中断任务且不写偏好', () async {
    final env = FakePluginEnvironment();
    final manager = await setup(env);
    await manager.setEnabled('community.example', true);
    final writes = env.preferenceWrites.length;
    for (final decision in [StopDecision.unsavedChanges, StopDecision.busy]) {
      env.latest('community.example').decision = decision;
      await expectLater(
        manager.setEnabled('community.example', false),
        throwsA(
          code(
            decision == StopDecision.busy
                ? PluginErrorCode.busy
                : PluginErrorCode.unsavedChanges,
          ),
        ),
      );
      expect(manager.isEnabled('community.example'), isTrue);
      expect(env.scopes['community.example']!.acceptsRequests, isTrue);
      expect(env.preferenceWrites.length, writes);
      expect(env.latest('community.example').stopCount, 0);
    }
    env.latest('community.example').decision = StopDecision.ready;
    await manager.shutdown();
  });

  test('关闭失败保持failed，重试确认关闭后才允许重新启用', () async {
    final env = FakePluginEnvironment();
    final manager = await setup(env);
    await manager.setEnabled('community.example', true);
    final runtime = env.latest('community.example')
      ..stopError = StateError('camera close failed');
    await expectLater(
      manager.setEnabled('community.example', false),
      throwsA(code(PluginErrorCode.internalError)),
    );
    expect(manager.stateOf('community.example'), PluginState.failed);
    expect(manager.isDesiredEnabled('community.example'), isTrue);
    expect(env.scopes['community.example']!.isActive, isFalse);
    runtime.stopError = null;
    await manager.setEnabled('community.example', true);
    expect(env.runtimes['community.example'], hasLength(2));
    await manager.shutdown();
  });

  test('启用落库失败回收实例，停用落库失败报告实际已关闭状态', () async {
    final env = FakePluginEnvironment();
    final manager = await setup(env);
    env.failSave = true;
    await expectLater(
      manager.setEnabled('community.example', true),
      throwsA(code(PluginErrorCode.storageFailure)),
    );
    expect(env.latest('community.example').activeSubscriptions, 0);
    expect(manager.stateOf('community.example'), PluginState.failed);
    env.failSave = false;
    await manager.setEnabled('community.example', true);
    env.failSave = true;
    await expectLater(
      manager.setEnabled('community.example', false),
      throwsA(code(PluginErrorCode.storageFailure)),
    );
    expect(manager.stateOf('community.example'), PluginState.disabled);
    expect(manager.isDesiredEnabled('community.example'), isTrue);
    env.failSave = false;
    await manager.setEnabled('community.example', false);
    expect(manager.isDesiredEnabled('community.example'), isFalse);
    await manager.shutdown();
  });

  test('启动、调用和停止超时返回timeout且撤销请求权限', () async {
    final env = FakePluginEnvironment(
      controlTimeout: const Duration(milliseconds: 5),
    );
    env.configure['community.example'] = (r) =>
        r.startCompleter = Completer<void>();
    final manager = await setup(env);
    await expectLater(
      manager.setEnabled('community.example', true),
      throwsA(code(PluginErrorCode.timeout)),
    );
    expect(env.scopes['community.example']!.isActive, isFalse);
    env.configure.clear();
    await manager.setEnabled('community.example', true);
    env.latest('community.example').invokeCompleter = Completer<JsonMap>();
    await expectLater(
      manager.invoke('community.example', 'test', {}),
      throwsA(code(PluginErrorCode.timeout)),
    );
    expect(env.scopes['community.example']!.acceptsRequests, isFalse);
    expect(manager.stateOf('community.example'), PluginState.failed);
    expect(env.latest('community.example').activeSubscriptions, 0);
    await manager.setEnabled('community.example', true);
    env.latest('community.example').stopCompleter = Completer<void>();
    await expectLater(
      manager.setEnabled('community.example', false),
      throwsA(code(PluginErrorCode.timeout)),
    );
    expect(manager.stateOf('community.example'), PluginState.failed);
    env.latest('community.example').stopCompleter!.complete();
    await manager.shutdown();
  });

  test('不兼容、缺依赖和重复标识独立失败，基础训练继续启动', () async {
    final env = FakePluginEnvironment(
      preferences: {
        'community.version': true,
        'community.dependent': true,
        'community.duplicate': true,
      },
    );
    env.add(fakePluginManifest('community.version', apiMin: 2, apiMax: 2));
    env.add(
      fakePluginManifest(
        'community.dependent',
        dependencies: [const PluginDependency(id: 'community.missing')],
      ),
    );
    env.add(fakePluginManifest('community.duplicate'));
    env.add(fakePluginManifest('community.duplicate'));
    final manager = await setup(env);
    expect(
      manager.errorOf('community.version')!.code,
      PluginErrorCode.unsupportedApi,
    );
    expect(
      manager.errorOf('community.dependent')!.code,
      PluginErrorCode.missingDependency,
    );
    expect(
      manager.errorOf('community.duplicate')!.code,
      PluginErrorCode.invalidData,
    );
    expect(manager.isEnabled('gym.training'), isTrue);
    await manager.shutdown();
  });

  test('没有必需能力授权时不构造运行实例', () async {
    final env = FakePluginEnvironment(preferences: {'community.camera': true})
      ..grantedCapabilities = {};
    env.add(
      fakePluginManifest(
        'community.camera',
        requiredCapabilities: {'camera.capture'},
      ),
    );
    final manager = await setup(env);
    expect(env.runtimes['community.camera'], isNull);
    expect(
      manager.errorOf('community.camera')!.code,
      PluginErrorCode.permissionDenied,
    );
    await manager.shutdown();
  });

  test('恢复协调先检查所有安全点，事务结束重新启动且不改本机偏好', () async {
    final env = FakePluginEnvironment();
    final manager = await setup(env);
    await manager.setEnabled('community.example', true);
    final before = Map.of(env.preferences);
    env.latest('community.example').decision = StopDecision.unsavedChanges;
    var runs = 0;
    await expectLater(
      manager.runWithPluginsPaused(() async {
        runs++;
      }),
      throwsA(code(PluginErrorCode.unsavedChanges)),
    );
    expect(runs, 0);
    expect(manager.isEnabled('gym.training'), isTrue);
    env.latest('community.example').decision = StopDecision.ready;
    await expectLater(
      manager.runWithPluginsPaused(() async {
        runs++;
        expect(manager.isEnabled('community.example'), isFalse);
        expect(manager.isEnabled('gym.training'), isTrue);
        expect(env.latest('gym.training').stopCount, 0);
        expect(env.scopes['gym.training']!.acceptsRequests, isFalse);
        throw StateError('transaction failed');
      }),
      throwsStateError,
    );
    expect(runs, 1);
    expect(manager.isEnabled('community.example'), isTrue);
    expect(manager.isEnabled('gym.training'), isTrue);
    expect(env.preferences, before);
    await manager.shutdown();
  });
}
