import 'package:flutter/material.dart';

import '../../ui/theme.dart';
import '../../ui/tokens.dart';

/// 一对 −/+ 做精确微调。
///
/// 视觉上是**次级**的（比大数字小得多）—— 它服务的是「22.5 想变 25」
/// 这种微调，不是主要操作路径。
class NumberStepper extends StatelessWidget {
  final double value;
  final double step;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const NumberStepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.step = 2.5,
    this.min = 0,
    this.max = 500,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _btn(context, Icons.remove, () {
          final next = (value - step).clamp(min, max);
          onChanged((next / step).round() * step);
        }),
        const SizedBox(width: AppSpacing.lg),
        _btn(context, Icons.add, () {
          final next = (value + step).clamp(min, max);
          onChanged((next / step).round() * step);
        }),
      ],
    );
  }

  Widget _btn(BuildContext context, IconData icon, VoidCallback onTap) {
    final c = appColors(context);
    return SizedBox(
      width: 48,
      height: 48,
      child: Material(
        color: c.surfacePressed,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          child: Icon(icon, size: 22, color: c.textSecondary),
        ),
      ),
    );
  }
}
