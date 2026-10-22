import 'plugin_protocol.dart';

export 'plugin_protocol.dart';

abstract interface class PluginHost {
  Set<String> get grantedCapabilities;
  Future<JsonMap> request(String method, JsonMap arguments);
  Stream<JsonMap> subscribe(String topic);
}

abstract interface class PluginRuntime {
  Future<void> start(PluginHost host);
  Future<JsonMap> invoke(String method, JsonMap arguments);
  Future<void> cancel(String requestId);
  Future<StopDecision> prepareStop();
  Future<void> stop();
}
