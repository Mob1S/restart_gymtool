/// 折线几何：把「一串数值 + 画布尺寸」算成「该画在哪几个坐标」。
///
/// 纯函数，与 Flutter 无关（规格 §2.2）。这里一个字都不画 —— 绘制在
/// `ui/widgets/trend_chart.dart`；分开的理由是「画在哪」能用纯 dart test 锁住，
/// 而「怎么画」只能靠眼睛看。
///
/// **这是 `domain/` 里最想 import Flutter 的文件**：坐标本该是 `Offset`。
/// 但 `Offset` 来自 `dart:ui`，而 `domain/` 一旦依赖 Flutter 就不再能用纯
/// `dart test` 跑（`test/layering_test.dart` 规则 3 盯着这条），所以坐标在这里
/// 是两个 `double`。这不是绕路，是分层。
library;

/// 折线上的一个点。
class ChartPoint {
  final double x;
  final double y;

  /// 这个点在原始 `values` 里的下标。**null 项不产生点**，所以相邻两点的
  /// [index] 可能不相邻 —— 中间跳过的那些就是「这一场没有可用于换算的组」。
  final int index;

  const ChartPoint({required this.x, required this.y, required this.index});
}

/// 一次 [layoutChart] 的结果。
class ChartLayout {
  /// 按 x 升序 —— 也就是按 [ChartPoint.index] 升序。null 项对应的地方没有点，
  /// 但线在 `TrendChart` 里直接连过去（缺口不画断）。
  final List<ChartPoint> points;

  /// 最大值所在的**第一个** `values` 下标；并列时取最早的 ——
  /// 语义是「你**第一次**做到这个数」，不是「你最近一次做到」。
  ///
  /// ⚠️ 坐标系是 [ChartPoint.index] 那一套（`values` 的下标），
  /// **不是 `points` 的下标** —— 有 null 时两者会错开。用法是
  /// `points.firstWhere((p) => p.index == highlightIndex)`；
  /// 按 `points[highlightIndex]` 取会越界或取错点。
  ///
  /// 全为 null 或空列表时为 null。
  final int? highlightIndex;

  /// 非 null 值的范围。没有任何非 null 值时两者都是 0 ——
  /// 此时 [points] 也是空的，没有点会拿这个范围去画。
  final double minValue;
  final double maxValue;

  /// `values` 里 null 的个数（= 没有点的场次数）。
  /// 动作详情页用它写「有 N 次训练没有可用于换算的组」（规格 §5）。
  final int gapCount;

  const ChartLayout({
    required this.points,
    required this.highlightIndex,
    required this.minValue,
    required this.maxValue,
    required this.gapCount,
  });
}

/// 把 [values] 映射到 `width × height` 的画布上，一个下标一列。
///
/// [values] 的每一项是**一场训练**（或一次测量），null 表示这一场没有值
/// —— 例如 e1RM 序列里次数全 > 10 的那一场（规格 §2.1）。
///
/// 三条规矩（规格 §2.2，都是取舍不是疏忽）：
///
/// 1. **x 按索引等距**，不按时间。这张图回答「我一次比一次强吗」，不是
///    「我几月几号练了多少」。按时间画的话，一周练五次再歇三周，前面五次
///    会挤成一坨。代价（明确接受）：**看不出中间歇了多久**。
/// 2. **y 取 `min..max`，不强制从 0**。进步曲线关心的是变化量，从 0 起会
///    把变化压平。代价（明确接受）：**看起来涨得比实际猛** —— 所以图上
///    不画 y 轴刻度，数值一律由卡片头上的「最好值 · 日期」给出。
/// 3. **全等值时竖直居中**（`y = height / 2`，比如连续三次都是 60kg）。
///    不除零（会得 NaN，整个图消失），也不贴底 —— **底边会被读成 0**，
///    而「三次都是 60kg」是「稳定」，不是「退步到 0」。
///
/// [insetY] 是上下留白：极值点上要画圆点（高亮那个还更大），贴着边画会被
/// 裁掉半边。默认 12 够放半径 4~6 的点。
ChartLayout layoutChart({
  required List<double?> values,
  required double width,
  required double height,
  double insetY = 12,
}) {
  var gapCount = 0;
  double? minValue;
  double? maxValue;
  int? highlightIndex;

  for (var i = 0; i < values.length; i++) {
    final v = values[i];
    if (v == null) {
      gapCount++;
      continue;
    }
    if (minValue == null || v < minValue) minValue = v;
    // 用**严格大于**：并列时 highlightIndex 停在更早的那个下标上
    if (maxValue == null || v > maxValue) {
      maxValue = v;
      highlightIndex = i;
    }
  }

  final points = <ChartPoint>[];
  final min = minValue;
  final max = maxValue;
  if (min != null && max != null) {
    final flat = min == max;
    final lastIndex = values.length - 1;

    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      if (v == null) continue;

      // 只有一个元素时 (values.length - 1) == 0，除零会得 NaN，放中间
      final x = values.length == 1 ? width / 2 : i / lastIndex * width;

      // flat 时把 (v - min) / (max - min) 换掉 —— 那是 0 / 0
      final y = flat
          ? height / 2
          : height - insetY - (v - min) / (max - min) * (height - 2 * insetY);

      points.add(ChartPoint(x: x, y: y, index: i));
    }
  }

  return ChartLayout(
    points: points,
    highlightIndex: highlightIndex,
    minValue: min ?? 0,
    maxValue: max ?? 0,
    gapCount: gapCount,
  );
}
