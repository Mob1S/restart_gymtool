import 'package:flutter/foundation.dart';

import '../data/db/sql_executor.dart';
import '../data/ids.dart';
import '../data/repositories/training_plan_repo.dart';
import '../domain/plans.dart';
import '../domain/training_plans.dart';

class PlanController extends ChangeNotifier {
  final SqlExecutor exec;
  final VoidCallback onChanged;
  final ValueChanged<String>? onDayDeleted, onPlanDeleted;
  PlanController(
    this.exec, {
    required this.onChanged,
    this.onDayDeleted,
    this.onPlanDeleted,
  });

  List<TrainingPlanDetail> plans = [];
  TrainingPlanDraft? draft;
  List<String> dayKeys = [];
  Set<String> _savedDayIds = {};
  bool busy = false, dirty = false, _disposed = false;
  String? message;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<T?> _run<T>(Future<T> Function() action) async {
    if (busy || _disposed) return null;
    busy = true;
    message = null;
    _notify();
    try {
      return await action();
    } catch (e) {
      message = e is PlanValidationException ? e.message : '无法保存计划，请重试';
      return null;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<void> loadList() async {
    await _run(() async {
      plans = await listTrainingPlans(exec);
    });
  }

  Future<void> loadDraft(String? id) async {
    if (busy) return;
    draft = null;
    dirty = false;
    dayKeys = [];
    _savedDayIds = {};
    await _run(() async {
      final existing = id == null ? null : await getTrainingPlan(exec, id);
      if (id != null && existing == null) {
        message = '这个计划不存在';
        return;
      }
      draft = existing?.toDraft() ?? TrainingPlanDraft(name: '', days: []);
      dayKeys = [for (final day in draft!.days) day.id ?? newId()];
      _savedDayIds = {
        for (final day in draft!.days)
          if (day.id != null) day.id!,
      };
    });
  }

  void _edit(String name, List<TrainingDayDraft> days) {
    final d = draft;
    if (d == null || busy || _disposed) return;
    draft = TrainingPlanDraft(
      id: d.id,
      expectedToken: d.expectedToken,
      name: name,
      days: days,
    );
    dirty = true;
    _notify();
  }

  void updateName(String name) {
    if (draft != null) _edit(name, draft!.days);
  }

  void addDay(TrainingDayDraft day) {
    if (draft == null || busy) return;
    dayKeys = [...dayKeys, newId()];
    _edit(draft!.name, [...draft!.days, day]);
  }

  void updateDay(int index, TrainingDayDraft day) {
    final d = draft;
    if (d == null || busy || index < 0 || index >= d.days.length) return;
    final days = [...d.days];
    days[index] = TrainingDayDraft(
      id: d.days[index].id,
      name: day.name,
      kind: day.kind,
      exerciseIds: day.exerciseIds,
      occurrenceIds: day.occurrenceIds,
    );
    _edit(d.name, days);
  }

  void removeDay(int index) {
    final d = draft;
    if (d == null || busy || index < 0 || index >= d.days.length) return;
    dayKeys = [...dayKeys]..removeAt(index);
    _edit(d.name, [...d.days]..removeAt(index));
  }

  void moveDay(int index, int direction) {
    final d = draft;
    final target = index + direction;
    if (d == null ||
        busy ||
        index < 0 ||
        index >= d.days.length ||
        target < 0 ||
        target >= d.days.length) {
      return;
    }
    final days = [...d.days];
    days.insert(target, days.removeAt(index));
    final keys = [...dayKeys];
    keys.insert(target, keys.removeAt(index));
    dayKeys = keys;
    _edit(d.name, days);
  }

  Future<bool> saveDraft() async {
    final d = draft;
    if (d == null) return false;
    return await _run(() async {
          final result = await saveTrainingPlan(exec, d);
          final retained = {for (final day in result.days) day.id};
          draft = result.toDraft();
          dayKeys = [for (final day in result.days) day.id];
          dirty = false;
          try {
            for (final removed in _savedDayIds.difference(retained)) {
              onDayDeleted?.call(removed);
            }
            onChanged();
          } catch (_) {
            message = '计划已保存，请重新打开查看';
          }
          _savedDayIds = retained;
          return true;
        }) ==
        true;
  }

  Future<void> movePlan(String id, int direction) async {
    await _run(() async {
      await moveTrainingPlan(
        exec,
        id,
        direction,
        expectedOrderToken: trainingPlanOrderToken(plans),
      );
      onChanged();
      plans = await listTrainingPlans(exec);
    });
  }

  Future<bool> confirmDelete(TrainingPlanDetail preview) async =>
      await _run(() async {
        await deleteTrainingPlan(
          exec,
          preview.id,
          expectedToken: preview.token,
        );
        try {
          onPlanDeleted?.call(preview.id);
          onChanged();
        } catch (_) {
          message = '计划已删除，请重新打开查看';
        }
        try {
          plans = await listTrainingPlans(exec);
        } catch (_) {
          message = '计划已删除，请重新打开查看';
        }
        return true;
      }) ==
      true;
  void discardDraft() {
    if (busy) return;
    draft = null;
    dayKeys = [];
    dirty = false;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
