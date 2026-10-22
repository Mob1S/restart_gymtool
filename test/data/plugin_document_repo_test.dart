import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/repositories/plugin_document_repo.dart';
import 'package:gym_tracker/data/repositories/backup_repo.dart';
import 'package:gym_tracker/domain/backup.dart';
import 'package:gym_tracker/domain/backup_codec.dart';

void main() {
  late FfiExecutor exec;
  late PluginDocumentRepo repo;
  setUp(() async {
    exec = await FfiExecutor.openMigrated();
    repo = PluginDocumentRepo(exec);
  });
  tearDown(() => exec.close());
  test('same key is isolated by namespace and accepts JSON null', () async {
    await repo.write('community.one', 'preferences', {'unit': 'kg'});
    await repo.write('community.two', 'preferences', null, dataVersion: 2);
    expect(await repo.read('community.one', 'preferences'), {'unit': 'kg'});
    expect(await repo.readAll('community.two'), {'preferences': null});
    expect(await repo.dataVersion('community.two'), 2);
  });
  test('batch failure and mismatched versions roll back all writes', () async {
    await expectLater(
      repo.transaction((tx) async {
        await tx.write('community.one', 'first', true);
        await tx.write('community.one', 'second', double.nan);
      }),
      throwsFormatException,
    );
    expect(await repo.readAll('community.one'), isEmpty);
    expect(await repo.dataVersion('community.one'), isNull);
    await repo.write('community.one', 'first', 1, dataVersion: 2);
    await expectLater(
      repo.write('community.one', 'second', 2),
      throwsStateError,
    );
    expect(await repo.readAll('community.one'), {'first': 1});
  });
  test(
    'a private document exceeding the combined backup budget rolls back',
    () async {
      await repo.write('community.one', 'first', 1);
      await expectLater(
        repo.write('community.one', 'huge', 'x' * maxBackupBytes),
        throwsA(isA<BackupValidationException>()),
      );
      expect(await repo.readAll('community.one'), {'first': 1});
    },
  );
  test('byte boundary reserves the full valid export timestamp width', () async {
    await repo.write('community.one', 'boundary', '');
    final zeroSize = encodeBackup(await exportBackup(exec, exportedAt: 0))
        .length;
    // This value previously committed at exactly 20 MiB using exportedAt:0,
    // but a normal millisecond timestamp made its next export exceed the limit.
    await expectLater(
      repo.write(
        'community.one',
        'boundary',
        'x' * (maxBackupBytes - zeroSize),
      ),
      throwsA(isA<BackupValidationException>()),
    );
    expect(await repo.read('community.one', 'boundary'), '');

    final reservedSize = encodeBackup(
      await exportBackup(exec, exportedAt: maxBackupTimestamp),
    ).length;
    await repo.write(
      'community.one',
      'boundary',
      'x' * (maxBackupBytes - reservedSize),
    );
    expect(
      encodeBackup(await exportBackup(exec, exportedAt: maxBackupTimestamp))
          .length,
      maxBackupBytes,
    );
    expect(
      encodeBackup(await exportBackup(exec, exportedAt: 1792530000000)).length,
      lessThanOrEqualTo(maxBackupBytes),
    );
  });
}
