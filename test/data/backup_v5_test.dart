import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/repositories/backup_repo.dart';
import 'package:gym_tracker/domain/backup.dart';
import 'package:gym_tracker/domain/backup_upgrade.dart';

import 'backup_v4_test.dart' show v4Fixture;
import 'backup_repo_test.dart' show FailingExecutor;

Map<String, dynamic> fixture() =>
    jsonDecode(jsonEncode(upgradeBackupToV5(v4Fixture())))
        as Map<String, dynamic>;

void main() {
  test('v4 upgrade preserves native weights, preferences and snapshots', () {
    final old = validateBackup(v4Fixture());
    final upgraded = validateBackup(fixture());
    expect(upgraded.version, 5);
    expect(upgraded.schemaVersion, 7);
    for (final key in ['sets', 'exercisePreferences', 'sessions']) {
      expect(upgraded.rows(key), old.rows(key));
    }
    expect(
      upgraded.rows('templates').every((r) => r['kind'] == 'training'),
      isTrue,
    );
    expect(
      upgraded.rows('plans').every((r) => r['activatedOn'] == null),
      isTrue,
    );
    expect(upgradeBackupToV5(upgraded.toJson()), upgraded.toJson());
  });
  for (final invalid in [
    '2026-02-29',
    '2026-1-01',
    '2026-01-01\n',
    '',
    '2026-13-01',
  ]) {
    test('rejects invalid activation $invalid', () {
      final raw = fixture();
      raw['data']['plans'][0]['activatedOn'] = invalid;
      expect(
        () => validateBackup(raw),
        throwsA(isA<BackupValidationException>()),
      );
    });
  }
  test('rejects bad kind, rest exercises and orphan references separately', () {
    final badKind = fixture();
    badKind['data']['templates'][0]['kind'] = 'off';
    expect(
      () => validateBackup(badKind),
      throwsA(isA<BackupValidationException>()),
    );
    final restActions = fixture();
    restActions['data']['templates'][0]['kind'] = 'rest';
    expect(
      () => validateBackup(restActions),
      throwsA(isA<BackupValidationException>()),
    );
    final orphan = fixture();
    orphan['data']['templates'][0]['planId'] = 'missing';
    expect(
      () => validateBackup(orphan),
      throwsA(isA<BackupValidationException>()),
    );
  });
  test('historical sessions may refer to a day changed into rest', () {
    final raw = fixture();
    final id = raw['data']['sessions'][0]['templateId'];
    raw['data']['templates'].firstWhere((r) => r['id'] == id)['kind'] = 'rest';
    raw['data']['templateExercises'].removeWhere((r) => r['templateId'] == id);
    expect(validateBackup(raw).rows('sessions')[0]['templateId'], id);
  });
  test('v5 round trip and failed restore retain complete data', () async {
    final db = await FfiExecutor.openMigrated();
    addTearDown(db.close);
    final raw = fixture();
    raw['data']['templates'].last['kind'] = 'rest';
    raw['data']['plans'].last['activatedOn'] = '2026-10-18';
    final incoming = validateBackup(raw);
    await restoreBackup(db, await inspectBackup(db, incoming));
    final exported = await exportBackup(db, exportedAt: 9);
    for (final key in incoming.data.keys) {
      expect(exported.rows(key), incoming.rows(key), reason: key);
    }
    expect(exported.rows('settings'), isEmpty);
    final preview = await inspectBackup(db, incoming);
    await expectLater(
      restoreBackup(
        FailingExecutor(db, 'INSERT INTO split_template', StateError('fault')),
        preview,
      ),
      throwsStateError,
    );
    expect((await exportBackup(db, exportedAt: 9)).toJson(), exported.toJson());
  });
}
