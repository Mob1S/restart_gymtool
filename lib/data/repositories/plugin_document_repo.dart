import 'dart:convert';

import '../../domain/plugin_backup.dart';
import '../db/sql_executor.dart';
import 'backup_repo.dart';

/// Host-internal storage. Public callers receive an identity-bound wrapper.
class PluginDocumentRepo {
  final SqlExecutor _exec;
  final bool _inTransaction;
  PluginDocumentRepo(SqlExecutor exec) : this._(exec, false);
  PluginDocumentRepo._(this._exec, this._inTransaction);

  Future<T> transaction<T>(Future<T> Function(PluginDocumentRepo tx) action) =>
      _inTransaction
      ? action(this)
      : _exec.transaction((tx) => action(PluginDocumentRepo._(tx, true)));

  void _identity(String pluginId, [String? key]) {
    if (!validPluginId(pluginId)) {
      throw ArgumentError.value(pluginId, 'pluginId');
    }
    if (key != null && key.trim().isEmpty) {
      throw ArgumentError.value(key, 'key');
    }
  }

  Future<int?> dataVersion(String pluginId) async {
    _identity(pluginId);
    final row = await _exec.first<Map<String, Object?>>(
      'SELECT data_version FROM plugin_data_version WHERE plugin_id=?',
      [pluginId],
    );
    return row?['data_version'] as int?;
  }

  Future<Object?> read(String pluginId, String key) async {
    _identity(pluginId, key);
    final row = await _exec.first<Map<String, Object?>>(
      'SELECT payload FROM plugin_document WHERE plugin_id=? AND document_key=?',
      [pluginId, key],
    );
    return row == null
        ? null
        : copyPluginJson(jsonDecode(row['payload'] as String));
  }

  Future<Map<String, Object?>> readAll(String pluginId) async {
    _identity(pluginId);
    final rows = await _exec.all<Map<String, Object?>>(
      'SELECT document_key,payload FROM plugin_document WHERE plugin_id=? ORDER BY rowid',
      [pluginId],
    );
    return Map.unmodifiable({
      for (final row in rows)
        row['document_key'] as String: copyPluginJson(
          jsonDecode(row['payload'] as String),
        ),
    });
  }

  Future<void> write(
    String pluginId,
    String key,
    Object? value, {
    int dataVersion = 1,
  }) => writeBatch(pluginId, {key: value}, dataVersion: dataVersion);

  Future<void> writeBatch(
    String pluginId,
    Map<String, Object?> values, {
    int dataVersion = 1,
  }) => transaction((tx) async {
    tx._identity(pluginId);
    if (dataVersion < 1 || dataVersion > 2147483647) {
      throw ArgumentError.value(dataVersion, 'dataVersion');
    }
    final current = await tx.dataVersion(pluginId);
    if (current != null && current != dataVersion) {
      throw StateError('插件数据版本不兼容，需要事务迁移');
    }
    await tx._exec.run(
      'INSERT OR IGNORE INTO plugin_data_version(plugin_id,data_version) VALUES(?,?)',
      [pluginId, dataVersion],
    );
    for (final entry in values.entries) {
      tx._identity(pluginId, entry.key);
      final payload = jsonEncode(copyPluginJson(entry.value));
      await tx._exec.run(
        'INSERT INTO plugin_document(plugin_id,document_key,data_version,payload) VALUES(?,?,?,?) ON CONFLICT(plugin_id,document_key) DO UPDATE SET data_version=excluded.data_version,payload=excluded.payload',
        [pluginId, entry.key, dataVersion, payload],
      );
    }
    await ensureBackupCapacity(tx._exec);
  });

  Future<void> delete(String pluginId, String key) => transaction((tx) async {
    tx._identity(pluginId, key);
    await tx._exec.run(
      'DELETE FROM plugin_document WHERE plugin_id=? AND document_key=?',
      [pluginId, key],
    );
  });
}
