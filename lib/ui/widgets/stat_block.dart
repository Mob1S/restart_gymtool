import 'package:flutter/material.dart';

import '../theme.dart';
import '../tokens.dart';

/// 总结页顶部那三个数字之一：时长 / 总组数 / 总容量。
///
/// **单位单独一档且更小**，因为它和数字不是同一层级的信息。
class StatBlock extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;

  const StatBlock({
    super.key,
    required this.label,
    required this.value,
    this.unit,
  });

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: AppFontSize.label,
            letterSpacing: AppTracking.label,
            color: c.textTertiary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: AppFontSize.stat,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
                fontFeatures: tabularNums,
              ),
            ),
            if (unit != null) ...[
              const SizedBox(width: 3),
              Text(
                unit!,
                style: TextStyle(
                  fontSize: AppFontSize.caption,
                  color: c.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
