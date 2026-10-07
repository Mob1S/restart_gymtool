import 'package:flutter/material.dart';

import '../theme.dart';
import '../tokens.dart';

/// 二级容器。`surface` 色 + 细描边，不用阴影 ——
/// 暗色主题里阴影几乎不可见，描边才是能看清边界的手段。
class AppCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
  });

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(color: c.border),
      ),
      child: child,
    );

    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radius),
      child: content,
    );
  }
}
