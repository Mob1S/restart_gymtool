import 'package:flutter/foundation.dart';

import '../data/db/sql_executor.dart';
import '../data/repositories/record_management_repo.dart';
import '../domain/record_management.dart';
import '../domain/workout_edit.dart';
import 'active_session_controller.dart';

class RecordManagementController extends ChangeNotifier {
  final SqlExecutor exec;
  final ActiveSessionController active;
  final VoidCallback onChanged;
  RecordManagementController(
    this.exec, {
    required this.active,
    required this.onChanged,
  });
  bool busy = false;
  bool _disposed = false;
  String? message;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<SessionDeletePreview?> previewDelete(String id) async {
    if (busy || _disposed) return null;
    busy = true;
    message = null;
    _notify();
    try {
      if (active.session?.id == id) {
        final result = await active.flushPendingWeight();
        if (active.writing ||
            (result != WorkoutWriteResult.saved &&
                result != WorkoutWriteResult.unchanged)) {
          message = '重量尚未保存，请返回训练重试';
          return null;
        }
      }
      return await inspectSessionDeletion(exec, id);
    } catch (_) {
      message = '无法读取这场训练，请重试';
      return null;
    } finally {
      busy = false;
      _notify();
    }
  }

  Future<bool> confirmDelete(SessionDeletePreview preview) async {
    if (busy || _disposed) return false;
    busy = true;
    message = null;
    _notify();
    try {
      final result = await deleteSession(exec, preview);
      try {
        if (active.session?.id == result.sessionId) active.reset();
        onChanged();
      } catch (_) {
        message = '记录已删除，请重新打开查看';
        return true;
      }
      message = result.deleted ? '记录已删除' : '这场训练已不存在';
      return true;
    } catch (e) {
      message = e is RecordManagementException ? e.message : '未删除，本机数据未改动，请重试';
      return false;
    } finally {
      busy = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
