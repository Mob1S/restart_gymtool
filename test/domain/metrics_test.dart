import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/domain/metrics.dart';
import 'package:gym_tracker/domain/types.dart';

SetLike s(double w, int r, {bool done = true}) =>
    SetLike(weight: w, reps: r, isCompleted: done);

void main() {
  group('totalVolumeLoad', () {
    test('累加 重量 × 次数', () {
      expect(totalVolumeLoad([s(20, 8), s(20, 8)]), 320);
    });

    test('未完成的组不计入', () {
      expect(totalVolumeLoad([s(20, 8), s(100, 10, done: false)]), 160);
    });

    test('空数组返回 0', () {
      expect(totalVolumeLoad([]), 0);
    });
  });

  group('estimateOneRepMax', () {
    test('reps 为 1 时直接返回实测重量', () {
      expect(estimateOneRepMax(100, 1), 100);
    });

    test('reps 为 0 或负数时返回 null', () {
      expect(estimateOneRepMax(100, 0), isNull);
      expect(estimateOneRepMax(100, -1), isNull);
    });

    test('reps 大于 10 时返回 null（外推失真，界面必须不显示）', () {
      expect(estimateOneRepMax(60, 11), isNull);
      expect(estimateOneRepMax(60, 20), isNull);
    });

    test('50kg × 8 次 → 62.32（三公式平均，锁住口径）', () {
      // Epley 63.33 / Brzycki 62.07 / Lombardi 61.56 → 平均 62.32
      expect(estimateOneRepMax(50, 8), closeTo(62.32, 0.01));
    });

    test('52.5kg × 8 次 → 65.43（锁住第二条真实数据）', () {
      expect(estimateOneRepMax(52.5, 8), closeTo(65.43, 0.01));
    });

    test('60×10 的 e1RM 高于 70×3 —— 「最佳 e1RM」不一定来自最重的那组', () {
      expect(estimateOneRepMax(60, 10)!,
          greaterThan(estimateOneRepMax(70, 3)!));
    });
  });
}
