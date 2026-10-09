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
    squatId = (await createCustomExercise(
      exec,
      name: '深蹲',
      muscleGroup: '腿',
    )).id;
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
    final set = (await listSets(
      exec,
      c.exercises.single.sessionExercise.id,
    )).singleWhere((s) => s.isCompleted);
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
    await exec.run(
      'UPDATE set_entry SET rest_started_at = ? WHERE is_completed = 1',
      [startedAt],
    );
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
    expect(c.session, isNull); // 立刻清空，不等用户在总结页点完成
    expect(c.exercises, isEmpty);
    expect(await getActiveSession(exec), isNull);
  });

  test('⭐ endWorkout 丢掉正在进行的那段休息，不把它写成 rest_seconds', () async {
    final c = await started();
    await c.completeCurrentSet(40, 8);
    final startedAt = DateTime.now().millisecondsSinceEpoch - 60000;
    await exec.run(
      'UPDATE set_entry SET rest_started_at = ? WHERE is_completed = 1',
      [startedAt],
    );
    await c.resume();

    await c.endWorkout();

    final seId = (await listSessionExercises(
      exec,
      (await listSessions(exec, 1)).single.id,
    )).single.id;
    final set = (await listSets(exec, seId)).singleWhere((s) => s.isCompleted);

    // 这一段是「做完最后一组到按下结束」的间隔，**不可知** ——
    // 用户可能在收杠铃，也可能已经揣兜里了。写进库就是伪造：
    // 实测 `[300, 300, 3]` 会让屏幕显示「平均歇了 3 分 21 秒」，
    // 而真实休息是 5 分 00 秒；还会把 200 秒那组从 addWeight 压成 positive。
    //
    // ⚠️ 这一条以前断言的是 `closeTo(60, 2)`（把它结掉）。改成 `isNull`
    // 是**产品口径的改动**，不是测试写错了 —— 理由见 `endWorkout` 的注释。
    expect(set.restSeconds, isNull, reason: '末组那段休息不是真实的组间休息，必须留空而不是编一个数');
    expect(
      set.restStartedAt,
      isNull,
      reason: '光把 rest_seconds 留空还不够 —— rest_started_at 也要清掉',
    );
  });

  test('⭐ 用户按过「开始下一组」再结束 → 那一段是用户确认过的，要留下', () async {
    // 上面那条的反面。差别在于**那一按**：按下「开始下一组」等于用户声明
    // 「我歇够了」，所以 `beginNextSet` 走 `endRest` 把真实时长写下来；
    // 此后 `endWorkout` 找不到进行中的休息，不该去动它。
    final c = await started();
    await c.completeCurrentSet(40, 8);
    await exec.run(
      'UPDATE set_entry SET rest_started_at = ? WHERE is_completed = 1',
      [DateTime.now().millisecondsSinceEpoch - 60000],
    );
    await c.resume();
    await c.beginNextSet();

    await c.endWorkout();

    final seId = (await listSessionExercises(
      exec,
      (await listSessions(exec, 1)).single.id,
    )).single.id;
    final set = (await listSets(exec, seId)).singleWhere((s) => s.isCompleted);
    expect(
      set.restSeconds,
      closeTo(60, 2),
      reason: '用户按了「开始下一组」，这段休息是他确认过的，不许被丢掉',
    );
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

  test('⭐ 休息期间切到另一个动作并完成一组 —— 上一段休息不能被丢掉', () async {
    // 这条路径是**界面真实可达的**，不是假想：
    // 记录页的动作条渲染在 body 之外（换动作不必退出记录界面，这是刻意的），
    // 而 body 只在**当前动作**在休息时才显示休息界面。所以：
    //   深蹲完成一组（进入休息）→ 点动作条切到卧推 → body 变回记录态
    //   → 点「完成这组」→ 两段休息同时在跑。
    //
    // 若不拦，beginNextSet / endWorkout 只会结束找到的那一段，
    // 另一段的 rest_seconds **永远是 NULL** —— 总结页平均休息少一个数据点，
    // 而且**不报错**。这是「同时至多一段休息在进行」这条不变量的意义。
    final benchId = (await createCustomExercise(
      exec,
      name: '卧推',
      muscleGroup: '胸',
    )).id;

    final c = ActiveSessionController(exec);
    await c.startNew();
    await c.addExercise(squatId);
    await c.addExercise(benchId);

    // 深蹲完成一组 → 深蹲进入休息
    c.setCurrentIndex(0);
    await c.completeCurrentSet(40, 8);
    final squatSeId = c.exercises[0].sessionExercise.id;
    final squatRestingBefore = (await listSets(
      exec,
      squatSeId,
    )).singleWhere((s) => s.isCompleted).restStartedAt;
    expect(squatRestingBefore, isNotNull, reason: '前置条件：深蹲此时应在休息中');

    // 手工把那一段休息的起点往前推 90 秒（避免测试真的等）
    await exec.run(
      'UPDATE set_entry SET rest_started_at = ? WHERE id IN '
      '(SELECT id FROM set_entry WHERE session_exercise_id = ? AND is_completed = 1)',
      [DateTime.now().millisecondsSinceEpoch - 90000, squatSeId],
    );
    await c.resume();

    // 切到卧推，完成一组 —— 这一步以前会让两段休息同时进行
    c.setCurrentIndex(1);
    await c.completeCurrentSet(60, 8);

    // ① 深蹲那一段被**结掉且记下了真实时长**，不是被丢掉
    final squatSets = await listSets(exec, squatSeId);
    final squatDone = squatSets.singleWhere((s) => s.isCompleted);
    expect(squatDone.restStartedAt, isNull, reason: '深蹲那段休息应已被结束');
    expect(
      squatDone.restSeconds,
      closeTo(90, 2),
      reason: '深蹲那段休息的时长必须被记下来 —— 这正是「别丢数据」那条',
    );

    // ② 卧推那一段正在进行
    final benchSeId = c.exercises[1].sessionExercise.id;
    final benchDone = (await listSets(
      exec,
      benchSeId,
    )).singleWhere((s) => s.isCompleted);
    expect(benchDone.restStartedAt, isNotNull);

    // ③ 全库此时**至多一段**休息在进行
    final allResting = await exec.all<Map<String, Object?>>(
      'SELECT id FROM set_entry WHERE rest_started_at IS NOT NULL',
    );
    expect(
      allResting,
      hasLength(1),
      reason: '同时只允许一段休息在进行 —— 多一段就会有一组的 rest_seconds 永远是 NULL',
    );
  });
}
