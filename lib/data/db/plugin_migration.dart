import 'sql_executor.dart';

const pluginTablesSql = '''
CREATE TABLE IF NOT EXISTS plugin_state (
  plugin_id TEXT PRIMARY KEY,
  desired_enabled INTEGER NOT NULL CHECK(desired_enabled IN (0,1))
);
CREATE TABLE IF NOT EXISTS plugin_data_version (
  plugin_id TEXT PRIMARY KEY,
  data_version INTEGER NOT NULL CHECK(data_version > 0)
);
CREATE TABLE IF NOT EXISTS plugin_document (
  plugin_id TEXT NOT NULL,
  document_key TEXT NOT NULL,
  data_version INTEGER NOT NULL CHECK(data_version > 0),
  payload TEXT NOT NULL,
  PRIMARY KEY(plugin_id, document_key),
  FOREIGN KEY(plugin_id) REFERENCES plugin_data_version(plugin_id)
);
''';

/// Persist before historical DDL so an interrupted fresh install stays fresh.
Future<void> recordPluginInstallOrigin(SqlExecutor exec) async {
  final existing = await exec.first<Map<String, Object?>>(
    "SELECT value FROM app_meta WHERE key='plugin_install_origin'",
  );
  if (existing != null) return;
  final version = await exec.first<Map<String, Object?>>(
    "SELECT value FROM app_meta WHERE key='schema_version'",
  );
  final tables = await exec.all<Map<String, Object?>>(
    "SELECT name FROM sqlite_master WHERE type='table' AND name IN "
    "('exercise','session','session_exercise','set_entry','split_template',"
    "'template_exercise','training_plan','exercise_preference','training_program',"
    "'motion_project','video_review','beverage','drink_record')",
  );
  await exec.run(
    "INSERT OR IGNORE INTO app_meta(key,value) VALUES('plugin_install_origin',?)",
    [version != null || tables.isNotEmpty ? 'legacy' : 'fresh'],
  );
}

/// Caller owns the schema-12 transaction, including its final version write.
Future<void> migratePluginsV12(SqlExecutor tx) async {
  await tx.run(pluginTablesSql);
  final origin = await tx.first<Map<String, Object?>>(
    "SELECT value FROM app_meta WHERE key='plugin_install_origin'",
  );
  final enabled = origin?['value'] == 'legacy' ? 1 : 0;
  for (final id in ['gym.training', 'gym.calories', 'gym.motion']) {
    await tx.run(
      'INSERT OR IGNORE INTO plugin_state(plugin_id,desired_enabled) VALUES(?,?)',
      [id, id == 'gym.training' ? 1 : enabled],
    );
  }
}
