import 'package:flutter/material.dart';

import '../../state/backup_controller.dart';

class BackupPreviewDialog extends StatefulWidget {
  final BackupController controller;
  final ScaffoldMessengerState messenger;
  const BackupPreviewDialog({
    super.key,
    required this.controller,
    required this.messenger,
  });

  @override
  State<BackupPreviewDialog> createState() => _BackupPreviewDialogState();
}

class _BackupPreviewDialogState extends State<BackupPreviewDialog> {
  // Preserve the displayed confirmation while the controller clears its token.
  late final _preview = widget.controller.preview!;
  late final _name = widget.controller.fileName!;

  Future<void> _restore() async {
    final controller = widget.controller;
    final navigator = Navigator.of(context);
    await controller.confirmRestore();
    if (mounted) navigator.pop();
    final message = controller.message;
    if (message != null && widget.messenger.mounted) {
      widget.messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final incoming = _preview.incoming;
      final current = _preview.current;
      final count = incoming.rows('sessions').length;
      final localCount = current.rows('sessions').length;
      final date = DateTime.fromMillisecondsSinceEpoch(incoming.exportedAt)
          .toLocal();
      final busy = widget.controller.restoring;
      return PopScope(
        canPop: !busy,
        child: AlertDialog(
          title: const Text('恢复备份'),
          scrollable: true,
          content: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_name),
              const SizedBox(height: 12),
              Text('导出时间：${date.toString().split('.').first}'),
              Text('备份格式：v${incoming.version}'),
              Text('训练：$count 场 · 已完成 ${incoming.completedSessions} 场'),
              Text(
                '动作：${incoming.rows('exercises').length} 个 · 组：${incoming.rows('sets').length}',
              ),
              Text('计划：${incoming.rows('templates').length} 个'),
              Text('动作偏好 ${incoming.rows('exercisePreferences').length} 项'),
              Text(
                incoming.version < 3
                    ? '旧备份将收藏、调重幅度和器械备忘恢复为默认。'
                    : '本机收藏、调重幅度和器械备忘将一起替换。',
              ),
              const SizedBox(height: 16),
              Text(
                '动作库：本机 ${current.rows('exercises').length} 个 → 备份 ${incoming.rows('exercises').length} 个',
              ),
              Text(
                '训练计划：本机 ${current.rows('templates').length} 个 → 备份 ${incoming.rows('templates').length} 个',
              ),
              const SizedBox(height: 12),
              const Text(
                '这是整库恢复，会替换本机的动作库、训练记录和训练计划；备份含偏好时也会替换偏好。新建或编辑计划请使用「训练计划」。本机视频复盘也会清除，JSON 备份不包含复盘视频和分析结果。',
              ),
              const SizedBox(height: 12),
              Text('将用备份中的 $count 场训练替换本机的 $localCount 场训练。建议先导出当前数据。'),
              if (current.activeSessions > 0)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text('本机有进行中的训练，它也会被替换。'),
                ),
              if (count == 0)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text('此备份没有训练记录，恢复后本机现有训练将被清空'),
                ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.only(top: 16),
                  child: LinearProgressIndicator(),
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: busy ? null : () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: busy ? null : _restore,
              child: Text(busy ? '正在恢复…' : '替换并恢复'),
            ),
          ],
        ),
      );
    },
  );
}
