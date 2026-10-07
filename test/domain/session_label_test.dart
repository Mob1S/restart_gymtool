import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/domain/session_label.dart';

ExerciseProgress ex(String name, int done, {int pending = 0}) => ExerciseProgress(
      exerciseName: name,
      sets: [
        ...List.generate(done, (_) => const SetProgress(isCompleted: true)),
        ...List.generate(pending, (_) => const SetProgress(isCompleted: false)),
      ],
    );

void main() {
  test('一个动作都没有 → 「还没有动作」', () {
    expect(describeExercises([]), '还没有动作');
  });

  test('单个动作不加「等」', () {
    expect(describeExercises([ex('深蹲', 2)]), '深蹲 · 已记 2 组');
  });

  test('多个动作说「等 N 个动作」', () {
    expect(
      describeExercises([ex('深蹲', 2), ex('卧推', 3), ex('硬拉', 0)]),
      '深蹲 等 3 个动作 · 已记 5 组',
    );
  });

  test('未完成的占位组不计入「已记」', () {
    expect(describeExercises([ex('深蹲', 2, pending: 1)]), '深蹲 · 已记 2 组');
  });

  test('一组都没完成时说「已记 0 组」', () {
    expect(describeExercises([ex('深蹲', 0, pending: 1)]), '深蹲 · 已记 0 组');
  });
}
