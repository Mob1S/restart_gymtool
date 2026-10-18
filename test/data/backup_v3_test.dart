import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/repositories/backup_repo.dart';
import 'package:gym_tracker/data/repositories/exercise_preferences_repo.dart';
import 'package:gym_tracker/data/repositories/settings_repo.dart';
import 'package:gym_tracker/domain/backup.dart';

import '../support/workout_fixture.dart';
import 'backup_repo_test.dart' show loadFixture;

// Exercise the published v3 validator independently of today's export version.
Map<String, dynamic> legacyV3(BackupFile backup) {
  final raw = jsonDecode(jsonEncode(backup.toJson())) as Map<String, dynamic>;
  raw['version'] = 3;
  raw['schemaVersion'] = 5;
  final data = raw['data'] as Map<String, dynamic>;
  data.remove('plans');
  for (final row in data['templates'] as List) {
    (row as Map).remove('planId');
  }
  for (final row in data['sessions'] as List) {
    for (final key in [
      'planId',
      'planNameSnapshot',
      'dayNameSnapshot',
      'origin',
    ]) {
      (row as Map).remove(key);
    }
  }
  for (final row in data['sets'] as List) {
    (row as Map).remove('sourceWeight');
    row.remove('sourceUnit');
  }
  data['exercisePreferences'] = [
    for (final row in data['exercisePreferences'] as List)
      {
        'exerciseId': row['exerciseId'],
        'weightStepMilli': (double.parse(row['kgStep'] as String) * 1000)
            .round(),
        'isFavorite': row['isFavorite'],
        'equipmentNote': row['equipmentNote'],
      },
  ];
  return raw;
}

void main() {
  test('current exact round trip contains Unicode preferences and prepared active weight', () async {
    final f = await workoutFixture();
    final p = (await readExercisePreferences(f.db, [f.benchId]))[f.benchId]!;
    await saveExercisePreference(
      f.db,
      f.benchId,
      expectedToken: p.token,
      weightStepMilli: 1250,
      isFavorite: true,
      equipmentNote: '座椅4\n😀',
    );
    await f.controller.completeCurrentSet(40, 8);
    final pending = f.controller.currentExercise!.sets.last;
    f.controller.stagePendingWeight(pending.id, 42.5);
    await f.controller.flushPendingWeight();
    final backup = await exportBackup(f.db, exportedAt: 0);
    expect(backup.version, 6);
    expect(backup.schemaVersion, 8);
    final other = await FfiExecutor.openMigrated();
    addTearDown(other.close);
    await restoreBackup(other, await inspectBackup(other, backup));
    expect((await exportBackup(other, exportedAt: 0)).data, backup.data);
    expect(
      backup.rows('exercisePreferences').single['equipmentNote'],
      '座椅4\n😀',
    );
  });
  for (final legacy in ['legacy-v1', 'legacy-v2']) {
    test(
      '$legacy clears exercise preferences while preserving missing theme settings',
      () async {
        final f = await workoutFixture();
        final p = (await readExercisePreferences(f.db, [
          f.benchId,
        ]))[f.benchId]!;
        await saveExercisePreference(
          f.db,
          f.benchId,
          expectedToken: p.token,
          isFavorite: true,
        );
        await setSetting(f.db, 'theme_mode', 'dark');
        await restoreBackup(
          f.db,
          await inspectBackup(f.db, loadFixture(legacy)),
        );
        expect(await f.db.all('SELECT * FROM exercise_preference'), isEmpty);
        expect(await getSetting(f.db, 'theme_mode'), 'dark');
      },
    );
  }
  for (final (label, mutate) in <(String, void Function(Map<String, dynamic>))>[
    (
      'missing preferences',
      (m) => (m['data'] as Map).remove('exercisePreferences'),
    ),
    (
      'orphan',
      (m) => m['data']['exercisePreferences'][0]['exerciseId'] = 'absent',
    ),
    (
      'duplicate',
      (m) => m['data']['exercisePreferences'].add(
        m['data']['exercisePreferences'][0],
      ),
    ),
    (
      'bad step',
      (m) => m['data']['exercisePreferences'][0]['weightStepMilli'] = 1251,
    ),
    (
      'number bool',
      (m) => m['data']['exercisePreferences'][0]['isFavorite'] = 1,
    ),
    (
      'long Unicode note',
      (m) => m['data']['exercisePreferences'][0]['equipmentNote'] = '😀' * 501,
    ),
    ('v3 old schema', (m) => m['schemaVersion'] = 4),
    ('v2 new schema', (m) => m['version'] = 2),
  ]) {
    test('rejects v3 $label before any write', () async {
      final f = await workoutFixture();
      final p = (await readExercisePreferences(f.db, [f.benchId]))[f.benchId]!;
      await saveExercisePreference(
        f.db,
        f.benchId,
        expectedToken: p.token,
        isFavorite: true,
      );
      final before = (await exportBackup(f.db, exportedAt: 0)).toJson();
      final raw = legacyV3(validateBackup(before));
      mutate(raw);
      expect(
        () => validateBackup(raw),
        throwsA(isA<BackupValidationException>()),
      );
      expect((await exportBackup(f.db, exportedAt: 0)).toJson(), before);
    });
  }
}
