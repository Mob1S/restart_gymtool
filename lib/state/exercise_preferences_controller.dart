import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/db/sql_executor.dart';
import '../data/repositories/exercise_preferences_repo.dart';
import '../domain/exercise_preferences.dart';
import '../domain/record_management.dart';
import '../domain/workout_edit.dart';
import 'data_revision.dart';

class ExercisePreferencesController extends ChangeNotifier {
  final SqlExecutor _exec;
  final DataRevision? revision;
  final Map<String, ExercisePreference> _values = {};
  bool _disposed = false;
  bool busy = false;
  int _generation = 0;
  String? message;
  ExercisePreferencesController(this._exec, {this.revision}) {
    revision?.addListener(invalidate);
  }
  void invalidate() {
    final ids = _values.keys.toList();
    _generation++;
    _values.clear();
    if (!_disposed) {
      notifyListeners();
      unawaited(
        load(ids).catchError((Object error) {
          if (!_disposed) {
            message = '偏好加载失败，请重新打开';
            notifyListeners();
          }
        }),
      );
    }
  }

  ExercisePreference preferenceFor(String id) =>
      _values[id] ?? ExercisePreference(exerciseId: id, token: 'null');
  Future<void> load(Iterable<String> ids) async {
    final generation = _generation;
    final values = await readExercisePreferences(_exec, ids);
    if (_disposed || generation != _generation) return;
    _values.addAll(values);
    notifyListeners();
  }

  Future<WorkoutWriteResult> save(
    String id, {
    int? weightStepMilli,
    bool? isFavorite,
    String? equipmentNote,
    String? expectedToken,
  }) async {
    if (busy || _disposed) return WorkoutWriteResult.busy;
    busy = true;
    message = null;
    notifyListeners();
    try {
      final result = await saveExercisePreference(
        _exec,
        id,
        expectedToken: expectedToken ?? preferenceFor(id).token,
        weightStepMilli: weightStepMilli,
        isFavorite: isFavorite,
        equipmentNote: equipmentNote,
      );
      if (_disposed) return WorkoutWriteResult.saved;
      revision?.changed();
      _values[id] = result;
      return WorkoutWriteResult.saved;
    } on RecordManagementException catch (e) {
      message = e.message;
      await load([id]);
      return WorkoutWriteResult.conflict;
    } catch (e) {
      message = e is FormatException ? e.message : '偏好未保存，请重试';
      return WorkoutWriteResult.failed;
    } finally {
      busy = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    revision?.removeListener(invalidate);
    super.dispose();
  }
}
