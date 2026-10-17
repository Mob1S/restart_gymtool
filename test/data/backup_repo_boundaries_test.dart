import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/migrations.dart';
import 'package:gym_tracker/data/repositories/backup_repo.dart';
import 'package:gym_tracker/data/repositories/exercise_repo.dart';
import 'package:gym_tracker/data/repositories/settings_repo.dart';
import 'package:gym_tracker/domain/backup.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'backup_repo_test.dart' show loadFixture, FailingExecutor;

void main() {
  late FfiExecutor exec;
  setUp(() async => exec = await FfiExecutor.openMigrated());
  tearDown(() async => exec.close());

  test(
    'same-ms, reverse IDs and tied positions preserve insertion order',
    () async {
      final raw = jsonDecode(
        jsonEncode(loadFixture().toJson()),
      ) as Map<String, dynamic>;
      final sets = raw['data']['sets'] as List;
      sets[0]['id'] = 'z';
      sets.insert(1, {
        ...sets[0] as Map<String, dynamic>,
        'id': 'a',
        'weight': 30,
      });
      final incoming = validateBackup(raw);
      await restoreBackup(exec, await inspectBackup(exec, incoming));
      // Reverse SQLite's unspecified scan order: removing ORDER BY now fails.
      await exec.run('PRAGMA reverse_unordered_selects = ON');
      final exported = await exportBackup(exec, exportedAt: 0);
      expect(exported.rows('sets').map((r) => r['id']), ['z', 'a', 'pending']);
      expect(exported.rows('sessions').map((r) => r['id']), [
        'finished-s',
        'active-s',
      ]);
      await restoreBackup(exec, await inspectBackup(exec, exported));
      expect((await exportBackup(exec, exportedAt: 0)).data, exported.data);
    },
  );
  test('old source schema cannot downgrade local schema; empty settings clears preferences', () async {
    final raw = jsonDecode(
      jsonEncode(loadFixture('legacy-v1').toJson()),
    ) as Map<String, dynamic>;
    raw['schemaVersion'] = 1;
    raw['data']['settings'] = [];
    await setSetting(exec, 'theme_mode', 'dark');
    await restoreBackup(exec, await inspectBackup(exec, validateBackup(raw)));
    expect(await getSchemaVersion(exec), 6);
    expect(await getSetting(exec, 'theme_mode'), isNull);
  });
  test(
    'failure after new seed marker restores its absence as well as all data',
    () async {
      await setSetting(exec, 'theme_mode', 'light');
      final before = (await exportBackup(exec, exportedAt: 0)).toJson();
      final failure = StateError('marker');
      final faulty = FailingExecutor(exec, 'INSERT INTO app_meta', failure);
      await expectLater(
        restoreBackup(faulty, await inspectBackup(faulty, loadFixture())),
        throwsA(same(failure)),
      );
      expect((await exportBackup(exec, exportedAt: 0)).toJson(), before);
      expect(
        await exec.first(
          "SELECT value FROM app_meta WHERE key='seed_initialized'",
        ),
        isNull,
      );
    },
  );
  test(
    'restored empty file database remains empty after close and reopen',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'gym-backup-test-',
      );
      final path = '${directory.path}/database.sqlite';
      Future<FfiExecutor> open() async {
        final db = await databaseFactoryFfi.openDatabase(path);
        final result = FfiExecutor.fromDatabase(db);
        await result.run('PRAGMA foreign_keys = ON');
        await migrate(result);
        return result;
      }

      var file = await open();
      try {
        await seedExercisesIfEmpty(file);
        await restoreBackup(
          file,
          await inspectBackup(file, loadFixture('current-v2')),
        );
        await file.close();
        file = await open();
        await seedExercisesIfEmpty(file);
        expect(await file.all('SELECT * FROM exercise'), isEmpty);
        expect(await getSetting(file, 'theme_mode'), 'dark');
        expect(await getSchemaVersion(file), 6);
      } finally {
        await file.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
