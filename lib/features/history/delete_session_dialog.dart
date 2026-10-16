import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/format.dart';
import '../../state/record_management_controller.dart';

Future<bool> showDeleteSessionDialog(BuildContext context, String id) async {
  final c = context.read<RecordManagementController>();
  final preview = await c.previewDelete(id);
  if (preview == null || !context.mounted) return false;
  final confirm = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('删除 ${formatDateTime(preview.session.startedAt)} 的训练？'),
      content: Text(
        '${preview.session.finishedAt == null ? '这场训练正在进行。' : ''}这场训练和已记的 ${preview.completedSets} 组会消失，相关进步数据将重新计算。此操作无法撤销。',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('删除这场训练'),
        ),
      ],
    ),
  );
  if (confirm != true) return false;
  final ok = await c.confirmDelete(preview);
  if (context.mounted && c.message != null) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(c.message!)));
  }
  return ok;
}
