import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/domain/backup.dart';

import 'backup_test.dart' show fixture;

void main() {
  test('total record limit is checked before processing any row', () {
    final raw = fixture();
    raw['data']['sets'] = List.filled(100001, null);
    raw['data']['exercises'][0]['id'] = ' ';
    expect(
      () => validateBackup(raw),
      throwsA(
        isA<BackupValidationException>().having(
          (e) => e.message,
          'message',
          contains('100,000'),
        ),
      ),
    );
  });
  for (final root in [null, <Object?>[]]) {
    test('nonobject root $root has path', () {
      expect(
        () => validateBackup(root),
        throwsA(
          isA<BackupValidationException>().having(
            (e) => e.message,
            'message',
            contains('备份 必须是对象'),
          ),
        ),
      );
    });
  }
  for (final (table, field, value) in <(String, String, Object?)>[
    ('exercises', 'id', ' '),
    ('sessions', 'note', 1),
    ('sessions', 'finishedAt', 'bad'),
    ('sets', 'position', -1),
    ('sets', 'reps', -1),
    ('sets', 'restSeconds', -1),
    ('sets', 'restStartedAt', 1.5),
    ('exercises', 'isArchived', 0),
  ]) {
    test('reject $table.$field=$value with field path', () {
      final raw = fixture();
      raw['data'][table][0][field] = value;
      expect(
        () => validateBackup(raw),
        throwsA(
          isA<BackupValidationException>().having(
            (e) => e.message,
            'message',
            contains('data.$table 第 1 条 的 $field'),
          ),
        ),
      );
    });
  }
  test('empty backup, zero pending set, empty training remain valid', () {
    expect(validateBackup(fixture('current-v2')).rows('sessions'), isEmpty);
    final raw = fixture();
    raw['data']['sets'][1]['weight'] = 0;
    raw['data']['sets'][1]['reps'] = 0;
    raw['data']['sessions'].add({
      'id': 'empty',
      'name': null,
      'startedAt': 0,
      'finishedAt': 1,
      'note': null,
      'templateId': null,
    });
    final backup = validateBackup(raw);
    expect(backup.rows('sets').last['reps'], 0);
    expect(backup.rows('sessions'), hasLength(3));
  });
  test('absent settings differs from present empty settings', () {
    final raw = fixture();
    expect(validateBackup(raw).hasSettings, isFalse);
    raw['data']['settings'] = [];
    expect(validateBackup(raw).hasSettings, isTrue);
  });
}
