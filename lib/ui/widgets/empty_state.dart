import 'package:flutter/material.dart';

import '../theme.dart';
import '../tokens.dart';

/// 空态。
///
/// [action] 不是可选的装饰 —— 旧项目在 M2 踩过一个坑：训练页的空态
/// 只显示一句「这次训练还没有动作」，**没有任何添加入口**，
/// 用户进到那里就是一条死路。空态必须给出下一步。
class EmptyState extends StatelessWidget {
  final String message;
  final Widget? action;

  const EmptyState({super.key, required this.message, this.action});

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: AppFontSize.body, color: c.textSecondary),
            ),
            if (action != null) ...[
              const SizedBox(height: AppSpacing.xl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
