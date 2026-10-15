import 'package:flutter/foundation.dart';

import '../data/db/sql_executor.dart';
import '../data/files/backup_file_store.dart';
import '../data/repositories/backup_repo.dart';
import '../domain/backup.dart';
import '../domain/backup_codec.dart';

enum BackupRestoreResult { restored, refreshFailed, notRestored }

class BackupController extends ChangeNotifier {
  final SqlExecutor _exec;
  final BackupFileStore _files;
  final Future<void> Function() _onRestored;
  final int Function() _now;

  BackupController({
    required this._exec,
    required this._files,
    required this._onRestored,
    int Function()? now,
  }) : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);

  bool _busy = false;
  bool _restoring = false;
  bool _disposed = false;
  int _revision = 0;
  int _selection = 0;
  BackupPreview? _preview;
  String? _fileName;
  String? _message;

  bool get busy => _busy;
  bool get restoring => _restoring;
  int get revision => _revision;
  BackupPreview? get preview => _preview;
  String? get fileName => _fileName;
  String? get message => _message;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _clearPreview() {
    _preview = null;
    _fileName = null;
  }

  Future<BackupSaveResult?> exportBackupFile() async {
    if (_busy || _disposed) return null;
    _busy = true;
    _message = null;
    _notify();
    try {
      final time = _now();
      final backup = await exportBackup(_exec, exportedAt: time);
      final result = await _files.save(
        backupFileName(time),
        encodeBackup(backup),
      );
      _message = switch (result) {
        BackupSaveResult.saved => '备份已保存',
        BackupSaveResult.downloadRequested => '已请求下载备份，请在浏览器下载记录中查看',
        BackupSaveResult.canceled => null,
      };
      return result;
    } catch (error) {
      _message = error is BackupValidationException
          ? error.message
          : '无法导出备份，请检查保存位置后重试';
      return null;
    } finally {
      _busy = false;
      _notify();
    }
  }

  Future<bool> selectBackupFile() async {
    if (_busy || _disposed) return false;
    final selection = ++_selection;
    _clearPreview();
    _message = null;
    _busy = true;
    _notify();
    try {
      final picked = await _files.pick();
      if (picked == null || selection != _selection || _disposed) return false;
      final incoming = decodeBackup(picked.bytes);
      final preview = await inspectBackup(_exec, incoming);
      if (selection != _selection || _disposed) return false;
      _preview = preview;
      _fileName = picked.name;
      return true;
    } catch (error) {
      if (selection == _selection) {
        _message = error is BackupValidationException
            ? error.message
            : '无法读取备份或本机数据，请重试';
      }
      return false;
    } finally {
      _busy = false;
      _notify();
    }
  }

  void cancelPreview() {
    if (_restoring) return;
    _selection++;
    _clearPreview();
    _notify();
  }

  Future<BackupRestoreResult> confirmRestore() async {
    final selected = _preview;
    if (_busy || selected == null || _disposed) {
      return BackupRestoreResult.notRestored;
    }
    _busy = true;
    _restoring = true;
    _message = null;
    _notify();
    try {
      try {
        await restoreBackup(_exec, selected);
      } catch (error) {
        _clearPreview();
        _message = error is BackupValidationException
            ? '${error.message}；本次恢复未改动数据'
            : '恢复失败，本次恢复未改动数据，请重新选择备份后重试';
        return BackupRestoreResult.notRestored;
      }
      _clearPreview();
      _revision++;
      try {
        await _onRestored();
      } catch (_) {
        _message = '数据已恢复，界面刷新失败，请重新打开应用';
        return BackupRestoreResult.refreshFailed;
      }
      _message = '已恢复 ${selected.incoming.rows('sessions').length} 场训练';
      return BackupRestoreResult.restored;
    } finally {
      _restoring = false;
      _busy = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _selection++;
    super.dispose();
  }
}
