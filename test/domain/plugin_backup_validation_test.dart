import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/domain/backup.dart';
import 'package:gym_tracker/domain/backup_codec.dart';
import 'package:gym_tracker/domain/backup_upgrade.dart';

import '../data/backup_repo_test.dart' show loadFixture;

Map<String, Object?> v8([Object? plugins = const <String, Object?>{}]) {
  final source = upgradeBackupToV6(loadFixture('current-v2').toJson());
  return {
    ...source,
    'version': 8,
    'schemaVersion': 12,
    'data': {...source['data'] as Map, 'beverages': [], 'drinkRecords': []},
    'plugins': plugins,
  };
}

void main() {
  test(
    'v8 requires plugins and exactly schema 12; legacy rejects extensions',
    () {
      final raw = v8();
      expect(validateBackup(raw).version, 8);
      expect(
        () => validateBackup({...raw}..remove('plugins')),
        throwsA(isA<BackupValidationException>()),
      );
      expect(
        () => validateBackup({...raw, 'schemaVersion': 11}),
        throwsA(isA<BackupValidationException>()),
      );
      expect(
        () => validateBackup({...raw, 'version': 7, 'schemaVersion': 11}),
        throwsA(isA<BackupValidationException>()),
      );
    },
  );
  test('unknown plugins retain immutable nested values and empty versions', () {
    final raw = v8({
      'community.example': {
        'dataVersion': 2,
        'records': [
          {
            'key': 'preferences',
            'value': {
              'nested': [null, true, 1, '中文'],
            },
          },
        ],
      },
      'community.empty': {'dataVersion': 3, 'records': []},
    });
    final b = decodeBackup(encodeBackup(validateBackup(raw)));
    expect(b.plugins!['community.empty']!.dataVersion, 3);
    expect(b.plugins!['community.example']!.records['preferences'], {
      'nested': [null, true, 1, '中文'],
    });
    expect(
      () =>
          (b.plugins!['community.example']!.records['preferences']
                  as Map)['new'] =
              1,
      throwsUnsupportedError,
    );
  });
  for (final invalid in [
    {
      'gym.calories': {'dataVersion': 1, 'records': []},
    },
    {
      'community.example': {'dataVersion': 0, 'records': []},
    },
    {
      'community.example': {'dataVersion': 1.5, 'records': []},
    },
    {
      'community.example': {
        'dataVersion': 1,
        'records': [
          {'key': 'x', 'value': 0},
          {'key': 'x', 'value': 1},
        ],
      },
    },
    {
      'community.example': {
        'dataVersion': 1,
        'records': [
          {'key': 'x', 'value': double.nan},
        ],
      },
    },
  ]) {
    test(
      'reject illegal extension $invalid',
      () => expect(
        () => validateBackup(v8(invalid)),
        throwsA(isA<BackupValidationException>()),
      ),
    );
  }
  test('extension nesting and records share limits', () {
    Object? nested = 0;
    for (var i = 0; i < 33; i++) {
      nested = [nested];
    }
    expect(
      () => validateBackup(
        v8({
          'community.example': {
            'dataVersion': 1,
            'records': [
              {'key': 'x', 'value': nested},
            ],
          },
        }),
      ),
      throwsA(isA<BackupValidationException>()),
    );
    expect(
      () => validateBackup(
        v8({
          'community.example': {
            'dataVersion': 1,
            'records': List.generate(
              100001,
              (i) => {'key': '$i', 'value': null},
            ),
          },
        }),
      ),
      throwsA(isA<BackupValidationException>()),
    );
  });
  test('encoded JSON duplicate namespace IDs and nested keys are rejected', () {
    final text = jsonEncode(v8());
    for (final replacement in [
      '{"community.x":{"dataVersion":1,"records":[]},"community.x":{"dataVersion":1,"records":[]}}',
      '{"community.x":{"dataVersion":1,"records":[{"key":"x","value":{"a":1,"a":2}}]}}',
    ]) {
      expect(
        () => decodeBackup(
          utf8.encode(
            text.replaceFirst('"plugins":{}', '"plugins":$replacement'),
          ),
        ),
        throwsA(isA<BackupValidationException>()),
      );
    }
  });
}
