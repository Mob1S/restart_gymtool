import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/domain/rotation.dart';
import 'package:gym_tracker/domain/training_plans.dart';

void main() {
  test('recommendation handles no days, missing days and wraparound', () {
    expect(recommendDay([], 'gone'), isNull);
    expect(recommendDay(['a', 'b', 'c'], null), 'a');
    expect(recommendDay(['a', 'b', 'c'], 'gone'), 'a');
    expect(recommendDay(['a', 'b', 'c'], 'a'), 'b');
    expect(recommendDay(['a', 'b', 'c'], 'c'), 'a');
    expect(recommendDay(['c', 'a', 'b'], 'c'), 'a');
  });
  test('drafts defensively copy their nested lists', () {
    final ids = ['exercise'];
    final day = TrainingDayDraft(name: 'Day', exerciseIds: ids);
    final days = [day];
    final plan = TrainingPlanDraft(name: 'Plan', days: days);
    ids.clear();
    days.clear();
    expect(plan.days.single.exerciseIds, ['exercise']);
    expect(() => plan.days.clear(), throwsUnsupportedError);
    expect(() => day.exerciseIds.clear(), throwsUnsupportedError);
  });
}
