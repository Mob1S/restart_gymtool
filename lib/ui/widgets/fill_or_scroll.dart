import 'package:flutter/material.dart';

/// 「装得下就铺满整屏，装不下才滚动」。
///
/// ## 为什么需要它
///
/// 记录页与休息页都是**按一屏刚好放下**排的（规格 §6.1：拇指永远停在
/// 同一个位置，不必瞄准）。这个假设在窄屏上不成立 —— 一次桌面探针
/// （模拟真机视口）实测出两条：
///
/// | 场景 | 原始结果 |
/// |---|---|
/// | 记录页 320×480 | `RenderFlex overflowed by 59 pixels on the bottom` |
/// | 休息页 640×360 横屏 | `RenderFlex overflowed by 31 pixels on the bottom` |
///
/// 溢出不是「不好看」而已：被切掉的正好是**唯一的主操作**
/// （「完成这组」/「开始第 N 组」），切掉就等于这一组记不了。
///
/// ## 为什么不是直接套 SingleChildScrollView
///
/// 直接套会把 `Spacer` 废掉 —— 滚动视图给的是**无界高度**，
/// `RenderFlex` 在无界主轴上算不出剩余空间，两个 `Spacer` 的高度会塌成 0，
/// 于是正常手机上「大数字居中、按钮贴底」的布局会整块挤到顶部。
///
/// 所以由 [IntrinsicHeight] 先把内容量成一个确定高度，外层 [ConstrainedBox]
/// 再把它撑到至少一屏。**装得下时布局与从前逐像素一致**，装不下时才滚动。
///
/// ## 已知的代价（不藏着）
///
/// 在 320×480 这种极窄屏上，内容确实比一屏高，于是**主按钮会落到首屏之外，
/// 需要往下滚一点**。这是刻意的取舍：宁可滚一下，也不要一个被切掉、
/// 点不到的按钮。正常手机（360×640 以上）完全不受影响。
class FillOrScroll extends StatelessWidget {
  final Widget child;

  const FillOrScroll({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: IntrinsicHeight(child: child),
        ),
      ),
    );
  }
}
