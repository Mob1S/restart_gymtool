import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/domain/rest.dart';
import 'package:gym_tracker/domain/types.dart';

const t0 = 1700000000000;

SetEntry set({
  required String id,
  bool done = true,
  int? restStartedAt,
}) =>
    SetEntry(
      id: id,
      sessionExerciseId: 'se1',
      position: 0,
      weight: 20,
      reps: 8,
      isCompleted: done,
      restStartedAt: restStartedAt,
    );

void main() {
  group('isStaleRest', () {
    test('没在休息时永远不 stale', () {
      expect(isStaleRest(null, t0 + 99999999), isFalse);
    });

    test('刚好 30 分钟不算过头（阈值是「超过」而非「达到」）', () {
      expect(isStaleRest(t0, t0 + staleRestThresholdMs), isFalse);
    });

    test('超过 30 分钟算过头', () {
      expect(isStaleRest(t0, t0 + staleRestThresholdMs + 1), isTrue);
    });

    test('29 分钟的正常长休息不能被误伤', () {
      expect(isStaleRest(t0, t0 + 29 * 60 * 1000), isFalse);
    });
  });

  group('findStaleRest', () {
    test('没有正在休息的组时返回 null', () {
      expect(findStaleRest([set(id: 'a')], t0), isNull);
    });

    test('找到那段跑过头的休息', () {
      final sets = [
        set(id: 'a', restStartedAt: t0),
        set(id: 'b', restStartedAt: t0 + 31 * 60 * 1000),
      ];
      // t0 那一组已经超过 30 分钟；t0+31min 那一组才刚开始
      expect(findStaleRest(sets, t0 + 31 * 60 * 1000)?.id, 'a');
    });

    test('未完成的组即使带着时间戳也不认（它不该在休息）', () {
      final sets = [set(id: 'a', done: false, restStartedAt: t0)];
      expect(findStaleRest(sets, t0 + 40 * 60 * 1000), isNull);
    });
  });
}
