import 'dart:convert';

import '../../domain/plugin_backup.dart';
import '../db/sql_executor.dart';

/// Storage adapters never activate execution/UI/media runtimes.
abstract interface class PluginBackupAdapter {
  Future<Map<String, PluginBackupData>> snapshot(SqlExecutor tx);
  Future<void> restore(SqlExecutor tx, Map<String, PluginBackupData> plugins);
}

class NamespacedPluginBackupAdapter implements PluginBackupAdapter {
  const NamespacedPluginBackupAdapter();

  @override
  Future<Map<String, PluginBackupData>> snapshot(SqlExecutor tx) async {
    final versions = await tx.all<Map<String, Object?>>(
      'SELECT plugin_id,data_version FROM plugin_data_version ORDER BY plugin_id',
    );
    final result = <String, Object?>{};
    for (final version in versions) {
      final id = version['plugin_id'] as String;
      final rows = await tx.all<Map<String, Object?>>(
        'SELECT document_key,data_version,payload FROM plugin_document WHERE plugin_id=? ORDER BY rowid',
        [id],
      );
      if (rows.any((row) => row['data_version'] != version['data_version'])) {
        throw StateError('插件数据版本不一致：$id');
      }
      result[id] = {
        'dataVersion': version['data_version'],
        'records': [
          for (final row in rows)
            {
              'key': row['document_key'],
              'value': jsonDecode(row['payload'] as String),
            },
        ],
      };
    }
    return validatePluginBackups(result);
  }

  @override
  Future<void> restore(
    SqlExecutor tx,
    Map<String, PluginBackupData> plugins,
  ) async {
    // Only explicitly present namespaces are replaced. Empty records retain version.
    for (final entry in plugins.entries) {
      await tx.run('DELETE FROM plugin_document WHERE plugin_id=?', [
        entry.key,
      ]);
      await tx.run(
        'INSERT INTO plugin_data_version(plugin_id,data_version) VALUES(?,?) ON CONFLICT(plugin_id) DO UPDATE SET data_version=excluded.data_version',
        [entry.key, entry.value.dataVersion],
      );
      for (final record in entry.value.records.entries) {
        await tx.run(
          'INSERT INTO plugin_document(plugin_id,document_key,data_version,payload) VALUES(?,?,?,?)',
          [
            entry.key,
            record.key,
            entry.value.dataVersion,
            jsonEncode(record.value),
          ],
        );
      }
    }
  }
}
