import 'package:flutter/material.dart';

import '../theme.dart';
import '../tokens.dart';

enum ButtonVariant { primary, secondary, danger }

/// 主操作按钮。整宽是**有意的** —— 记录页那几次点击要能用拇指一次命中。
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final ButtonVariant variant;
  final IconData? icon;

  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = ButtonVariant.primary,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    final bg = switch (variant) {
      ButtonVariant.primary => c.accent,
      ButtonVariant.secondary => c.surfacePressed,
      ButtonVariant.danger => c.danger,
    };
    final fg = variant == ButtonVariant.secondary ? c.textPrimary : Colors.white;
    final disabled = onPressed == null;

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          disabledBackgroundColor: c.surfacePressed,
          disabledForegroundColor: c.textTertiary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radius),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20),
              const SizedBox(width: AppSpacing.sm),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: AppFontSize.title,
                fontWeight: FontWeight.w600,
                color: disabled ? c.textTertiary : fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
