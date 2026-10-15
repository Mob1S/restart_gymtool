import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/files/backup_file_store.dart';
import 'package:gym_tracker/data/repositories/backup_repo.dart';
import 'package:gym_tracker/data/repositories/settings_repo.dart';
import 'package:gym_tracker/domain/backup_codec.dart';
import 'package:gym_tracker/state/backup_controller.dart';

import '../support/backup_fakes.dart';
import '../data/backup_repo_test.dart' show FailingExecutor, loadFixture;

void main() {
  late FfiExecutor exec;
  late MemoryBackupFiles files;
  late BackupController controller;
  var refreshes = 0;
  Future<void> Function()? refresh;
  setUp(() async {
    exec = await FfiExecutor.openMigrated();
    files = MemoryBackupFiles();
    refreshes = 0;
    refresh = null;
    controller = BackupController(
      exec: exec,
      files: files,
      now: () => DateTime(2026, 10, 15, 12, 34, 56).millisecondsSinceEpoch,
      onRestored: () async {
        refreshes++;
        await refresh?.call();
      },
    );
  });
  tearDown(() async {
    controller.dispose();
    await exec.close();
  });

  test(
    'filename and bytes share one instant; download and cancellation messages',
    () async {
      files.saveResult = BackupSaveResult.downloadRequested;
      expect(
        await controller.exportBackupFile(),
        BackupSaveResult.downloadRequested,
      );
      expect(files.savedName, 'gym-backup-2026-10-15-123456.json');
      expect(
        decodeBackup(files.savedBytes!).exportedAt,
        DateTime(2026, 10, 15, 12, 34, 56).millisecondsSinceEpoch,
      );
      expect(controller.message, contains('已请求下载'));
      files.saveResult = BackupSaveResult.canceled;
      await controller.exportBackupFile();
      expect(controller.message, isNull);
      expect(controller.busy, false);
    },
  );
  test('concurrent selections only open one picker and cancellation clears previous preview', () async {
    files.useFixture();
    await controller.selectBackupFile();
    expect(controller.preview, isNotNull);
    final gate = Completer<PickedBackup?>();
    files.choose = () => gate.future;
    final first = controller.selectBackupFile();
    expect(controller.preview, isNull);
    expect(await controller.selectBackupFile(), false);
    expect(files.picks, 2);
    gate.complete(null);
    expect(await first, false);
    expect(controller.busy, false);
    expect(await controller.confirmRestore(), BackupRestoreResult.notRestored);
    expect(refreshes, 0);
  });
  test(
    'cancel during asynchronous selection prevents late preview resurrection',
    () async {
      files.useFixture();
      final gate = Completer<PickedBackup?>();
      files.choose = () => gate.future;
      final pending = controller.selectBackupFile();
      controller.cancelPreview();
      gate.complete(files.selected);
      expect(await pending, false);
      expect(controller.preview, isNull);
      expect(controller.busy, false);
    },
  );
  test('concurrent exports only save once', () async {
    final gate = Completer<BackupSaveResult>();
    final entered = Completer<void>();
    files.write = () {
      entered.complete();
      return gate.future;
    };
    final first = controller.exportBackupFile();
    await entered.future;
    expect(await controller.exportBackupFile(), isNull);
    expect(files.saves, 1);
    gate.complete(BackupSaveResult.saved);
    await first;
    expect(controller.busy, false);
  });
  test('commit once; repeated confirmation and cancellation cannot interrupt refresh', () async {
    files.useFixture();
    await controller.selectBackupFile();
    final gate = Completer<void>();
    final entered = Completer<void>();
    refresh = () {
      entered.complete();
      return gate.future;
    };
    final first = controller.confirmRestore();
    await entered.future;
    expect(controller.restoring, true);
    controller.cancelPreview();
    expect(await controller.confirmRestore(), BackupRestoreResult.notRestored);
    gate.complete();
    expect(await first, BackupRestoreResult.restored);
    expect(controller.preview, isNull);
    expect(controller.revision, 1);
    expect(refreshes, 1);
    expect(controller.busy, false);
    expect(controller.restoring, false);
    expect(
      (await exportBackup(exec, exportedAt: 0)).rows('sessions'),
      hasLength(2),
    );
  });
  test(
    'postcommit refresh error must report that database was restored',
    () async {
      files.useFixture();
      await controller.selectBackupFile();
      refresh = () async => throw StateError('UI');
      expect(
        await controller.confirmRestore(),
        BackupRestoreResult.refreshFailed,
      );
      expect(controller.message, '数据已恢复，界面刷新失败，请重新打开应用');
      expect(
        (await exportBackup(exec, exportedAt: 0)).rows('sessions'),
        hasLength(2),
      );
      expect(controller.revision, 1);
      expect(controller.restoring, false);
    },
  );
  test(
    'stale preview refuses restore without refresh and retains local data',
    () async {
      files.useFixture();
      await controller.selectBackupFile();
      await setSetting(exec, 'theme_mode', 'dark');
      expect(
        await controller.confirmRestore(),
        BackupRestoreResult.notRestored,
      );
      expect(await getSetting(exec, 'theme_mode'), 'dark');
      expect(refreshes, 0);
      expect(controller.message, contains('重新预览'));
      expect(controller.preview, isNull);
      expect(controller.busy, false);
    },
  );
  test(
    'pick, malformed data, save and snapshot failures all release busy',
    () async {
      files.choose = () async => throw StateError('pick');
      await controller.selectBackupFile();
      expect(controller.busy, false);
      files.choose = null;
      files.useJson({'bad': true});
      await controller.selectBackupFile();
      expect(controller.preview, isNull);
      expect(controller.busy, false);
      files.write = () async => throw StateError('save');
      await controller.exportBackupFile();
      expect(controller.busy, false);
      await exec.run('DROP TABLE set_entry');
      files.useFixture();
      await controller.selectBackupFile();
      expect(controller.preview, isNull);
      expect(controller.busy, false);
      expect(controller.restoring, false);
    },
  );
  test(
    'write failure rolls back local data and never refreshes the app',
    () async {
      await restoreBackup(exec, await inspectBackup(exec, loadFixture()));
      final before = (await exportBackup(exec, exportedAt: 0)).data;
      controller.dispose();
      controller = BackupController(
        exec: FailingExecutor(
          exec,
          'DELETE FROM session_exercise',
          StateError('disk'),
        ),
        files: files,
        onRestored: () async {
          refreshes++;
        },
      );
      files.useFixture('current-v2');
      await controller.selectBackupFile();
      expect(
        await controller.confirmRestore(),
        BackupRestoreResult.notRestored,
      );
      expect((await exportBackup(exec, exportedAt: 0)).data, before);
      expect(refreshes, 0);
      expect(controller.revision, 0);
      expect(controller.busy, false);
      expect(controller.restoring, false);
      expect(controller.message, contains('未改动数据'));
    },
  );
}
