import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/migrations.dart';
import 'package:gym_tracker/data/repositories/beverage_repo.dart';
import 'package:gym_tracker/data/repositories/backup_repo.dart';
import 'package:gym_tracker/domain/backup.dart';
import 'package:gym_tracker/domain/backup_codec.dart';
import 'package:gym_tracker/domain/beverage.dart';
import 'package:gym_tracker/domain/local_date.dart';

import '../domain/beverage_test.dart' show beverage, drink;
import 'backup_repo_test.dart' show FailingExecutor;

void main() {
  late FfiExecutor exec;
  late BeverageRepo repo;
  setUp(() async {
    exec = await FfiExecutor.openInMemory();
    await migrate(exec);
    repo = BeverageRepo(exec);
  });
  tearDown(() async => exec.close());
  test('v11 migration is idempotent and preserves existing training', () async {
    await exec.run('DROP TABLE drink_record');
    await exec.run('DROP TABLE beverage');
    await exec.run("UPDATE app_meta SET value='10' WHERE key='schema_version'");
    await exec.run("INSERT INTO session(id,started_at) VALUES('kept',123)");
    await exec.run(
      "INSERT INTO motion_project(id,mode,folder,payload,created_at,updated_at) VALUES('analysis','import','private','{}',1,1)",
    );
    await migrate(exec);
    expect(await getSchemaVersion(exec), schemaVersion);
    expect((await exec.all('SELECT * FROM session')).length, 1);
    expect((await exec.all('SELECT * FROM motion_project')).length, 1);
    await migrate(exec);
    await repo.saveBeverage(beverage());
    expect((await repo.library()).length, 1);
  });
  test(
    'library edits/archive preserve immutable historical snapshot',
    () async {
      final b = beverage();
      await repo.saveRecord(drink(), newBeverage: b);
      await repo.saveBeverage(
        Beverage.fromJson({
          ...b.toJson(),
          'energyValue': '0',
          'archived': true,
        }),
      );
      expect(await repo.library(), isEmpty);
      expect(
        (await repo.library(includeArchived: true)).single.energyValue,
        '0',
      );
      expect((await repo.records()).single.calories!.display, '138.6');
    },
  );
  test(
    'record edit moves civil date; delete removes from aggregates',
    () async {
      await repo.saveRecord(drink(), newBeverage: beverage());
      await repo.saveRecord(drink(day: 19, amount: '100'));
      expect(
        await repo.records(
          from: LocalDate(2026, 10, 20),
          through: LocalDate(2026, 10, 20),
        ),
        isEmpty,
      );
      expect((await repo.records()).single.calories!.display, '42');
      await repo.deleteRecord('r');
      expect(await repo.records(), isEmpty);
    },
  );
  test('new library and drink insert are one atomic transaction', () async {
    final faulty = BeverageRepo(
      FailingExecutor(exec, 'INSERT INTO drink_record', StateError('injected')),
    );
    await expectLater(
      faulty.saveRecord(drink(), newBeverage: beverage()),
      throwsStateError,
    );
    expect(await repo.library(), isEmpty);
    expect(await repo.records(), isEmpty);
  });
  test(
    'v7 backup roundtrip keeps zero unknown source archive and snapshots',
    () async {
      for (final b in [
        beverage(id: 'zero', energy: '0'),
        beverage(id: 'unknown', energy: null),
      ]) {
        await repo.saveRecord(
          drink(b: b, id: b.id),
          newBeverage: b.copyWith(archived: true),
        );
      }
      final original = await exportBackup(exec, exportedAt: 1);
      expect(original.version, 8);
      expect(original.schemaVersion, 12);
      final decoded = decodeBackup(encodeBackup(original));
      await repo.deleteRecord('zero');
      await restoreBackup(exec, await inspectBackup(exec, decoded));
      final restored = await exportBackup(exec, exportedAt: 1);
      expect(restored.toJson(), original.toJson());
    },
  );
  test(
    'legacy v6 backup preserves local drinks but explicit v7 empty clears',
    () async {
      final empty = await exportBackup(exec, exportedAt: 0);
      final data = {...empty.data}
        ..remove('beverages')
        ..remove('drinkRecords');
      final old = validateBackup({
        ...(empty.toJson()..remove('plugins')),
        'version': 6,
        'schemaVersion': 8,
        'data': data,
      });
      await repo.saveRecord(drink(), newBeverage: beverage());
      final preview = await inspectBackup(exec, old);
      expect(preview.incoming.hasBeverages, isFalse);
      await restoreBackup(exec, preview);
      expect((await repo.records()).length, 1);
      await restoreBackup(exec, await inspectBackup(exec, empty));
      expect(await repo.library(), isEmpty);
      expect(await repo.records(), isEmpty);
    },
  );
  test('v7 missing arrays corrupt snapshots or dangling refs rejected before writing', () async {
    await repo.saveRecord(drink(), newBeverage: beverage());
    final backup = await exportBackup(exec, exportedAt: 0);
    final missing = {...backup.data}..remove('beverages');
    expect(
      () => validateBackup({...backup.toJson(), 'data': missing}),
      throwsA(isA<BackupValidationException>()),
    );
    final badPayload = jsonEncode({...drink().toJson(), 'calories': '0/1'});
    expect(
      () => validateBackup({
        ...backup.toJson(),
        'data': {
          ...backup.data,
          'drinkRecords': [
            {...backup.rows('drinkRecords').single, 'payload': badPayload},
          ],
        },
      }),
      throwsA(isA<BackupValidationException>()),
    );
    expect(
      () => validateBackup({
        ...backup.toJson(),
        'data': {...backup.data, 'beverages': []},
      }),
      throwsA(isA<BackupValidationException>()),
    );
  });
  test(
    'restoring beverage write failure rolls training and drinks back',
    () async {
      final empty = await exportBackup(exec, exportedAt: 0);
      await repo.saveRecord(drink(), newBeverage: beverage());
      final full = await exportBackup(exec, exportedAt: 0);
      await restoreBackup(exec, await inspectBackup(exec, empty));
      await exec.run("INSERT INTO session(id,started_at) VALUES('local',123)");
      final preview = await inspectBackup(exec, full);
      await expectLater(
        restoreBackup(
          FailingExecutor(
            exec,
            'INSERT INTO drink_record',
            StateError('injected'),
          ),
          preview,
        ),
        throwsStateError,
      );
      expect(await repo.library(), isEmpty);
      expect(
        (await exec.all<Map<String, Object?>>('SELECT id FROM session'))
            .single['id'],
        'local',
      );
    },
  );
}
