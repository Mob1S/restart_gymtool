import '../db/sql_executor.dart';

Future<Map<String, bool>> loadPluginPreferences(SqlExecutor exec) async {
  final rows = await exec.all<Map<String, Object?>>(
    'SELECT plugin_id,desired_enabled FROM plugin_state ORDER BY plugin_id',
  );
  return Map.unmodifiable({
    for (final row in rows)
      row['plugin_id'] as String: row['desired_enabled'] == 1,
  });
}

Future<void> savePluginPreference(
  SqlExecutor exec,
  String pluginId,
  bool enabled,
) async {
  if (pluginId.trim().isEmpty) throw ArgumentError.value(pluginId, 'pluginId');
  if (pluginId == 'gym.training' && !enabled) {
    throw ArgumentError('基础训练不可停用');
  }
  await exec.run(
    'INSERT INTO plugin_state(plugin_id,desired_enabled) VALUES(?,?) '
    'ON CONFLICT(plugin_id) DO UPDATE SET desired_enabled=excluded.desired_enabled',
    [pluginId, enabled ? 1 : 0],
  );
}
