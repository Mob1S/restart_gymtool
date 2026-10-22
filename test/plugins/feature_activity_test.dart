import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/plugins/api/plugin_runtime.dart';
import 'package:gym_tracker/plugins/host/plugin_host.dart';
import 'package:gym_tracker/plugins/runtime/feature_activity.dart';
import 'package:gym_tracker/plugins/runtime/plugin_scope.dart';

PluginHost _host() => BoundPluginHost(
  scope: PluginScope('community.example'),
  grantedCapabilities: {},
);

void main() {
  test('慢启动关闭先等待启动收尾，不在已关闭之后创建旧资源', () async {
    final activated = Completer<void>();
    var stopped = 0;
    final runtime = FeaturePluginRuntime(
      FeatureActivityRegistry(),
      onStart: () => activated.future,
      onStop: () async {
        stopped++;
      },
    );
    final starting = runtime.start(_host());
    await Future<void>.delayed(Duration.zero);
    final stopping = runtime.stop();
    await Future<void>.delayed(Duration.zero);
    expect(stopped, 0);
    activated.complete();
    await starting;
    await stopping;
    expect(stopped, 1);
    expect(() => runtime.host, throwsStateError);
  });

  test('停止超时后重复调用共享旧停止，重新启动等待旧回调完成', () async {
    final closed = Completer<void>();
    var stops = 0;
    var starts = 0;
    final runtime = FeaturePluginRuntime(
      FeatureActivityRegistry(),
      onStart: () async {
        starts++;
      },
      onStop: () {
        stops++;
        return closed.future;
      },
    );
    await runtime.start(_host());
    final stop = runtime.stop();
    await expectLater(
      stop.timeout(const Duration(milliseconds: 5)),
      throwsA(isA<TimeoutException>()),
    );
    expect(identical(runtime.stop(), stop), isTrue);
    final replacement = _host();
    final restarting = runtime.start(replacement);
    await Future<void>.delayed(Duration.zero);
    expect(starts, 1);
    expect(stops, 1);
    closed.complete();
    await stop;
    await restarting;
    expect(identical(runtime.host, replacement), isTrue);
    expect(starts, 2);
    await runtime.stop();
    expect(stops, 2);
  });

  test('启动和关闭失败可清理重试，成功关闭幂等', () async {
    var failStart = true;
    var failStop = true;
    var stops = 0;
    final runtime = FeaturePluginRuntime(
      FeatureActivityRegistry(),
      onStart: () async {
        if (failStart) throw StateError('start');
      },
      onStop: () async {
        stops++;
        if (failStop) throw StateError('stop');
      },
    );
    await expectLater(runtime.start(_host()), throwsStateError);
    await expectLater(runtime.stop(), throwsStateError);
    failStop = false;
    await runtime.stop();
    await runtime.stop();
    expect(stops, 2);
    failStart = false;
    final current = _host();
    await runtime.start(current);
    expect(identical(runtime.host, current), isTrue);
    await runtime.stop();
  });

  test('一个页面关闭失败仍然等待其他页面清理', () async {
    final registry = FeatureActivityRegistry();
    final closed = <int>[];
    registry.register(() => StopDecision.ready, () async {
      closed.add(1);
      throw StateError('failed');
    });
    registry.register(() => StopDecision.ready, () async {
      closed.add(2);
    });
    await expectLater(registry.close(), throwsStateError);
    expect(closed, [1, 2]);
  });

  test('页面关闭失败仍尝试平台关闭，失败状态可重试', () async {
    final registry = FeatureActivityRegistry();
    var fail = true;
    var platformStops = 0;
    registry.register(() => StopDecision.ready, () async {
      if (fail) throw StateError('page');
    });
    final runtime = FeaturePluginRuntime(
      registry,
      onStop: () async {
        platformStops++;
      },
    );
    await runtime.start(_host());
    await expectLater(runtime.stop(), throwsStateError);
    expect(platformStops, 1);
    fail = false;
    await runtime.stop();
    expect(platformStops, 2);
    expect(() => runtime.host, throwsStateError);
  });
}
