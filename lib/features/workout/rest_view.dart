import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/format.dart';
import '../../ui/theme.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/primary_button.dart';
import 'breathing_dot.dart';

/// 休息界面：**正计时，不催促**。
///
/// 这是本 App 与常见健身 App 最重要的区别（规格 §3.4）：
/// 用户休息多久就记多久，数据是**观察**出来的，不是**规定**出来的。
/// 倒计时会催人，而每一次休息都因此成为一条可分析的数据。
///
/// **计时基于 `restStartedAt` 时间戳用「现在 − 开始」算，不用累加器** ——
/// App 被系统挂起十分钟，算出来的休息时长依然准确。旧项目真机实测：
/// 息屏前 18:20，息屏 35 秒后 19:01，Δ41 秒 vs 实测等待 40 秒，吻合。
class RestView extends StatefulWidget {
  final int restStartedAt;
  final int nextSetNumber;
  final VoidCallback onBeginNextSet;

  const RestView({
    super.key,
    required this.restStartedAt,
    required this.nextSetNumber,
    required this.onBeginNextSet,
  });

  @override
  State<RestView> createState() => _RestViewState();
}

class _RestViewState extends State<RestView> {
  Timer? _timer;

  /// 每次都从时间戳现算，**不累加** —— 累加器在 App 被挂起时会冻住
  int get _elapsedSeconds =>
      ((DateTime.now().millisecondsSinceEpoch - widget.restStartedAt) / 1000)
          .floor();

  @override
  void initState() {
    super.initState();
    // 这个 Timer **只负责触发重绘**，不负责计时。
    // 所以它的 tick 间隔准不准、挂起期间有没有跳，都不影响读数。
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 呼吸点告诉用户「它真的在走」，而不是一个静止的 00:00
        const BreathingDot(),
        const SizedBox(height: AppSpacing.lg),
        Text(
          formatClock(_elapsedSeconds),
          style: TextStyle(
            fontSize: AppFontSize.clock,
            fontWeight: FontWeight.w700,
            color: c.textPrimary,
            fontFeatures: tabularNums,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text('组间休息', style: TextStyle(
          fontSize: AppFontSize.label,
          letterSpacing: AppTracking.unit,
          color: c.textTertiary,
        )),
        const SizedBox(height: AppSpacing.xxl),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
          child: PrimaryButton(
            label: '开始第 ${widget.nextSetNumber} 组',
            onPressed: widget.onBeginNextSet,
          ),
        ),
      ],
    );
  }
}
