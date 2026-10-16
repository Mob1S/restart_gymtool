import 'package:flutter/foundation.dart';

import '../data/db/sql_executor.dart';
import '../data/repositories/template_repo.dart';
import '../domain/plans.dart';

class PlanController extends ChangeNotifier {
  final SqlExecutor exec;
  final VoidCallback onChanged;
  final void Function(String id)? onDeleted;
  PlanController(this.exec, {required this.onChanged, this.onDeleted});
  List<TemplateSummary> plans = [];
  TemplateDraft? draft;
  bool busy = false;
  bool dirty = false;
  bool _disposed = false;
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
      plans = await listTemplates(exec);
    });
  }

  Future<void> loadDraft(String? id) async {
    draft = null;
    dirty = false;
    await _run(() async {
      if (id == null) {
        draft = TemplateDraft(name: '', exerciseIds: []);
        return;
      }
      final existing = await getTemplate(exec, id);
      if (existing == null) {
        message = '这个计划不存在';
        return;
      }
      draft = TemplateDraft(
        id: id,
        name: existing.template.name,
        exerciseIds: existing.exercises.map((e) => e.entry.exerciseId).toList(),
        expectedToken: existing.editToken,
      );
    });
  }

  void _edit(String name, List<String> ids) {
    final d = draft;
    if (d == null || busy) return;
    draft = TemplateDraft(
      id: d.id,
      name: name,
      exerciseIds: ids,
      expectedToken: d.expectedToken,
    );
    dirty = true;
    _notify();
  }

  void updateName(String name) {
    final d = draft;
    if (d != null) _edit(name, d.exerciseIds);
  }

  void addExercise(String id) {
    final d = draft;
    if (d != null) _edit(d.name, [...d.exerciseIds, id]);
  }

  void removeDraftItem(int index) {
    final d = draft;
    if (d == null || index < 0 || index >= d.exerciseIds.length) return;
    _edit(d.name, [...d.exerciseIds]..removeAt(index));
  }

  void moveDraftItem(int index, int direction) {
    final d = draft;
    if (d == null ||
        index < 0 ||
        index >= d.exerciseIds.length ||
        index + direction < 0 ||
        index + direction >= d.exerciseIds.length) {
      return;
    }
    final ids = [...d.exerciseIds];
    final id = ids.removeAt(index);
    ids.insert(index + direction, id);
    _edit(d.name, ids);
  }

  Future<bool> saveDraft() async {
    final d = draft;
    if (d == null) return false;
    final saved = await _run(() async {
      final result = await saveTemplate(exec, d);
      dirty = false;
      draft = TemplateDraft(
        id: result.template.id,
        name: result.template.name,
        exerciseIds: result.exercises.map((e) => e.entry.exerciseId).toList(),
        expectedToken: result.editToken,
      );
      try {
        onChanged();
      } catch (_) {
        message = '计划已保存，请重新打开查看';
      }
      return true;
    });
    return saved == true;
  }

  Future<void> movePlan(String id, int direction) async {
    await _run(() async {
      if (await moveTemplate(exec, id, direction, templateOrderToken(plans))) {
        try {
          onChanged();
          plans = await listTemplates(exec);
        } catch (_) {
          message = '计划顺序已保存，请重新打开查看';
        }
      } else {
        plans = await listTemplates(exec);
      }
    });
  }

  Future<TemplateDeletePreview?> previewDelete(String id) =>
      _run<TemplateDeletePreview?>(() => inspectTemplateDeletion(exec, id));
  Future<bool> confirmDelete(TemplateDeletePreview preview) async {
    final ok = await _run(() async {
      final result = await deleteTemplate(exec, preview);
      if (result.deleted) {
        try {
          onDeleted?.call(preview.id);
          onChanged();
        } catch (_) {
          message = '计划已删除，请重新打开查看';
        }
      }
      try {
        plans = await listTemplates(exec);
      } catch (_) {
        message = '计划已删除，请重新打开查看';
      }
      return result.deleted;
    });
    return ok == true;
  }

  void discardDraft() {
    if (busy) return;
    draft = null;
    dirty = false;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
