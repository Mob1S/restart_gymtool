import 'dart:async';

import '../api/plugin_runtime.dart';
import '../runtime/plugin_scope.dart';

typedef PluginRequestHandler = Future<JsonMap> Function(JsonMap arguments);

class HostMethod {
  const HostMethod({
    required this.capability,
    required this.handle,
    this.control = true,
  });
  final String capability;
  final PluginRequestHandler handle;

  /// Media tasks report progress and cancel explicitly instead of timing out.
  final bool control;
}

class HostTopic {
  const HostTopic({required this.capability, required this.events});
  final String capability;
  final Stream<JsonMap> events;
}

/// Dispatches only registered methods, using the identity bound to this scope.
class BoundPluginHost implements PluginHost {
  BoundPluginHost({
    required this.scope,
    required Set<String> grantedCapabilities,
    Map<String, HostMethod> methods = const {},
    Map<String, HostTopic> topics = const {},
    this.controlTimeout = const Duration(seconds: 10),
    this.onRequest,
  }) : grantedCapabilities = Set.unmodifiable(grantedCapabilities),
       _methods = Map.unmodifiable(methods),
       _topics = Map.unmodifiable(topics);

  final PluginScope scope;
  @override
  final Set<String> grantedCapabilities;
  final Map<String, HostMethod> _methods;
  final Map<String, HostTopic> _topics;
  final Duration controlTimeout;

  /// Optional tracing receives the same immutable envelope used for dispatch.
  final void Function(PluginRequest request)? onRequest;

  void _authorize(String capability) {
    scope.ensureActive();
    if (!grantedCapabilities.contains(capability)) {
      throw PluginException(
        PluginErrorCode.permissionDenied,
        '插件没有使用此能力的权限',
        pluginId: scope.pluginId,
      );
    }
  }

  @override
  Future<JsonMap> request(String method, JsonMap arguments) async {
    scope.ensureActive();
    final registration = _methods[method];
    if (registration == null) {
      throw const PluginException(PluginErrorCode.invalidData, '插件请求的方法不存在');
    }
    _authorize(registration.capability);
    final safe = copyPluginJsonMap(arguments);
    // Private storage identities cannot be overridden by message arguments.
    if (safe.containsKey('pluginId') && safe['pluginId'] != scope.pluginId) {
      throw const PluginException(
        PluginErrorCode.permissionDenied,
        '无法访问其他插件的数据',
      );
    }
    final request = PluginRequest(
      requestId: scope.nextRequestId(),
      method: method,
      arguments: safe,
      generation: scope.generation,
    );
    try {
      onRequest?.call(request);
      final task = scope.runRequest(
        request.requestId,
        () => registration.handle(request.arguments),
      );
      final result = await (registration.control
          ? task.timeout(controlTimeout)
          : task);
      scope.ensureActive();
      return copyPluginJsonMap(result);
    } on TimeoutException {
      // Transaction commit guards inherit the request zone and reject late writes.
      scope.cancelRequest(request.requestId);
      throw const PluginException(PluginErrorCode.timeout, '插件请求超时');
    } on PluginException {
      rethrow;
    } catch (_) {
      throw const PluginException(PluginErrorCode.internalError, '插件能力调用失败');
    }
  }

  @override
  Stream<JsonMap> subscribe(String topic) {
    scope.ensureActive();
    final registration = _topics[topic];
    if (registration == null) {
      throw const PluginException(PluginErrorCode.invalidData, '插件事件主题不存在');
    }
    _authorize(registration.capability);
    final requestId = scope.nextRequestId();
    late StreamController<JsonMap> controller;
    StreamSubscription<JsonMap>? subscription;
    controller = StreamController<JsonMap>(
      onListen: () {
        try {
          scope.ensureActive();
        } catch (error, stack) {
          // The stream may be listened to after its instance has been stopped.
          // Report through the stream instead of throwing from onListen's zone.
          controller.addError(error, stack);
          unawaited(controller.close());
          return;
        }
        subscription = registration.events.listen(
          (event) {
            if (!scope.acceptsRequests) return;
            controller.add(
              PluginEvent(
                requestId: requestId,
                generation: scope.generation,
                type: topic,
                payload: event,
              ).toJson(),
            );
          },
          onError: (Object error, StackTrace stack) {
            if (scope.acceptsRequests) controller.addError(error, stack);
          },
          onDone: controller.close,
        );
        scope.addCleanup(() async {
          await subscription?.cancel();
          // A paused single-subscription consumer must not block plugin shutdown.
          unawaited(controller.close());
        });
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () => subscription?.cancel(),
    );
    return controller.stream;
  }
}
