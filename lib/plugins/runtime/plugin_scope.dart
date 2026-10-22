import 'dart:async';

import '../api/plugin_protocol.dart';

class _ScopedRequest {
  _ScopedRequest(this.owner);
  final PluginScope owner;
  bool cancelled = false;
}

/// One instance owns one scope. Revocation never affects a replacement scope.
class PluginScope {
  PluginScope(this.pluginId, {this.generation = 0});

  final String pluginId;
  final int generation;
  final Object token = Object();
  static int _nextScope = 0;
  static final Object _requestZone = Object();
  final int _scopeId = ++_nextScope;
  int _nextRequest = 0;
  final Map<String, _ScopedRequest> _requests = {};
  final List<FutureOr<void> Function()> _cleanups = [];
  bool _active = true;
  bool _acceptingRequests = true;
  Future<void>? _closing;

  bool get isActive => _active;
  bool get acceptsRequests => _active && _acceptingRequests;

  String nextRequestId() => '$pluginId:$generation:$_scopeId:${++_nextRequest}';

  Future<T> runRequest<T>(String requestId, Future<T> Function() action) async {
    ensureActive();
    final request = _ScopedRequest(this);
    _requests[requestId] = request;
    try {
      return await runZoned(action, zoneValues: {_requestZone: request});
    } finally {
      request.cancelled = true;
      _requests.remove(requestId);
    }
  }

  void cancelRequest(String requestId) {
    _requests[requestId]?.cancelled = true;
  }

  void ensureActive() {
    if (!acceptsRequests) {
      throw PluginException(
        PluginErrorCode.pluginDisabled,
        '插件当前不可用',
        pluginId: pluginId,
      );
    }
    final request = Zone.current[_requestZone];
    if (request is _ScopedRequest &&
        identical(request.owner, this) &&
        request.cancelled) {
      throw PluginException(
        PluginErrorCode.cancelled,
        '插件请求已取消',
        pluginId: pluginId,
      );
    }
  }

  void suspendRequests() => _acceptingRequests = false;
  void resumeRequests() {
    if (_active) _acceptingRequests = true;
  }

  void revoke() {
    _active = false;
    _acceptingRequests = false;
  }

  void addCleanup(FutureOr<void> Function() cleanup) {
    if (!_active) {
      unawaited(Future<void>.sync(cleanup));
      return;
    }
    _cleanups.add(cleanup);
  }

  void trackSubscription(StreamSubscription<Object?> subscription) =>
      addCleanup(subscription.cancel);

  Future<void> close() => _closing ??= _close().then<void>(
    (_) {},
    onError: (Object error, StackTrace stack) {
      // Retry only resources whose previous cleanup did not confirm success.
      _closing = null;
      Error.throwWithStackTrace(error, stack);
    },
  );

  Future<void> _close() async {
    revoke();
    Object? firstError;
    StackTrace? firstStack;
    for (var index = _cleanups.length - 1; index >= 0; index--) {
      try {
        await _cleanups[index]();
        _cleanups.removeAt(index);
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
      }
    }
    if (firstError != null) Error.throwWithStackTrace(firstError, firstStack!);
  }
}
