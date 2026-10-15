import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/files/backup_file_store.dart';
import 'package:gym_tracker/domain/backup.dart';

void main() {
  test('known oversize never subscribes to stream', () async {
    var read = false;
    Stream<List<int>> source() async* {
      read = true;
      yield [1];
    }

    await expectLater(
      readBoundedBackup('large', source(), reportedLength: maxBackupBytes + 1),
      throwsA(isA<BackupValidationException>()),
    );
    expect(read, isFalse);
  });
  test('unknown oversize stops consuming immediately', () async {
    var continued = false;
    Stream<List<int>> source() async* {
      yield Uint8List(maxBackupBytes);
      yield [1];
      continued = true;
      yield [2];
    }

    await expectLater(
      readBoundedBackup('large', source()),
      throwsA(isA<BackupValidationException>()),
    );
    expect(continued, isFalse);
  });
  test('exact limit and empty file are readable', () async {
    expect(
      (await readBoundedBackup(
        'exact',
        Stream.value(Uint8List(maxBackupBytes)),
      )).bytes.length,
      maxBackupBytes,
    );
    expect(
      (await readBoundedBackup(
        'empty',
        const Stream.empty(),
        reportedLength: 0,
      )).bytes,
      isEmpty,
    );
  });
  test('picker cancellation returns null', () async {
    expect(
      await PlatformBackupFileStore(choose: () async => null).pick(),
      isNull,
    );
  });
  test('picker exception is translated', () async {
    await expectLater(
      PlatformBackupFileStore(choose: () async => throw StateError('access'))
          .pick(),
      throwsA(
        isA<BackupValidationException>().having(
          (e) => e.message,
          'message',
          contains('无法读取'),
        ),
      ),
    );
  });
  test(
    'stream error is translated and does not return partial bytes',
    () async {
      Stream<List<int>> source() async* {
        yield [1];
        throw StateError('read');
      }

      await expectLater(
        readBoundedBackup('bad', source()),
        throwsA(
          isA<BackupValidationException>().having(
            (e) => e.message,
            'message',
            contains('无法读取'),
          ),
        ),
      );
    },
  );
  for (final (web, uri, result) in [
    (false, Uri.parse('content://backup/1'), BackupSaveResult.saved),
    (false, null, BackupSaveResult.canceled),
    (true, null, BackupSaveResult.downloadRequested),
  ]) {
    test('save web=$web uri=$uri returns $result', () async {
      final store = PlatformBackupFileStore(
        web: web,
        write: (name, bytes) async {
          expect(name, 'backup.json');
          expect(bytes, [1, 2]);
          return uri;
        },
      );
      expect(await store.save('backup.json', [1, 2]), result);
    });
  }
  test('save error and oversize cannot report success', () async {
    var writes = 0;
    final store = PlatformBackupFileStore(
      write: (_, _) async {
        writes++;
        throw StateError('disk');
      },
    );
    await expectLater(
      store.save('large', Uint8List(maxBackupBytes + 1)),
      throwsA(isA<BackupValidationException>()),
    );
    expect(writes, 0);
    await expectLater(
      store.save('small', [1]),
      throwsA(
        isA<BackupValidationException>().having(
          (e) => e.message,
          'message',
          contains('无法保存'),
        ),
      ),
    );
    expect(writes, 1);
  });
}
