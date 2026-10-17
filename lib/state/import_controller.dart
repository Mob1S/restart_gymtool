import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../data/db/sql_executor.dart';
import '../data/files/backup_file_store.dart';
import '../data/repositories/import_repo.dart';
import '../domain/backup.dart';
import '../domain/import_records.dart';
import '../domain/import_preview.dart';
import '../domain/workout_csv.dart';

enum ImportCommitOutcome { committed, refreshFailed, notCommitted }

class ImportController extends ChangeNotifier {
  final SqlExecutor exec;
  final BackupFileStore files;
  final Future<void> Function(ImportResult) onCommitted;
  ImportController({
    required this.exec,
    required this.files,
    required this.onCommitted,
  });
  bool busy = false;
  bool committing = false;
  bool _disposed = false;
  int _generation = 0;
  ImportDraft? draft;
  ImportSelection? selection;
  String? message;
  String? fileName;
  String? _csv;
  String _origin = 'csv';
  ImportResult? lastResult;
  int? lastImportedStartedAt;
  WeightUnit unit = WeightUnit.kg;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  String _error(Object e) => switch (e) {
    ImportValidationException() => e.message,
    BackupValidationException() => e.message,
    FormatException() => '文件不是有效 UTF-8 CSV',
    _ => '无法读取或保存记录，请重试',
  };
  Future<bool> _prepare(Future<CsvParseResult?> Function() read) async {
    if (busy || _disposed) return false;
    final generation = ++_generation;
    busy = true;
    draft = null;
    selection = null;
    message = null;
    _notify();
    try {
      final parsed = await read();
      if (parsed == null || _disposed || generation != _generation) {
        return false;
      }
      final catalog = await loadImportCatalog(exec);
      if (_disposed || generation != _generation) return false;
      draft = buildImportDraft(parsed, catalog);
      selection = ImportSelection.defaults(draft!);
      return true;
    } catch (e) {
      if (generation == _generation) message = _error(e);
      return false;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<bool> selectCsv({WeightUnit defaultUnit = WeightUnit.kg}) {
    if (busy) return Future.value(false);
    _origin = 'csv';
    _csv = null;
    fileName = null;
    unit = defaultUnit;
    return _prepare(() async {
      final picked = await files.pick();
      if (picked == null) return null;
      if (picked.bytes.length > maxBackupBytes) {
        throw const ImportValidationException('文件超过 20 MiB');
      }
      _csv = utf8.decode(picked.bytes);
      fileName = picked.name;
      return parseWorkoutCsv(_csv!, defaultUnit: unit);
    });
  }

  Future<bool> changeUnit(WeightUnit value) {
    final csv = _csv;
    if (csv == null || busy) return Future.value(false);
    unit = value;
    return _prepare(() async => parseWorkoutCsv(csv, defaultUnit: value));
  }

  Future<bool> previewManual(
    List<ImportedWorkout> workouts, {
    Map<String, String?> matches = const {},
  }) {
    if (busy) return Future.value(false);
    _origin = 'manual';
    _csv = null;
    fileName = null;
    return _prepare(() async {
      validateImportedWorkouts(workouts);
      return CsvParseResult(
        source: CsvSource.unknown,
        workouts: workouts,
        statsByWorkout: [
          for (final _ in workouts) WorkoutImportStats([], 0, false),
        ],
      );
    }).then((ok) {
      if (ok && selection != null) {
        updateSelection(
          ImportSelection(
            selected: selection!.selected,
            matches: {...selection!.matches, ...matches},
          ),
        );
      }
      return ok;
    });
  }

  void updateSelection(ImportSelection value) {
    if (busy || _disposed) return;
    selection = value;
    message = null;
    _notify();
  }

  ConfirmedImport? get confirmed {
    if (draft == null || selection == null) return null;
    try {
      return confirmImportDraft(draft!, selection!);
    } on ImportValidationException {
      return null;
    }
  }

  void cancel({bool notify = true}) {
    if (committing) return;
    _generation++;
    draft = null;
    selection = null;
    if (notify) _notify();
  }

  Future<ImportCommitOutcome> commit() async {
    final batch = confirmed;
    if (busy || batch == null || _disposed) {
      return ImportCommitOutcome.notCommitted;
    }
    busy = true;
    committing = true;
    message = null;
    _notify();
    try {
      ImportResult result;
      try {
        result = await importWorkouts(exec, batch, origin: _origin);
      } catch (e) {
        draft = null;
        selection = null;
        message = '未导入，本机数据未改动：${_error(e)}';
        return ImportCommitOutcome.notCommitted;
      }
      draft = null;
      selection = null;
      lastResult = result;
      lastImportedStartedAt = batch.workouts.isEmpty
          ? null
          : batch.workouts.first.startedAt;
      try {
        await onCommitted(result);
      } catch (_) {
        message = '已导入 ${result.sessions} 场，请重新打开查看';
        return ImportCommitOutcome.refreshFailed;
      }
      message =
          '已导入 ${result.sessions} 场、${result.sets} 组，新增 ${result.createdExercises} 个动作';
      return ImportCommitOutcome.committed;
    } finally {
      busy = false;
      committing = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
