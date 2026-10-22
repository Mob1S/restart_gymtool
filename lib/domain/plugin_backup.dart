const reservedPluginBackupIds = {'gym.training', 'gym.calories', 'gym.motion'};
const maxPluginJsonDepth = 32;

bool validPluginId(String value) =>
    RegExp(r'^[a-z][a-z0-9]*(?:[._-][a-z0-9]+)+$').hasMatch(value);

/// Validate and copy every container, preventing mutation after validation.
Object? copyPluginJson(Object? value, {int depth = 0}) {
  if (depth > maxPluginJsonDepth) {
    throw const FormatException('插件 JSON 嵌套超过 32 层');
  }
  if (value == null || value is String || value is bool) return value;
  if (value is num && value.isFinite) return value;
  if (value is List) {
    return List<Object?>.unmodifiable([
      for (final item in value) copyPluginJson(item, depth: depth + 1),
    ]);
  }
  if (value is Map && value.keys.every((key) => key is String)) {
    return Map<String, Object?>.unmodifiable({
      for (final entry in value.entries)
        entry.key as String: copyPluginJson(entry.value, depth: depth + 1),
    });
  }
  throw const FormatException('插件数据必须是有限数值、字符串、布尔值、null 或 JSON 容器');
}

class PluginBackupData {
  final int dataVersion;
  final Map<String, Object?> records;
  const PluginBackupData._(this.dataVersion, this.records);

  factory PluginBackupData.fromJson(Object? value) {
    if (value is! Map ||
        value.keys.any((key) => key is! String) ||
        value.length != 2 ||
        !value.containsKey('dataVersion') ||
        !value.containsKey('records')) {
      throw const FormatException('插件封装必须包含 dataVersion 与 records');
    }
    final version = value['dataVersion'];
    final rows = value['records'];
    if (version is! int || version < 1 || version > 2147483647) {
      throw const FormatException('插件 dataVersion 必须是正整数');
    }
    if (rows is! List) throw const FormatException('插件 records 必须是数组');
    final records = <String, Object?>{};
    for (final row in rows) {
      if (row is! Map ||
          row.length != 2 ||
          !row.containsKey('key') ||
          !row.containsKey('value')) {
        throw const FormatException('插件记录必须包含 key 与 value');
      }
      final key = row['key'];
      if (key is! String || key.trim().isEmpty) {
        throw const FormatException('插件记录 key 必须是非空字符串');
      }
      if (records.containsKey(key)) throw FormatException('插件记录包含重复 key：$key');
      records[key] = copyPluginJson(row['value']);
    }
    return PluginBackupData._(version, Map.unmodifiable(records));
  }

  Map<String, Object?> toJson() => {
    'dataVersion': dataVersion,
    'records': [
      for (final entry in records.entries)
        {'key': entry.key, 'value': entry.value},
    ],
  };
}

Map<String, PluginBackupData> validatePluginBackups(Object? value) {
  if (value is! Map || value.keys.any((key) => key is! String)) {
    throw const FormatException('plugins 必须是对象');
  }
  final result = <String, PluginBackupData>{};
  for (final entry in value.entries) {
    final id = entry.key as String;
    if (!validPluginId(id)) throw FormatException('插件 ID 无效：$id');
    if (reservedPluginBackupIds.contains(id)) {
      throw FormatException('plugins 不能包含保留 ID：$id');
    }
    result[id] = PluginBackupData.fromJson(entry.value);
  }
  return Map.unmodifiable(result);
}
