import 'dart:convert';

import '../../domain/backup.dart';
import '../../domain/backup_codec.dart';
import '../../domain/backup_upgrade.dart';
import '../db/migrations.dart';
import '../db/sql_executor.dart';

class BackupPreview {
  final BackupFile incoming;
  final BackupFile current;
  final String _baseline;
  BackupPreview._(this.incoming, this.current)
    : _baseline = jsonEncode(current.data);
}

class _Table {
  final String name;
  final List<String> fields;
  final Set<String> booleans;
  const _Table(this.name, this.fields, [this.booleans = const {}]);
  List<String> get columns => fields.map(_column).toList();
}

String _column(String field) =>
    field.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');

const _tables = {
  'exercisePreferences': _Table(
    'exercise_preference',
    [
      'exerciseId',
      'weightUnit',
      'kgStep',
      'lbStep',
      'showKgEquivalent',
      'isFavorite',
      'equipmentNote',
    ],
    {'showKgEquivalent', 'isFavorite'},
  ),
  'exercises': _Table(
    'exercise',
    [
      'id',
      'name',
      'muscleGroup',
      'equipment',
      'isCustom',
      'isArchived',
      'createdAt',
    ],
    {'isCustom', 'isArchived'},
  ),
  'sessions': _Table('session', [
    'id',
    'name',
    'startedAt',
    'finishedAt',
    'note',
    'templateId',
    'planId',
    'planNameSnapshot',
    'dayNameSnapshot',
    'origin',
  ]),
  'sessionExercises': _Table('session_exercise', [
    'id',
    'sessionId',
    'exerciseId',
    'position',
    'note',
  ]),
  'sets': _Table(
    'set_entry',
    [
      'id',
      'sessionExerciseId',
      'position',
      'weight',
      'reps',
      'isCompleted',
      'restSeconds',
      'restStartedAt',
      'completedAt',
      'sourceWeight',
      'sourceUnit',
    ],
    {'isCompleted'},
  ),
  'templates': _Table('split_template', [
    'id',
    'name',
    'position',
    'createdAt',
    'planId',
    'kind',
  ]),
  'plans': _Table('training_plan', [
    'id',
    'name',
    'position',
    'createdAt',
    'activatedOn',
  ]),
  'templateExercises': _Table('template_exercise', [
    'id',
    'templateId',
    'exerciseId',
    'position',
  ]),
  'settings': _Table('app_setting', ['key', 'value']),
};

Future<Map<String, Object?>> _readData(SqlExecutor tx) async {
  final data = <String, Object?>{};
  for (final entry in _tables.entries) {
    final table = entry.value;
    final rows = await tx.all<Map<String, Object?>>(
      'SELECT ${table.columns.join(',')} FROM ${table.name} ORDER BY ${entry.key == 'settings' ? 'key' : 'rowid ASC'}',
    );
    data[entry.key] = rows
        .map(
          (row) => {
            for (final field in table.fields)
              field: table.booleans.contains(field)
                  ? switch (row[_column(field)]) {
                      0 => false,
                      1 => true,
                      _ => throw StateError('数据库布尔字段损坏：${table.name}.$field'),
                    }
                  : row[_column(field)],
          },
        )
        .toList();
  }
  return data;
}

Future<BackupFile> _snapshot(SqlExecutor tx, int exportedAt) async =>
    validateBackup({
      'format': backupFormat,
      'version': backupVersion,
      'schemaVersion': schemaVersion,
      'exportedAt': exportedAt,
      'data': await _readData(tx),
    });

/// Caller holds a transaction; never starts a nested transaction.
Future<BackupFile> readBackupSnapshot(
  SqlExecutor tx, {
  required int exportedAt,
}) => _snapshot(tx, exportedAt);

Future<BackupFile> exportBackup(
  SqlExecutor exec, {
  required int exportedAt,
}) async {
  final backup = await exec.transaction((tx) => _snapshot(tx, exportedAt));
  encodeBackup(backup); // Refuse an export this app could not read back.
  return backup;
}

Future<BackupPreview> inspectBackup(
  SqlExecutor exec,
  BackupFile incoming,
) async {
  // Check the source byte limit before normalization as well as the expanded
  // current size; neither legacy defaults nor new parent rows bypass limits.
  encodeBackup(incoming);
  final validated = validateBackup(upgradeBackupToV5(incoming.toJson()));
  encodeBackup(validated);
  return BackupPreview._(validated, await exportBackup(exec, exportedAt: 0));
}

Future<void> restoreBackup(SqlExecutor exec, BackupPreview preview) async {
  final incoming = validateBackup(upgradeBackupToV5(preview.incoming.toJson()));
  await exec.transaction((tx) async {
    final current = await _snapshot(tx, 0);
    if (jsonEncode(current.data) != preview._baseline) {
      throw const BackupValidationException('本机数据已变化，请重新预览并确认恢复');
    }
    for (final table in [
      'set_entry',
      'session_exercise',
      'session',
      'template_exercise',
      'split_template',
      'training_plan',
      'exercise_preference',
      'exercise',
    ]) {
      await tx.run('DELETE FROM $table');
    }
    for (final key in [
      'exercises',
      'exercisePreferences',
      'plans',
      'templates',
      'templateExercises',
      'sessions',
      'sessionExercises',
      'sets',
    ]) {
      await _insert(tx, key, incoming.rows(key));
    }
    if (incoming.hasSettings) {
      await tx.run('DELETE FROM app_setting');
      await _insert(tx, 'settings', incoming.rows('settings'));
    }
    await tx.run(
      "INSERT INTO app_meta (key,value) VALUES ('seed_initialized','1') ON CONFLICT(key) DO UPDATE SET value=excluded.value",
    );
    if ((await tx.all('PRAGMA foreign_key_check')).isNotEmpty) {
      throw StateError('恢复后的数据引用检查失败');
    }
  });
}

Future<void> _insert(
  SqlExecutor tx,
  String key,
  List<Map<String, Object?>> rows,
) async {
  final table = _tables[key]!;
  final sql =
      'INSERT INTO ${table.name} (${table.columns.join(',')}) VALUES (${List.filled(table.fields.length, '?').join(',')})';
  for (final row in rows) {
    await tx.run(
      sql,
      table.fields.map((field) {
        final value = row[field];
        return value is bool ? (value ? 1 : 0) : value;
      }).toList(),
    );
  }
}
