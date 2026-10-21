import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/sql_executor.dart';
import 'package:gym_tracker/data/repositories/backup_repo.dart';
import 'package:gym_tracker/data/repositories/exercise_repo.dart';
import 'package:gym_tracker/data/repositories/settings_repo.dart';
import 'package:gym_tracker/domain/backup.dart';
import 'package:gym_tracker/domain/backup_upgrade.dart';

BackupFile loadFixture([String name = 'legacy-v2']) => validateBackup(
  jsonDecode(File('test/fixtures/backup/$name.json').readAsStringSync()),
);

class FailingExecutor implements SqlExecutor {
  final SqlExecutor inner;
  final String after;
  final Object error;
  FailingExecutor(this.inner, this.after, this.error);
  @override
  Future<T> transaction<T>(Future<T> Function(SqlExecutor) action) =>
      inner.transaction((tx) => action(FailingExecutor(tx, after, error)));
  @override
  Future<void> run(String sql, [List<Object?>? params]) async {
    await inner.run(sql, params);
    if (sql.startsWith(after)) throw error;
  }

  @override
  Future<List<T>> all<T>(String sql, [List<Object?>? params]) =>
      inner.all<T>(sql, params);
  @override
  Future<T?> first<T>(String sql, [List<Object?>? params]) =>
      inner.first<T>(sql, params);
}

void main() {
  late FfiExecutor exec;
  setUp(() async => exec = await FfiExecutor.openMigrated());
  tearDown(() async => exec.close());

  Future<void> restore(BackupFile backup) async =>
      restoreBackup(exec, await inspectBackup(exec, backup));

  test('six entity tables survive exact round trip including same-ms order and plans', () async {
    final incoming = loadFixture();
    await restore(incoming);
    final exported = await exportBackup(exec, exportedAt: 123);
    final upgraded = validateBackup(upgradeBackupToV5(incoming.toJson()));
    for (final key in upgraded.data.keys) {
      expect(exported.rows(key), upgraded.rows(key), reason: key);
    }
    expect(exported.rows('sessions').map((r) => r['id']), [
      'finished-s',
      'active-s',
    ]);
    expect(await exec.all('PRAGMA foreign_key_check'), isEmpty);
    expect(
      (await exec.first<Map<String, Object?>>(
        "SELECT value FROM app_meta WHERE key='schema_version'",
      ))!['value'],
      '11',
    );
  });
  test(
    'v1 without settings preserves theme; settings extension replaces it',
    () async {
      await setSetting(exec, 'theme_mode', 'light');
      await restore(loadFixture('legacy-v1'));
      expect(await getSetting(exec, 'theme_mode'), 'light');
      await restore(loadFixture('current-v2'));
      expect(await getSetting(exec, 'theme_mode'), 'dark');
      await seedExercisesIfEmpty(exec);
      expect(await exec.all('SELECT * FROM exercise'), isEmpty);
    },
  );
  test('a same-count edit after preview must not be overwritten', () async {
    await restore(loadFixture());
    final preview = await inspectBackup(exec, loadFixture('current-v2'));
    await exec.run("UPDATE session SET note='changed' WHERE id='finished-s'");
    await expectLater(
      restoreBackup(exec, preview),
      throwsA(isA<BackupValidationException>()),
    );
    expect(
      (await exec.first<Map<String, Object?>>(
        "SELECT note FROM session WHERE id='finished-s'",
      ))!['note'],
      'changed',
    );
  });
  for (final needle in [
    'DELETE FROM session_exercise',
    'INSERT INTO session ',
    'INSERT INTO app_setting',
  ]) {
    test(
      'injected failure after $needle restores all tables, settings and metadata',
      () async {
        await restore(loadFixture());
        await setSetting(exec, 'theme_mode', 'light');
        final before = (await exportBackup(exec, exportedAt: 0)).toJson();
        final meta = await exec.all<Map<String, Object?>>(
          'SELECT * FROM app_meta ORDER BY key',
        );
        final failure = StateError('injected $needle');
        final faulty = FailingExecutor(exec, needle, failure);
        final source = loadFixture();
        final raw = source.toJson();
        final data = Map<String, Object?>.from(raw['data'] as Map);
        data['settings'] = [
          {'key': 'theme_mode', 'value': 'dark'},
        ];
        final incoming = validateBackup({...raw, 'data': data});
        final preview = await inspectBackup(faulty, incoming);
        await expectLater(
          restoreBackup(faulty, preview),
          throwsA(same(failure)),
        );
        expect((await exportBackup(exec, exportedAt: 0)).toJson(), before);
        expect(
          await exec.all<Map<String, Object?>>(
            'SELECT * FROM app_meta ORDER BY key',
          ),
          meta,
        );
      },
    );
  }
}
