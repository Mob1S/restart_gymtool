import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/files/beverage_ocr_native.dart';
import 'package:gym_tracker/data/files/beverage_http_native.dart';
import 'package:gym_tracker/data/files/motion_bridge_native.dart';
import 'package:gym_tracker/plugins/api/plugin_runtime.dart';
import 'package:gym_tracker/plugins/flutter/plugin_media_adapter.dart';
import 'package:gym_tracker/plugins/host/plugin_host.dart';
import 'package:gym_tracker/plugins/runtime/plugin_scope.dart';

void main() {
  test(
    'leaving a native search closes only that session HTTP client',
    () async {
      final first = _PendingHttpClient(), second = _PendingHttpClient();
      var next = 0;
      activateBeverageHttp();
      await HttpOverrides.runZoned(() async {
        final a = beverageHttpGet(
          Uri.https('example.test', '/a'),
          sessionId: 'a',
        );
        final b = beverageHttpGet(
          Uri.https('example.test', '/b'),
          sessionId: 'b',
        );
        final aError = expectLater(a, throwsA(isA<HttpException>()));
        final bError = expectLater(b, throwsA(isA<HttpException>()));
        await cancelBeverageHttpSession('a');
        await aError;
        expect(first.closed, true);
        expect(second.closed, false);
        await cancelBeverageHttpSession('b');
        await bError;
        expect(second.closed, true);
      }, createHttpClient: (_) => next++ == 0 ? first : second);
    },
  );
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(
      const MethodChannel('gym_tracker/review'),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('gym_tracker/beverage_ocr'),
      null,
    );
    messenger.setMockMethodCallHandler(
      const MethodChannel('gym_tracker/review_progress'),
      null,
    );
  });

  test('motion deactivate waits for the platform acknowledgement', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final released = Completer<void>();
    final methods = <String>[];
    messenger.setMockMethodCallHandler(
      const MethodChannel('gym_tracker/review'),
      (call) async {
        methods.add(call.method);
        if (call.method == 'deactivate') await released.future;
        return null;
      },
    );
    final bridge = MotionBridge();
    await bridge.activate();
    var stopped = false;
    final stopping = bridge.deactivate().then((_) => stopped = true);
    await Future<void>.delayed(Duration.zero);
    expect(methods, ['activate', 'deactivate']);
    expect(stopped, isFalse);
    released.complete();
    await stopping;
    expect(stopped, isTrue);
    await bridge.activate();
    expect(methods.last, 'activate');
  });

  test('OCR deactivate waits for cancelled recognizer resources', () async {
    final released = Completer<void>();
    messenger.setMockMethodCallHandler(
      const MethodChannel('gym_tracker/beverage_ocr'),
      (call) async {
        expect(call.method, 'cancel');
        await released.future;
        return null;
      },
    );
    var stopped = false;
    final stopping = BeverageOcr().deactivate().then((_) => stopped = true);
    await Future<void>.delayed(Duration.zero);
    expect(stopped, isFalse);
    released.complete();
    await stopping;
    expect(stopped, isTrue);
  });

  test('revoked media cleanup cannot close a replacement activation', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final methods = <String>[];
    messenger.setMockMethodCallHandler(
      const MethodChannel('gym_tracker/review'),
      (call) async {
        methods.add(call.method);
        return null;
      },
    );
    await MotionBridge().activate();
    final scope = PluginScope('gym.motion');
    final scoped = ScopedMotionBridge(
      BoundPluginHost(
        scope: scope,
        grantedCapabilities: {'media.pick', 'camera.capture'},
      ),
    );
    scope.revoke();
    await scoped.call(
      'close',
    ); // Registered teardown still runs after revocation.
    expect(methods, ['activate', 'close']);
    await MotionBridge().activate();
    await scoped.call('close');
    await scoped.call('cancel');
    await scoped.call('release', {'folder': 'old'});
    expect(methods, ['activate', 'close', 'activate']);
    await expectLater(scoped.call('frame'), throwsA(isA<PluginException>()));
    await expectLater(scoped.activate(), throwsA(isA<PluginException>()));
    await expectLater(scoped.deactivate(), throwsA(isA<PluginException>()));
  });

  test('late scoped event subscriptions never reach the platform', () async {
    var listens = 0;
    messenger.setMockMethodCallHandler(
      const MethodChannel('gym_tracker/review_progress'),
      (call) async {
        listens++;
        return null;
      },
    );
    final scope = PluginScope('gym.motion');
    final scoped = ScopedMotionBridge(
      BoundPluginHost(scope: scope, grantedCapabilities: {'media.pick'}),
    );
    final stream = scoped.events;
    scope.revoke();
    await expectLater(stream, emitsError(isA<PluginException>()));
    expect(listens, 0);
    expect(() => scoped.events, throwsA(isA<PluginException>()));
  });

  test('old OCR cleanup cannot cancel a replacement activation', () async {
    var cancels = 0;
    messenger.setMockMethodCallHandler(
      const MethodChannel('gym_tracker/beverage_ocr'),
      (call) async {
        cancels++;
        return null;
      },
    );
    await BeverageOcr().activate();
    final scoped = ScopedBeverageOcr(
      BoundPluginHost(
        scope: PluginScope('gym.calories'),
        grantedCapabilities: {'media.pick'},
      ),
    );
    await BeverageOcr().activate();
    await scoped.cancel();
    expect(cancels, 0);
    await expectLater(
      scoped.scan(camera: false),
      throwsA(isA<PluginException>()),
    );
    await expectLater(scoped.deactivate(), throwsA(isA<PluginException>()));
  });
}

class _PendingHttpClient implements HttpClient {
  final _request = Completer<HttpClientRequest>();
  bool closed = false;
  @override
  set userAgent(String? value) {}
  @override
  Future<HttpClientRequest> getUrl(Uri url) => _request.future;
  @override
  void close({bool force = false}) {
    closed = true;
    if (!_request.isCompleted) {
      _request.completeError(const HttpException('cancelled'));
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
