import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/domain/backup.dart';
import 'package:gym_tracker/domain/backup_codec.dart';

Map<String, dynamic> fixture([String name = 'legacy-v2']) =>
    jsonDecode(File('test/fixtures/backup/$name.json').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  test(
    'v1 restores missing plans and templateId without inventing preferences',
    () {
      final backup = validateBackup(fixture('legacy-v1'));
      expect(backup.rows('templates'), isEmpty);
      expect(backup.rows('sessions').single['templateId'], isNull);
      expect(backup.hasSettings, isFalse);
    },
  );
  test('legacy v2 keeps nonempty plans, active training and pending sets', () {
    final backup = validateBackup(fixture());
    expect(backup.rows('templates').single['name'], '推日');
    expect(backup.rows('sets').last['isCompleted'], false);
    expect(backup.activeSessions, 1);
    expect(backup.completedSessions, 1);
    expect(backup.hasSettings, false);
  });
  test(
    'current settings and immutable normalized data survive a byte round trip',
    () {
      final backup = validateBackup(fixture('current-v2'));
      expect(backup.hasSettings, true);
      expect(decodeBackup(encodeBackup(backup)).toJson(), backup.toJson());
      expect(
        () => backup.rows('settings').single['value'] = 'light',
        throwsUnsupportedError,
      );
      expect(() => backup.rows('sets').clear(), throwsUnsupportedError);
    },
  );
  for (final (label, patch) in <(String, void Function(Map<String, dynamic>))>[
    ('future format', (m) => m['version'] = 4),
    ('future schema', (m) => m['schemaVersion'] = 5),
    ('wrong app', (m) => m['format'] = 'other'),
    ('missing array', (m) => (m['data'] as Map).remove('sets')),
    ('null plans', (m) => m['data']['templates'] = null),
    ('duplicate ID', (m) => m['data']['sets'].add(m['data']['sets'][0])),
    (
      'orphan set',
      (m) => m['data']['sets'][0]['sessionExerciseId'] = 'missing',
    ),
    ('orphan plan', (m) => m['data']['sessions'][0]['templateId'] = 'missing'),
    (
      'orphan plan exercise',
      (m) => m['data']['templateExercises'][0]['exerciseId'] = 'missing',
    ),
    (
      'number pretending to be bool',
      (m) => m['data']['sets'][0]['isCompleted'] = 1,
    ),
    ('negative weight', (m) => m['data']['sets'][0]['weight'] = -1),
    (
      'nonfinite weight',
      (m) => m['data']['sets'][0]['weight'] = double.infinity,
    ),
    ('fractional reps', (m) => m['data']['sets'][0]['reps'] = 1.5),
    ('oversized timestamp', (m) => m['exportedAt'] = 8640000000000001),
    (
      'missing nullable field',
      (m) => (m['data']['sessions'][0] as Map).remove('note'),
    ),
    (
      'two active workouts',
      (m) => m['data']['sessions'][0]['finishedAt'] = null,
    ),
  ]) {
    test('reject $label', () {
      final raw = fixture();
      patch(raw);
      expect(
        () => validateBackup(raw),
        throwsA(isA<BackupValidationException>()),
      );
    });
  }
  test('BOM is accepted, malformed UTF8 and JSON are rejected', () {
    final data = utf8.encode(jsonEncode(fixture()));
    expect(
      decodeBackup([0xef, 0xbb, 0xbf, ...data]).rows('sets'),
      hasLength(2),
    );
    for (final bytes in [
      [0xff],
      utf8.encode('this is definitely not json'),
      utf8.encode('{"hello":1}'),
    ]) {
      expect(
        () => decodeBackup(bytes),
        throwsA(isA<BackupValidationException>()),
      );
    }
  });
  test('input has a bounded byte size before JSON decoding', () {
    expect(
      () => decodeBackup(List.filled(maxBackupBytes + 1, 32)),
      throwsA(isA<BackupValidationException>()),
    );
  });
  test('unknown fields are removed, duplicate setting keys are rejected', () {
    final raw = fixture('current-v2');
    raw['data']['untrusted'] = 'DROP TABLE exercise';
    expect(validateBackup(raw).toJson()['data'], isNot(contains('untrusted')));
    raw['data']['settings'].add({'key': 'theme_mode', 'value': 'light'});
    expect(
      () => validateBackup(raw),
      throwsA(isA<BackupValidationException>()),
    );
  });
}
