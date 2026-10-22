/// The control protocol intentionally contains only JSON values.
typedef JsonMap = Map<String, Object?>;

const pluginProtocolVersion = 1;
const pluginApiVersion = pluginProtocolVersion;

enum StopDecision { ready, busy, unsavedChanges }

enum PluginState { disabled, starting, enabled, stopping, failed }

enum PluginErrorCode {
  unsupportedApi,
  unsupportedPlatform,
  missingDependency,
  permissionDenied,
  pluginDisabled,
  busy,
  unsavedChanges,
  cancelled,
  timeout,
  storageFailure,
  invalidData,
  internalError,
}

class PluginException implements Exception {
  const PluginException(this.code, this.message, {this.pluginId});

  final PluginErrorCode code;
  final String message;
  final String? pluginId;

  JsonMap toJson() => {
    'code': code.name,
    'message': message,
    if (pluginId != null) 'pluginId': pluginId,
  };

  factory PluginException.fromJson(JsonMap json) {
    final code = json['code'];
    final matches = PluginErrorCode.values.where((e) => e.name == code);
    if (matches.isEmpty ||
        json['message'] is! String ||
        (json['pluginId'] != null && json['pluginId'] is! String)) {
      throw const PluginException(PluginErrorCode.invalidData, '插件错误格式无效');
    }
    return PluginException(
      matches.single,
      json['message'] as String,
      pluginId: json['pluginId'] as String?,
    );
  }

  @override
  String toString() => '${code.name}: $message';
}

/// Validates and copies a value so callers cannot mutate a published message.
Object? copyPluginJson(Object? value, {int depth = 0}) {
  if (depth > 32) {
    throw const PluginException(PluginErrorCode.invalidData, '插件数据嵌套过深');
  }
  if (value == null || value is String || value is bool) return value;
  if (value is num && value.isFinite) return value;
  if (value is List) {
    return List<Object?>.unmodifiable(
      value.map((item) => copyPluginJson(item, depth: depth + 1)),
    );
  }
  if (value is Map && value.keys.every((key) => key is String)) {
    return Map<String, Object?>.unmodifiable({
      for (final entry in value.entries)
        entry.key as String: copyPluginJson(entry.value, depth: depth + 1),
    });
  }
  throw const PluginException(PluginErrorCode.invalidData, '插件数据必须是有效的 JSON');
}

JsonMap copyPluginJsonMap(Object? value) {
  final copied = copyPluginJson(value);
  if (copied is! JsonMap) {
    throw const PluginException(PluginErrorCode.invalidData, '插件消息必须是 JSON 对象');
  }
  return copied;
}

class PluginRequest {
  PluginRequest({
    required this.requestId,
    required this.method,
    JsonMap arguments = const {},
    this.protocolVersion = pluginProtocolVersion,
    this.generation = 0,
  }) : arguments = copyPluginJsonMap(arguments) {
    if (requestId.isEmpty || method.isEmpty || generation < 0) {
      throw const PluginException(PluginErrorCode.invalidData, '插件请求缺少标识或方法');
    }
    if (protocolVersion != pluginProtocolVersion) {
      throw const PluginException(PluginErrorCode.unsupportedApi, '插件协议版本不兼容');
    }
  }

  final String requestId;
  final String method;
  final JsonMap arguments;
  final int protocolVersion;
  final int generation;

  JsonMap toJson() => {
    'requestId': requestId,
    'protocolVersion': protocolVersion,
    'generation': generation,
    'method': method,
    'arguments': arguments,
  };

  factory PluginRequest.fromJson(JsonMap json) {
    if (json['requestId'] is! String ||
        json['method'] is! String ||
        json['protocolVersion'] is! int ||
        (json['generation'] != null && json['generation'] is! int)) {
      throw const PluginException(PluginErrorCode.invalidData, '插件请求格式无效');
    }
    return PluginRequest(
      requestId: json['requestId'] as String,
      method: json['method'] as String,
      protocolVersion: json['protocolVersion'] as int,
      generation: (json['generation'] as int?) ?? 0,
      arguments: copyPluginJsonMap(json['arguments']),
    );
  }
}

class PluginEvent {
  PluginEvent({
    required this.requestId,
    required this.generation,
    required this.type,
    JsonMap payload = const {},
  }) : payload = copyPluginJsonMap(payload) {
    if (requestId.isEmpty || generation < 0 || type.isEmpty) {
      throw const PluginException(PluginErrorCode.invalidData, '插件事件格式无效');
    }
  }

  final String requestId;
  final int generation;
  final String type;
  final JsonMap payload;

  JsonMap toJson() => {
    'requestId': requestId,
    'generation': generation,
    'type': type,
    'payload': payload,
  };

  factory PluginEvent.fromJson(JsonMap json) {
    if (json['requestId'] is! String ||
        json['generation'] is! int ||
        json['type'] is! String) {
      throw const PluginException(PluginErrorCode.invalidData, '插件事件格式无效');
    }
    return PluginEvent(
      requestId: json['requestId'] as String,
      generation: json['generation'] as int,
      type: json['type'] as String,
      payload: copyPluginJsonMap(json['payload']),
    );
  }
}
