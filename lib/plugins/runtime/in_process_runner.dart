import 'dart:async';

import '../api/plugin_runtime.dart';
import 'plugin_scope.dart';

class InProcessRunner {
  InProcessRunner({
    required this.runtime,
    required this.scope,
    this.controlTimeout = const Duration(seconds: 10),
  });

  final PluginRuntime runtime;
  final PluginScope scope;
  final Duration controlTimeout;

  Future<T> control<T>(Future<T> Function() action) async {
    try {
      return await Future<T>.sync(action).timeout(controlTimeout);
    } on TimeoutException {
      scope.suspendRequests();
      throw PluginException(
        PluginErrorCode.timeout,
        '插件操作超时，请重试',
        pluginId: scope.pluginId,
      );
    }
  }

  Future<JsonMap> invoke(String method, JsonMap arguments) {
    scope.ensureActive();
    return control(() => runtime.invoke(method, copyPluginJsonMap(arguments)))
        .then((value) {
          scope.ensureActive();
          return copyPluginJsonMap(value);
        });
  }

  Future<void> close() async {
    // Revoke before awaiting platform shutdown so stale callbacks cannot write.
    scope.revoke();
    Object? stopError;
    StackTrace? stopStack;
    try {
      await control(runtime.stop);
    } catch (error, stack) {
      stopError = error;
      stopStack = stack;
    }
    try {
      await control(scope.close);
    } catch (error, stack) {
      stopError ??= error;
      stopStack ??= stack;
    }
    if (stopError != null) Error.throwWithStackTrace(stopError, stopStack!);
  }
}
