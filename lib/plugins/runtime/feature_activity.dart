import '../api/plugin_runtime.dart';

/// Registrations belong to one page instance and are removed idempotently.
class FeatureActivityRegistry {
  final _activities =
      <Object, (StopDecision Function(), Future<void> Function())>{};
  void Function() register(
    StopDecision Function() decision,
    Future<void> Function() close,
  ) {
    final token = Object();
    _activities[token] = (decision, close);
    return () => _activities.remove(token);
  }

  StopDecision prepareStop() {
    for (final activity in _activities.values) {
      final decision = activity.$1();
      if (decision != StopDecision.ready) return decision;
    }
    return StopDecision.ready;
  }

  Future<void> close() async {
    Object? firstError;
    StackTrace? firstStack;
    for (final activity in _activities.values.toList()) {
      try {
        await activity.$2();
      } catch (error, stack) {
        firstError ??= error;
        firstStack ??= stack;
      }
    }
    if (firstError != null) Error.throwWithStackTrace(firstError, firstStack!);
  }
}

class FeaturePluginRuntime implements PluginRuntime {
  final FeatureActivityRegistry activities;
  final Future<void> Function()? onStart, onStop;
  PluginHost? _host;
  Future<void>? _starting;
  Future<void>? _stopping;
  FeaturePluginRuntime(this.activities, {this.onStart, this.onStop});
  PluginHost get host => _host ?? (throw StateError('此功能尚未启用'));
  @override
  Future<void> start(PluginHost host) async {
    // A timed-out close may still be running. Never race its platform callbacks.
    final stopping = _stopping;
    if (stopping != null) await stopping;
    if (_host != null) {
      if (identical(_host, host)) {
        await _starting;
        return;
      }
      throw const PluginException(PluginErrorCode.busy, '上一个功能实例尚未关闭');
    }
    _stopping = null;
    _host = host;
    final starting = Future<void>.sync(() async {
      await onStart?.call();
    });
    _starting = starting;
    try {
      await starting;
    } finally {
      if (identical(_starting, starting)) _starting = null;
    }
  }

  @override
  Future<Map<String, Object?>> invoke(
    String method,
    Map<String, Object?> arguments,
  ) => host.request(method, arguments);
  @override
  Future<void> cancel(String requestId) async {}
  @override
  Future<StopDecision> prepareStop() async => activities.prepareStop();
  @override
  Future<void> stop() {
    final pending = _stopping;
    if (pending != null) return pending;
    final owner = _host;
    if (owner == null) return Future.value();
    return _stopping = _close(owner).then<void>(
      (_) {},
      onError: (Object error, StackTrace stack) {
        // A confirmed failure is retryable; a pending timeout shares this future.
        _stopping = null;
        Error.throwWithStackTrace(error, stack);
      },
    );
  }

  Future<void> _close(PluginHost owner) async {
    try {
      await _starting;
    } catch (_) {
      // Partial start failures still require platform and activity cleanup.
    }
    Object? firstError;
    StackTrace? firstStack;
    try {
      await activities.close();
    } catch (error, stack) {
      firstError = error;
      firstStack = stack;
    }
    try {
      await onStop?.call();
    } catch (error, stack) {
      firstError ??= error;
      firstStack ??= stack;
    }
    if (firstError != null) Error.throwWithStackTrace(firstError, firstStack!);
    if (identical(_host, owner)) _host = null;
  }
}
