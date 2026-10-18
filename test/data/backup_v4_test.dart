import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/repositories/backup_repo.dart';
import 'package:gym_tracker/data/repositories/set_repo.dart';
import 'package:gym_tracker/data/repositories/settings_repo.dart';
import 'package:gym_tracker/domain/backup.dart';
import 'package:gym_tracker/domain/backup_codec.dart';
import 'package:gym_tracker/domain/backup_upgrade.dart';

import 'backup_repo_test.dart' show loadFixture, FailingExecutor;

Map<String, dynamic> v4Fixture() {
  final raw = jsonDecode(
    jsonEncode(upgradeBackupToV4(loadFixture().toJson())),
  ) as Map<String, dynamic>;
  final data = raw['data'] as Map<String, dynamic>;
  data['plans'].add({
    'id': 'second-plan',
    'name': '两日计划',
    'position': 1,
    'createdAt': 5,
  });
  data['templates'].addAll([
    {
      'id': 'day-a',
      'planId': 'second-plan',
      'name': '全身 A',
      'position': 0,
      'createdAt': 6,
    },
    {
      'id': 'day-b',
      'planId': 'second-plan',
      'name': '全身 B',
      'position': 1,
      'createdAt': 6,
    },
  ]);
  data['sessions'][0]['origin'] = 'live';
  data['sessions'][0]['planNameSnapshot'] = '保留开训计划名称';
  data['sessions'][0]['dayNameSnapshot'] = '保留开训训练日名称';
  data['sets'][0]['weight'] = 22.6796185;
  data['sets'][0]['sourceWeight'] = '50';
  data['sets'][0]['sourceUnit'] = 'lb';
  data['exercisePreferences'] = [
    {
      'exerciseId': 'custom-e',
      'weightUnit': 'lb',
      'kgStep': '1.25',
      'lbStep': '0.125',
      'showKgEquivalent': true,
      'isFavorite': true,
      'equipmentNote': '座椅 4\n😀',
    },
  ];
  return raw;
}

void main() {
  group('v4 pure validation', () {
    test(
      'a training day requires an existing parent even without workout records',
      () {
        final raw = <String, dynamic>{
          'format': 'gym-tracker-backup',
          'version': 4,
          'schemaVersion': 6,
          'exportedAt': 0,
          'data': <String, dynamic>{
            'exercises': [],
            'plans': [
              {'id': 'plan', 'name': '计划', 'position': 0, 'createdAt': 0},
            ],
            'templates': [
              {
                'id': 'day',
                'planId': 'plan',
                'name': '训练日',
                'position': 0,
                'createdAt': 0,
              },
            ],
            'templateExercises': [],
            'sessions': [],
            'sessionExercises': [],
            'sets': [],
            'exercisePreferences': [],
            'settings': [],
          },
        };
        expect(validateBackup(raw).rows('templates'), hasLength(1));
        raw['data']['templates'][0]['planId'] = 'missing-parent';
        expect(
          () => validateBackup(raw),
          throwsA(isA<BackupValidationException>()),
        );
      },
    );
    test(
      'preserves parents, source values, custom preferences and immutability',
      () {
        final backup = validateBackup(v4Fixture());
        expect(backup.version, 4);
        expect(backup.rows('plans'), hasLength(2));
        expect(backup.rows('templates'), hasLength(3));
        expect(decodeBackup(encodeBackup(backup)).toJson(), backup.toJson());
        expect(
          () => backup.rows('plans').first['name'] = 'changed',
          throwsUnsupportedError,
        );
      },
    );
    for (final (label, change)
        in <(String, void Function(Map<String, dynamic>))>[
          ('missing plans', (m) => (m['data'] as Map).remove('plans')),
          (
            'duplicate parent',
            (m) => m['data']['plans'].add(m['data']['plans'][0]),
          ),
          (
            'orphan parent',
            (m) => m['data']['templates'][0]['planId'] = 'absent',
          ),
          (
            'null day parent',
            (m) => m['data']['templates'][0]['planId'] = null,
          ),
          (
            'orphan session parent',
            (m) => m['data']['sessions'][0]['planId'] = 'absent',
          ),
          (
            'cross-parent day',
            (m) => m['data']['sessions'][0]['planId'] = 'second-plan',
          ),
          (
            'missing session parent',
            (m) => m['data']['sessions'][0]['planId'] = null,
          ),
          (
            'unknown origin',
            (m) => m['data']['sessions'][0]['origin'] = 'other',
          ),
          (
            'bad source unit',
            (m) => m['data']['sets'][0]['sourceUnit'] = 'stone',
          ),
          (
            'missing lb source',
            (m) => m['data']['sets'][0]['sourceWeight'] = null,
          ),
          (
            'negative reading',
            (m) => m['data']['sets'][0]['sourceWeight'] = '-50',
          ),
          (
            'nonfinite reading',
            (m) => m['data']['sets'][0]['sourceWeight'] = 'Infinity',
          ),
          ('numeric source', (m) => m['data']['sets'][0]['sourceWeight'] = 50),
          ('inconsistent kg', (m) => m['data']['sets'][0]['weight'] = 50),
          ('rounded kg', (m) => m['data']['sets'][0]['weight'] = 22.68),
          (
            'bad preference unit',
            (m) => m['data']['exercisePreferences'][0]['weightUnit'] = 'stone',
          ),
          (
            'zero step',
            (m) => m['data']['exercisePreferences'][0]['kgStep'] = '0',
          ),
          (
            'negative step',
            (m) => m['data']['exercisePreferences'][0]['lbStep'] = '-1',
          ),
          (
            'nonfinite step',
            (m) => m['data']['exercisePreferences'][0]['lbStep'] = 'NaN',
          ),
          (
            'numeric step',
            (m) => m['data']['exercisePreferences'][0]['kgStep'] = 2.5,
          ),
          (
            'numeric switch',
            (m) => m['data']['exercisePreferences'][0]['showKgEquivalent'] = 1,
          ),
          (
            'missing source field',
            (m) => (m['data']['sets'][0] as Map).remove('sourceWeight'),
          ),
          ('wrong schema', (m) => m['schemaVersion'] = 5),
          ('future format', (m) => m['version'] = 5),
        ]) {
      test('rejects $label', () {
        final raw = v4Fixture();
        change(raw);
        expect(
          () => validateBackup(raw),
          throwsA(isA<BackupValidationException>()),
        );
      });
    }
    test('only kg legacy rows allow a missing source reading; tiny numeric error is tolerated', () {
      final raw = v4Fixture();
      raw['data']['sets'][0]['weight'] = 22.6796185 + 1e-10;
      expect(validateBackup(raw).rows('sets'), hasLength(2));
      raw['data']['sets'][0]['sourceWeight'] = null;
      raw['data']['sets'][0]['sourceUnit'] = 'kg';
      expect(validateBackup(raw).rows('sets').first['sourceWeight'], isNull);
    });
    test('parent rows count toward the record limit', () {
      final raw = v4Fixture();
      raw['data']['plans'] = List.generate(
        maxBackupRecords,
        (i) => {'id': 'parent-$i', 'name': '计划', 'position': i, 'createdAt': 0},
      );
      expect(
        () => validateBackup(raw),
        throwsA(isA<BackupValidationException>()),
      );
    });
    test('source text counts toward encoded byte limit', () {
      final raw = v4Fixture();
      raw['data']['plans'][0]['name'] = 'a' * maxBackupBytes;
      expect(
        () => encodeBackup(validateBackup(raw)),
        throwsA(isA<BackupValidationException>()),
      );
    });
  });

  for (final version in [1, 2, 3]) {
    test(
      'legacy v$version upgrades deterministically, preserves missing settings and validates first',
      () {
        final raw = jsonDecode(
          jsonEncode(
            loadFixture(version == 1 ? 'legacy-v1' : 'legacy-v2').toJson(),
          ),
        ) as Map<String, dynamic>;
        if (version == 3) {
          raw['version'] = 3;
          raw['schemaVersion'] = 5;
          raw['data']['exercisePreferences'] = [
            {
              'exerciseId': 'custom-e',
              'weightStepMilli': 1250,
              'isFavorite': true,
              'equipmentNote': '保留',
            },
          ];
        }
        final first = upgradeBackupToV4(raw);
        expect(upgradeBackupToV4(raw), first);
        final backup = validateBackup(first);
        expect(backup.hasSettings, false);
        expect(backup.rows('plans'), hasLength(version == 1 ? 0 : 1));
        expect(backup.rows('sessions').last['planId'], isNull);
        expect(backup.rows('sessions').last['dayNameSnapshot'], isNull);
        expect(
          backup.rows('sessions').every((r) => r['origin'] == 'legacy'),
          true,
        );
        if (version == 3) {
          expect(backup.rows('exercisePreferences').single['kgStep'], '1.25');
          expect(backup.rows('exercisePreferences').single['lbStep'], '5');
        }
        raw['data']['sets'][0]['weight'] = -1;
        expect(
          () => upgradeBackupToV4(raw),
          throwsA(isA<BackupValidationException>()),
        );
      },
    );
  }
  test('legacy generated parent IDs avoid every existing record ID', () {
    final raw =
        jsonDecode(jsonEncode(loadFixture().toJson())) as Map<String, dynamic>;
    raw['data']['sets'][0]['id'] = 'legacy-training-plan';
    raw['data']['sets'][1]['id'] = 'legacy-training-plan-1';
    final upgraded = validateBackup(upgradeBackupToV4(raw));
    expect(upgraded.rows('plans').single['id'], 'legacy-training-plan-2');
  });

  group('v4 actual database', () {
    late FfiExecutor db;
    setUp(() async => db = await FfiExecutor.openMigrated());
    tearDown(() async => db.close());
    test(
      'native lb and all plan levels survive exact DB and byte round trips',
      () async {
        await setSetting(db, 'theme_mode', 'dark');
        final incoming = validateBackup(v4Fixture());
        final preview = await inspectBackup(db, incoming);
        expect(preview.incoming.version, 5);
        await restoreBackup(db, preview);
        final first = await exportBackup(db, exportedAt: 123);
        expect(
          first.rows('plans'),
          validateBackup(upgradeBackupToV5(incoming.toJson())).rows('plans'),
        );
        expect(
          first.rows('exercisePreferences'),
          incoming.rows('exercisePreferences'),
        );
        expect(
          (await listSets(db, 'se')).single.equipmentWeight.label,
          '50 lb',
        );
        expect((await listSets(db, 'se')).single.weight, 22.6796185);
        final other = await FfiExecutor.openMigrated();
        addTearDown(other.close);
        await restoreBackup(
          other,
          await inspectBackup(other, decodeBackup(encodeBackup(first))),
        );
        expect(
          (await exportBackup(other, exportedAt: 123)).toJson(),
          first.toJson(),
        );
        expect(await other.all('PRAGMA foreign_key_check'), isEmpty);
        expect(await getSetting(db, 'theme_mode'), 'dark');
      },
    );
    test('source-only edit invalidates restore preview even with unchanged kg/count', () async {
      final source = validateBackup(v4Fixture());
      await restoreBackup(db, await inspectBackup(db, source));
      final preview = await inspectBackup(db, source);
      await db.run(
        "UPDATE set_entry SET source_weight='22.6796185', source_unit='kg' WHERE id='done'",
      );
      await expectLater(
        restoreBackup(db, preview),
        throwsA(isA<BackupValidationException>()),
      );
      expect((await listSets(db, 'se')).single.equipmentWeight.unit.name, 'kg');
    });
    for (final after in [
      'DELETE FROM training_plan',
      'INSERT INTO training_plan',
      'INSERT INTO exercise_preference',
    ]) {
      test(
        'failure after $after rolls back every new field and table',
        () async {
          final source = validateBackup(v4Fixture());
          await restoreBackup(db, await inspectBackup(db, source));
          final before = (await exportBackup(db, exportedAt: 0)).toJson();
          final failure = StateError('injected');
          final faulty = FailingExecutor(db, after, failure);
          await expectLater(
            restoreBackup(faulty, await inspectBackup(faulty, source)),
            throwsA(same(failure)),
          );
          expect((await exportBackup(db, exportedAt: 0)).toJson(), before);
        },
      );
    }
  });
}
