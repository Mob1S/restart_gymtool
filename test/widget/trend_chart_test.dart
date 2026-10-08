import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/domain/chart_geometry.dart';
import 'package:gym_tracker/ui/theme.dart';
import 'package:gym_tracker/ui/tokens.dart';
import 'package:gym_tracker/ui/widgets/trend_chart.dart';

/// `TrendChart` 的绘制冒烟守卫：**退化输入不许崩**。
///
/// 几何（坐标算得对不对）由 `test/domain/chart_geometry_test.dart` 锁死，
/// 这里不重抄一遍 —— 本文件只回答「照着一份几何去画，会不会抛」。下列五种
/// 输入现实里都会出现：空列表、全 null、单点（只练过一次）、全等值（连续几次
/// 同重量）、中间有 null（那一场次数全 > 10）。
///
/// 唯一超出冒烟范围的是 ⭐ 那条高亮点断言，理由写在它自己的注释里。
void main() {
  const chartWidth = 200.0;

  Future<void> pumpChart(
    WidgetTester tester,
    List<double?> values, {
    bool compact = false,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(AppColors.dark),
        home: Center(
          child: SizedBox(
            width: chartWidth,
            child: TrendChart(values: values, compact: compact),
          ),
        ),
      ),
    );
  }

  /// widget 里那个 `CustomPaint` —— `paints` / `paintsNothing` 收的就是
  /// 一个 Finder 或 RenderObject。
  Finder canvas() => find.descendant(
    of: find.byType(TrendChart),
    matching: find.byType(CustomPaint),
  );

  /// 期望坐标仍由 `layoutChart` 给：测试里手算等于把几何再写一遍，两处一起
  /// 错就永远照不出来。尺寸从 RenderObject 取 —— widget 内部还有一层左右
  /// 留白，不能拿 `TrendChart` 自己的尺寸去算。
  ChartLayout expected(WidgetTester tester, List<double?> values) {
    final size = tester.getSize(canvas());
    return layoutChart(values: values, width: size.width, height: size.height);
  }

  testWidgets('空列表：不崩，什么也不画', (tester) async {
    await pumpChart(tester, const []);
    expect(tester.takeException(), isNull);
    expect(canvas(), paintsNothing);
  });

  testWidgets('全 null：不崩，什么也不画（不许补一条平的线冒充走势）', (tester) async {
    await pumpChart(tester, const [null, null, null]);
    expect(tester.takeException(), isNull);
    expect(canvas(), paintsNothing);
  });

  testWidgets('只有一个点：不崩，线画不出来但点要画出来', (tester) async {
    await pumpChart(tester, const [60]);
    expect(tester.takeException(), isNull);

    final point = expected(tester, const [60]).points.single;
    // 唯一的点同时就是最大值，所以按规则是高亮那个（success、更大）——
    // 这不是漏画，是「只练过一次」时高亮落在它身上。
    expect(
      canvas(),
      paints..circle(x: point.x, y: point.y, color: AppColors.dark.success),
    );
  });

  testWidgets('全等值：不崩，三个点都画（y 走竖直居中，不是 NaN）', (tester) async {
    await pumpChart(tester, const [60, 60, 60]);
    expect(tester.takeException(), isNull);
    expect(canvas(), paintsExactlyCountTimes(#drawCircle, 3));
  });

  testWidgets('中间有 null：不崩，点只有两个（缺口不产生点）', (tester) async {
    await pumpChart(tester, const [1, null, 3]);
    expect(tester.takeException(), isNull);
    expect(canvas(), paintsExactlyCountTimes(#drawCircle, 2));
  });

  testWidgets('⭐ 高亮点画在 values[highlightIndex] 那个点上，不是 points 里同下标的点', (
    tester,
  ) async {
    // [null, 5, 3]：最大值 5 在下标 1，而它在 points 里排第 0 个 ——
    // `points[highlightIndex]` 会点在最右、最下那个点（值为 3 的那个）上：
    // **图错了却不抛**，所以「不崩」守不住它，只能断言坐标。
    await pumpChart(tester, const [null, 5, 3]);
    expect(tester.takeException(), isNull);

    final layout = expected(tester, const [null, 5, 3]);
    final highlight = layout.points.firstWhere(
      (point) => point.index == layout.highlightIndex,
    );
    final plain = layout.points.firstWhere(
      (point) => point.index != layout.highlightIndex,
    );

    // `paints` 的每个条件只按下标顺序去对「下一个」drawCircle，不跳着找 ——
    // 所以两个圆都要写出来：先普通点，再高亮点（painter 也是这个顺序）。
    // 取错下标时，第二句会撞上画错位置的那个绿点。
    expect(
      canvas(),
      paints
        ..circle(x: plain.x, y: plain.y, color: AppColors.dark.accent)
        ..circle(x: highlight.x, y: highlight.y, color: AppColors.dark.success),
    );
  });

  testWidgets('compact：不崩，只画最后一个点（迷你走势不给高亮）', (tester) async {
    await pumpChart(tester, const [1, 3, 2], compact: true);
    expect(tester.takeException(), isNull);
    expect(canvas(), paintsExactlyCountTimes(#drawCircle, 1));
  });

  testWidgets('compact 的退化输入：空列表 / 全 null / 单点都不崩', (tester) async {
    await pumpChart(tester, const [], compact: true);
    expect(tester.takeException(), isNull);

    await pumpChart(tester, const [null, null], compact: true);
    expect(tester.takeException(), isNull);

    await pumpChart(tester, const [60], compact: true);
    expect(tester.takeException(), isNull);
    expect(canvas(), paintsExactlyCountTimes(#drawCircle, 1));
  });
}
