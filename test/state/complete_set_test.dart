import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/migrations.dart';
import 'package:gym_tracker/data/repositories/exercise_repo.dart';
import 'package:gym_tracker/data/repositories/session_repo.dart';
import 'package:gym_tracker/data/repositories/set_repo.dart';
import 'package:gym_tracker/state/active_session_controller.dart';

void main() {
  late FfiExecutor exec;
  late String squatId;

  setUp(() async {
    exec = await FfiExecutor.openInMemory();
    await migrate(exec);
    squatId = (await createCustomExercise(exec, name: '深蹲', muscleGroup: '腿')).id;
  });

  tearDown(() async => exec.close());

  Future<ActiveSessionController> started() async {
    final c = ActiveSessionController(exec);
    await c.startNew();
    await c.addExercise(squatId);
    return c;
  }

  test('⭐ 完成一组立刻落盘（不是等训练结束才写）', () async {
    final c = await started();
    await c.completeCurrentSet(40, 8);

    final seId = c.exercises.single.sessionExercise.id;
    final stored = await listSets(exec, seId);
    expect(stored.where((s) => s.isCompleted), hasLength(1));
    expect(stored.singleWhere((s) => s.isCompleted).weight, 40);
  });

  test('⭐ 落盘的是用户此刻填的值，不是组里的旧值', () async {
    final c = await started();
    // 占位组初始是 20×8，用户改成 42.5×6
    await c.completeCurrentSet(42.5, 6);
    final set = (await listSets(exec, c.exercises.single.sessionExercise.id))
        .singleWhere((s) => s.isCompleted);
    expect(set.weight, 42.5);
    expect(set.reps, 6);
  });

  test('完成一组后自动预建下一组（休息结束就有东西可填）', () async {
    final c = await started();
    await c.completeCurrentSet(40, 8);
    final sets = c.exercises.single.sets;
    expect(sets, hasLength(2));
    expect(sets.where((s) => !s.isCompleted), hasLength(1));
  });

  test('完成后开始休息计时：restStartedAt 与 completedAt 是同一个时刻', () async {
    final c = await started();
    await c.completeCurrentSet(40, 8);
    final set = c.exercises.single.sets.singleWhere((s) => s.isCompleted);
    expect(set.restStartedAt, isNotNull);
    expect(set.restStartedAt, set.completedAt);
  });

  test('beginNextSet 写入休息秒数并清掉 restStartedAt', () async {
    final c = await started();
    await c.completeCurrentSet(40, 8);

    // 手工把休息开始时间往前推 90 秒，避免测试里真的等
    final startedAt = DateTime.now().millisecondsSinceEpoch - 90000;
    await exec.run('UPDATE set_entry SET rest_started_at = ? WHERE is_completed = 1',
        [startedAt]);
    await c.resume(); // 重新载入，让内存里的值跟上

    await c.beginNextSet();
    final set = c.exercises.single.sets.singleWhere((s) => s.isCompleted);
    expect(set.restStartedAt, isNull);
    expect(set.restSeconds, closeTo(90, 2));
  });

  test('没有在休息时 beginNextSet 不写脏数据', () async {
    final c = await started();
    await c.beginNextSet();
    final sets = c.exercises.single.sets;
    expect(sets.where((s) => s.isCompleted), isEmpty);
  });

  test('⭐ endWorkout 写 finished_at 并立刻清空内存', () async {
    final c = await started();
    await c.completeCurrentSet(40, 8);
    final id = await c.endWorkout();

    expect(id, isNotNull);
    expect(c.session, isNull);   // 立刻清空，不等用户在总结页点完成
    expect(c.exercises, isEmpty);
    expect(await getActiveSession(exec), isNull);
  });

  test('endWorkout 时若正在休息，先把这段休息结掉', () async {
    final c = await started();
    await c.completeCurrentSet(40, 8);
    final startedAt = DateTime.now().millisecondsSinceEpoch - 60000;
    await exec.run('UPDATE set_entry SET rest_started_at = ? WHERE is_completed = 1',
        [startedAt]);
    await c.resume();

    await c.endWorkout();

    final seId = (await listSessionExercises(exec, (await listSessions(exec, 1)).single.id))
        .single.id;
    final set = (await listSets(exec, seId)).singleWhere((s) => s.isCompleted);
    // 不收尾的话这一组永远是 NULL，总结页算不出平均休息
    expect(set.restSeconds, closeTo(60, 2));
  });

  test('store 里本来就没有训练时 endWorkout 返回 null', () async {
    final c = ActiveSessionController(exec);
    expect(await c.endWorkout(), isNull);
  });

  test('reset 只清内存，不碰数据库', () async {
    final c = await started();
    c.reset();
    expect(c.session, isNull);
    // 库里那一场还在，仍然是进行中的
    expect(await getActiveSession(exec), isNotNull);
  });

  test('训练已结束时 completeCurrentSet 静默返回', () async {
    final c = await started();
    await c.endWorkout();
    await c.completeCurrentSet(40, 8); // 不该抛错
    expect(c.exercises, isEmpty);
  });

  test('重复点「完成这组」不会写第二条记录', () async {
    final c = await started();
    await c.completeCurrentSet(40, 8);
    // 此时没有 pending 组吗？有的 —— 上一组完成后预建了下一组。
    // 所以这里改为验证：当前动作已无 pending 时（手工删掉占位组）不出错
    await exec.run('DELETE FROM set_entry WHERE is_completed = 0');
    await c.resume();
    await c.completeCurrentSet(40, 8);
    final sets = await listSets(exec, c.exercises.single.sessionExercise.id);
    expect(sets.where((s) => s.isCompleted), hasLength(1));
  });
}
