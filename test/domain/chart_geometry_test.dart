import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/domain/chart_geometry.dart';

/// 画布尺寸写成常量：几何测试的每个期望值都要能手算复核，
/// 期望值里掺进变量就没人核得动了。
const _width = 200.0;
const _height = 100.0;

/// 默认 insetY 的期望值（与实现里那个默认值无关，故意手算写死）。
const _insetY = 12.0;

ChartLayout _layout(List<double?> values) =>
    layoutChart(values: values, width: _width, height: _height);

void main() {
  group('layoutChart', () {
    test('1. 单元素：x 居中而非除零，y 也居中', () {
      final layout = _layout([60]);
      expect(layout.points, hasLength(1));
      expect(layout.points.single.index, 0);
      expect(layout.points.single.x, _width / 2);
      // 只有一个值 = min == max，走竖直居中那条路，不是 NaN
      expect(layout.points.single.y, _height / 2);
      expect(layout.highlightIndex, 0);
      expect(layout.gapCount, 0);
    });

    test('2. 全等值 [60,60,60]：三点全部竖直居中，不除零、不贴底', () {
      final layout = _layout([60, 60, 60]);
      expect(layout.points, hasLength(3));
      for (final p in layout.points) {
        // 贴底（y = height - insetY = 88）会被读成 0；0/0 会得 NaN。
        // 两者都过不了这条断言。
        expect(p.y, _height / 2, reason: 'min == max 时必须居中，下标 ${p.index}');
      }
      expect(layout.points.map((p) => p.x), [0, _width / 2, _width]);
      expect(layout.minValue, 60);
      expect(layout.maxValue, 60);
    });

    test('3. y 取 min..max 而不是 0..max：[100,110] 的最低点落在下边距上', () {
      final layout = _layout([100, 110]);
      expect(layout.minValue, 100);
      expect(layout.maxValue, 110);
      // 从 0 起缩放的话 100 会落在 88 - 100/110*76 ≈ 18.9，不是 88
      expect(layout.points[0].y, _height - _insetY);
      expect(layout.points[1].y, _insetY);
    });

    test('4. 高亮点是最大值不是最新值：[100,50,80] → highlightIndex == 0', () {
      final layout = _layout([100, 50, 80]);
      expect(layout.highlightIndex, 0);
      expect(layout.points[0].y, _insetY);
      expect(layout.points[1].y, _height - _insetY);
      expect(layout.points[2].y, closeTo(42.4, 0.001));
    });

    test('5. 最大值并列取最早：[80,100,100] → highlightIndex == 1', () {
      final layout = _layout([80, 100, 100]);
      expect(layout.highlightIndex, 1, reason: '语义是「第一次做到这个数」，不是最后一次');
      expect(layout.maxValue, 100);
    });

    test('6. null 不产生点但计入 gapCount：[1,null,3]', () {
      final layout = _layout([1, null, 3]);
      expect(layout.points, hasLength(2));
      expect(layout.points[0].index, 0);
      expect(layout.points[1].index, 2);
      expect(layout.gapCount, 1);
      // x 按**原始下标**等距：index 2 落在右边缘，中间的空档不被挤掉
      expect(layout.points[0].x, 0);
      expect(layout.points[1].x, _width);
      // y 的缩放不受 null 影响
      expect(layout.points[0].y, _height - _insetY);
      expect(layout.points[1].y, _insetY);
      expect(layout.highlightIndex, 2);
    });

    test('7. 全 null：没有点、没有高亮，不崩', () {
      final layout = _layout([null, null, null]);
      expect(layout.points, isEmpty);
      expect(layout.highlightIndex, isNull);
      expect(layout.gapCount, 3);
      expect(layout.minValue, 0);
      expect(layout.maxValue, 0);
    });

    test('8. 空列表：与全 null 一样安静', () {
      final layout = _layout([]);
      expect(layout.points, isEmpty);
      expect(layout.highlightIndex, isNull);
      expect(layout.gapCount, 0);
    });

    test('9. highlightIndex 是 values 的下标，不是 points 的下标', () {
      // [null, 5, 3]：最大值 5 在 values 下标 1，但在 points 里排第 0 个。
      // 两种口径在这里给出不同的数（1 vs 0），只能有一个是对的。
      final layout = _layout([null, 5, 3]);
      expect(layout.points.map((p) => p.index), [1, 2]);
      expect(layout.highlightIndex, 1);
      // 画的时候靠 index 找高亮点；取错口径这条会抛 StateError
      expect(
        layout.points.singleWhere((p) => p.index == layout.highlightIndex).y,
        _insetY,
      );
    });
  });
}
