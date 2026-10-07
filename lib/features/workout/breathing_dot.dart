import 'package:flutter/material.dart';

import '../../ui/theme.dart';

/// 休息计时旁的呼吸点。
///
/// 它存在的理由是：一个静止的 `00:00` 无法告诉用户计时到底有没有在跑。
class BreathingDot extends StatefulWidget {
  const BreathingDot({super.key});

  @override
  State<BreathingDot> createState() => _BreathingDotState();
}

class _BreathingDotState extends State<BreathingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    final dot = Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
    );

    // 系统开了「减弱动态效果」就不做呼吸，只留一个静止的点。
    // 规格 §6.4：两处动效都必须尊重这个开关。
    if (MediaQuery.disableAnimationsOf(context)) return dot;

    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1.0).animate(_controller),
      child: dot,
    );
  }
}
