import 'package:flutter/material.dart';

import '../theme.dart';
import '../tokens.dart';

/// A route-independent way back to the loaded workout, without reloading it.
class ActiveWorkoutBar extends StatelessWidget {
  final String? name;
  final int completedSets;
  final bool loading, enabled;
  final String? error;
  final VoidCallback onResume;
  final VoidCallback? onRetry;

  const ActiveWorkoutBar({
    super.key,
    this.name,
    this.completedSets = 0,
    this.loading = false,
    this.enabled = true,
    this.error,
    required this.onResume,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return _frame(
        context,
        const Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: AppSpacing.md),
            Expanded(child: Text('正在读取训练…')),
          ],
        ),
      );
    }
    if (error != null) {
      return _frame(
        context,
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: AppSpacing.sm,
          children: [
            Text(error!),
            TextButton(onPressed: onRetry, child: const Text('重试读取训练')),
          ],
        ),
      );
    }
    if (name == null) {
      return const SizedBox.shrink();
    }
    final c = appColors(context);
    final title = name!.trim().isEmpty ? '本次训练' : name!.trim();
    final count = completedSets;
    return Semantics(
      button: true,
      enabled: enabled,
      onTap: enabled ? onResume : null,
      label: '继续训练，$title，已完成 $count 组',
      excludeSemantics: true,
      child: Material(
        color: c.surface,
        child: InkWell(
          key: const ValueKey('active-workout-resume'),
          onTap: enabled ? onResume : null,
          child: _frame(
            context,
            Row(
              children: [
                Icon(Icons.play_circle_outline, color: c.accent),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '继续训练 · $title',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      Text(
                        '已完成 $count 组',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Icon(Icons.chevron_right, color: c.textSecondary),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _frame(BuildContext context, Widget child) => DecoratedBox(
    decoration: BoxDecoration(
      color: appColors(context).surface,
      border: Border(top: BorderSide(color: appColors(context).border)),
    ),
    child: ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.screenH,
          vertical: AppSpacing.md,
        ),
        child: child,
      ),
    ),
  );
}
