import 'package:flutter/material.dart';

import '../../state/backup_controller.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/app_card.dart';
import 'backup_preview_dialog.dart';

class BackupSection extends StatelessWidget {
  final BackupController controller;
  const BackupSection({super.key, required this.controller});

  Future<void> _select(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final ready = await controller.selectBackupFile();
    if (!context.mounted) {
      controller.cancelPreview();
      return;
    }
    if (!ready) return;
    await showDialog<void>(
      context: context,
      builder: (_) =>
          BackupPreviewDialog(controller: controller, messenger: messenger),
    );
    controller.cancelPreview();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('数据备份'),
        const SizedBox(height: AppSpacing.sm),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '将训练、动作和偏好保存为 JSON 文件。恢复会替换整个动作库、训练记录和训练计划；新建或编辑计划请使用「训练计划」。视频复盘仅保存在本机，不包含在 JSON 备份中；整库恢复会清除本机复盘。',
              ),
              const SizedBox(height: AppSpacing.md),
              OutlinedButton.icon(
                onPressed: controller.busy ? null : controller.exportBackupFile,
                icon: const Icon(Icons.download_outlined),
                label: const Text('导出备份'),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton.icon(
                onPressed: controller.busy ? null : () => _select(context),
                icon: const Icon(Icons.restore),
                label: const Text('从备份恢复'),
              ),
              if (controller.busy) ...[
                const SizedBox(height: AppSpacing.md),
                const LinearProgressIndicator(),
                const SizedBox(height: AppSpacing.sm),
                Text(controller.restoring ? '正在恢复，请稍候…' : '正在处理文件…'),
              ],
              if (controller.message != null) ...[
                const SizedBox(height: AppSpacing.md),
                Semantics(liveRegion: true, child: Text(controller.message!)),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}
