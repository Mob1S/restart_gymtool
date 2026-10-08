import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../domain/chart_geometry.dart';
import '../theme.dart';

/// 走势图：一条折线 + 每个点一个圆点，最大值那个用 `success` 且更大。
///
/// **坐标一个字都不在这里算** —— 全部来自 `layoutChart`。这样「画在哪」能用
/// 纯 dart test 锁住，「怎么画」才留给眼睛（规格 §2.2 的分工）。
///
/// 不画坐标轴 / 网格 / 刻度：y 轴取 `min..max` 而不是从 0 起，添上刻度就得
/// 为「看起来涨得比实际猛」辩护；数值由卡片头上的「最好值 · 日期」给出，
/// 图只表达走势（规格 §2.2 第 2 条）。
class TrendChart extends StatelessWidget {
  /// 一场训练一个值。null = 这一场没有值 —— e1RM 序列里那些「所有组次数
  /// 都 > 10」的场次就是 null。
  ///
  /// null 不画点，但**线直接连过去**：不补 0（0 是「练得很差」），也不补估算
  /// （正是被禁止的外推）—— 缺口只由页面在图下写一句说明（规格 §5.5）。
  final List<double?> values;

  /// 列表行里的迷你走势：矮，只画线 + 最后一点，不画高亮。
  final bool compact;

  const TrendChart({super.key, required this.values, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    return SizedBox(
      // 宽度铺满上层给的约束；compact 给一个默认宽度，好让它直接站进 Row。
      width: compact ? _compactWidth : double.infinity,
      height: compact ? _compactHeight : _regularHeight,
      // 左右各留出一个「最大圆点」的半径：第一点 / 最后一点正好落在画布边上，
      // 不留这一手，边缘的圆就有一半在画布外 —— 越界绘制会被怎样处理
      // （光栅缓存裁掉、或原样画到邻居身上）不由我们说了算。
      // 这是 Padding，不是几何：`layoutChart` 拿到的仍是画布自己的尺寸。
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: _highlightRadius),
        child: CustomPaint(
          painter: _TrendChartPainter(
            values: values,
            compact: compact,
            // 线用 accent（这个 App 的主信号色），success 只留给高亮点 ——
            // 绿色出现第二处就不再点得醒「这是最大值」。
            lineColor: c.accent,
            highlightColor: c.success,
          ),
        ),
      ),
    );
  }
}

/// 图表专属尺寸，**不进 `tokens.dart`**。
///
/// tokens 装的是「多处共用同一档观感」的尺度（字号 / 间距 / 圆角）；下面这几个
/// 只有本文件一个使用者，混进全局清单只会稀释它。**出现第二个使用者就该搬。**
const double _regularHeight = 120;
const double _compactHeight = 28;
const double _compactWidth = 72;
const double _strokeWidth = 2;
const double _compactStrokeWidth = 1.5;
const double _dotRadius = 3;
const double _highlightRadius = 5;
const double _compactDotRadius = 2;

/// 与 `layoutChart` 的默认留白相同（12 放得下半径 5 的高亮点）。
/// 写出来只是让 compact 那一档的差异留在同一条语句里。
const double _regularInsetY = 12;

/// compact 画布只有 28 高：沿默认的 12 会把纵向压成 4px 的一条。
/// 按点半径收到 4 就够 —— 点不被裁，走势还剩 20px 起伏空间。
const double _compactInsetY = 4;

class _TrendChartPainter extends CustomPainter {
  final List<double?> values;
  final bool compact;
  final Color lineColor;
  final Color highlightColor;

  const _TrendChartPainter({
    required this.values,
    required this.compact,
    required this.lineColor,
    required this.highlightColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final layout = layoutChart(
      values: values,
      width: size.width,
      height: size.height,
      insetY: compact ? _compactInsetY : _regularInsetY,
    );

    // 空列表 / 全 null 都是「没有点可画」：不画占位的平线 ——
    // 一条贴 0 的平线会被读成「一直没进步」（规格 §6）。
    if (layout.points.isEmpty) return;

    _paintPolyline(canvas, layout);
    if (compact) {
      _paintLastPoint(canvas, layout);
    } else {
      _paintDots(canvas, layout);
    }
  }

  /// 折线：按 points 的顺序连。null 留下的缺口不画断 —— 相邻两点直接连过去。
  ///
  /// 只有一个点时 `Path` 里只有一次 `moveTo`，画不出线 —— 那正是
  /// 「只练过一次，还没有走势可看」，点照画，文案由页面给（规格 §6）。
  void _paintPolyline(Canvas canvas, ChartLayout layout) {
    final path = Path()..moveTo(layout.points.first.x, layout.points.first.y);
    for (final point in layout.points.skip(1)) {
      path.lineTo(point.x, point.y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = compact ? _compactStrokeWidth : _strokeWidth
        // 圆头 + 圆角接头：单点或尖峰处不留一段方线茬。
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _paintDots(Canvas canvas, ChartLayout layout) {
    // ⚠️ `highlightIndex` 是 **values 的下标**，不是 points 的下标 ——
    // 两者在序列里有 null 时必然错开（e1RM 里「所有组次数都 > 10」的场次
    // 就是 null），写 `points[highlightIndex]` 会点错点，或者直接越界。
    final highlightIndex = layout.highlightIndex;
    final highlight = highlightIndex == null
        ? null
        : layout.points.firstWhere((p) => p.index == highlightIndex);

    final dotPaint = Paint()..color = lineColor;
    for (final point in layout.points) {
      if (point.index == highlightIndex) continue; // 高亮点单独画，半径更大
      canvas.drawCircle(Offset(point.x, point.y), _dotRadius, dotPaint);
    }

    if (highlight != null) {
      canvas.drawCircle(
        Offset(highlight.x, highlight.y),
        _highlightRadius,
        Paint()..color = highlightColor,
      );
    }
  }

  /// compact 只点最后一个点 —— 最近一次**有值**的训练（末尾是 null 不算，
  /// 它本来就没有点）。
  ///
  /// 高亮不画：一行里塞不下图例，孤零零一个绿点会被读成「最近一次最好」，
  /// 而它其实是历史最大。绿点只在能给它上下文（卡片头的「最好 · 日期」）
  /// 的地方出现。
  void _paintLastPoint(Canvas canvas, ChartLayout layout) {
    final last = layout.points.last;
    canvas.drawCircle(
      Offset(last.x, last.y),
      _compactDotRadius,
      Paint()..color = lineColor,
    );
  }

  @override
  bool shouldRepaint(covariant _TrendChartPainter oldDelegate) =>
      oldDelegate.compact != compact ||
      oldDelegate.lineColor != lineColor ||
      oldDelegate.highlightColor != highlightColor ||
      !listEquals(oldDelegate.values, values);
}
