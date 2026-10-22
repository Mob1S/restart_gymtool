import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/migrations.dart';
import 'package:gym_tracker/data/repositories/backup_repo.dart';
import 'package:gym_tracker/data/repositories/beverage_repo.dart';
import 'package:gym_tracker/data/repositories/plugin_document_repo.dart';
import 'package:gym_tracker/data/repositories/plugin_state_repo.dart';
import 'package:gym_tracker/domain/backup.dart';
import 'package:gym_tracker/domain/backup_upgrade.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'backup_repo_test.dart' show FailingExecutor, loadFixture;
import '../domain/plugin_backup_validation_test.dart' show v8;
import '../domain/beverage_test.dart' show beverage, drink;

void main() {
  late FfiExecutor exec;
  late PluginDocumentRepo repo;
  setUp(() async {
    exec = await FfiExecutor.openMigrated();
    repo = PluginDocumentRepo(exec);
  });
  tearDown(() => exec.close());
  Future<void> restore(BackupFile incoming) async =>
      restoreBackup(exec, await inspectBackup(exec, incoming));
  for (var version = 1; version <= 6; version++) {
    test(
      'legacy v$version preserves local drinks with calories disabled',
      () async {
        final drinks = BeverageRepo(exec);
        await drinks.saveRecord(drink(), newBeverage: beverage());
        Map<String, Object?> raw = loadFixture(
          version == 1 ? 'legacy-v1' : 'legacy-v2',
        ).toJson();
        if (version == 3) {
          raw = {
            ...raw,
            'version': 3,
            'schemaVersion': 5,
            'data': {...raw['data'] as Map, 'exercisePreferences': []},
          };
        } else if (version == 4) {
          raw = upgradeBackupToV4(raw);
        } else if (version == 5) {
          raw = upgradeBackupToV5(raw);
        } else if (version == 6) {
          raw = upgradeBackupToV6(raw);
        }
        await restore(validateBackup(raw));
        expect((await drinks.records()).single.toJson(), drink().toJson());
        expect((await loadPluginPreferences(exec))['gym.calories'], false);
        expect(
          (await exportBackup(exec, exportedAt: 0)).rows('drinkRecords'),
          hasLength(1),
        );
      },
    );
  }
  for (final version in [7, 8]) {
    test(
      'v$version explicitly replaces drinks while calories remains disabled',
      () async {
        final drinks = BeverageRepo(exec);
        await drinks.saveRecord(drink(), newBeverage: beverage());
        final raw = v8();
        if (version == 7) {
          raw['version'] = 7;
          raw['schemaVersion'] = 11;
          raw.remove('plugins');
        }
        await restore(validateBackup(raw));
        expect(await drinks.records(), isEmpty);
        expect(await drinks.library(), isEmpty);
        expect((await loadPluginPreferences(exec))['gym.calories'], false);
      },
    );
  }
  test(
    'unknown namespace round trip preserves content and explicit empty version',
    () async {
      final raw = v8({
        'community.example': {
          'dataVersion': 3,
          'records': [
            {
              'key': 'preferences',
              'value': {
                'displayUnit': 'kg',
                'nested': [1, null, true],
              },
            },
          ],
        },
      });
      await restore(validateBackup(raw));
      var exported = await exportBackup(exec, exportedAt: 0);
      expect(exported.toJson()['plugins'], raw['plugins']);
      await repo.write('community.other', 'key', 'preserved');
      await restore(
        validateBackup(
          v8({
            'community.example': {'dataVersion': 4, 'records': []},
          }),
        ),
      );
      expect(await repo.readAll('community.example'), isEmpty);
      expect(await repo.dataVersion('community.example'), 4);
      expect(await repo.read('community.other', 'key'), 'preserved');
      exported = await exportBackup(exec, exportedAt: 0);
      expect(exported.plugins!['community.example']!.toJson(), {
        'dataVersion': 4,
        'records': [],
      });
    },
  );
  test('legacy restores retain namespaces and local plugin choices', () async {
    await repo.write('community.example', 'key', {'v': 1});
    await savePluginPreference(exec, 'gym.motion', true);
    final states = await loadPluginPreferences(exec);
    await restore(loadFixture());
    expect(await repo.read('community.example', 'key'), {'v': 1});
    expect(await loadPluginPreferences(exec), states);
  });
  test('extension edit invalidates preview and restore failure rolls back whole batch', () async {
    final incoming = validateBackup(
      v8({
        'community.example': {
          'dataVersion': 1,
          'records': [
            {'key': 'x', 'value': 1},
          ],
        },
      }),
    );
    final preview = await inspectBackup(exec, incoming);
    await repo.write('community.other', 'key', true);
    await expectLater(
      restoreBackup(exec, preview),
      throwsA(isA<BackupValidationException>()),
    );
    final before = (await exportBackup(exec, exportedAt: 0)).toJson();
    final faulty = FailingExecutor(
      exec,
      'INSERT INTO plugin_document',
      StateError('disk'),
    );
    await expectLater(
      restoreBackup(faulty, await inspectBackup(faulty, incoming)),
      throwsStateError,
    );
    expect((await exportBackup(exec, exportedAt: 0)).toJson(), before);
  });
  test('legacy restore exceeding budget with retained namespaces rolls back training', () async {
    await repo.write(
      'community.example',
      'large',
      'x' * (maxBackupBytes - 3000),
    );
    final raw = loadFixture().toJson();
    final data = {...loadFixture().data};
    data['sessions'] = [
      for (final row in loadFixture().rows('sessions'))
        {...row, 'note': 'x' * 4000},
    ];
    final incoming = validateBackup({...raw, 'data': data});
    final before = (await exportBackup(exec, exportedAt: 0)).toJson();
    await expectLater(
      restoreBackup(exec, await inspectBackup(exec, incoming)),
      throwsA(isA<BackupValidationException>()),
    );
    expect((await exportBackup(exec, exportedAt: 0)).toJson(), before);
  });
  test(
    'unknown namespaces survive database close and reopen without activation',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'gym-plugin-backup-',
      );
      Future<FfiExecutor> open() async {
        final db = await databaseFactoryFfi.openDatabase(
          '${directory.path}/plugins.sqlite',
        );
        final file = FfiExecutor.fromDatabase(db);
        await file.run('PRAGMA foreign_keys = ON');
        await migrate(file);
        return file;
      }

      var file = await open();
      final raw = v8({
        'community.example': {
          'dataVersion': 2,
          'records': [
            {
              'key': 'preferences',
              'value': {'displayUnit': 'kg'},
            },
          ],
        },
      });
      try {
        await restoreBackup(
          file,
          await inspectBackup(file, validateBackup(raw)),
        );
        await file.close();
        file = await open();
        expect(
          (await exportBackup(file, exportedAt: 0)).toJson()['plugins'],
          raw['plugins'],
        );
        expect((await loadPluginPreferences(file))['gym.calories'], false);
      } finally {
        await file.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
