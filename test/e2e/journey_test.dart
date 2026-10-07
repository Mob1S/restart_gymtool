import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/migrations.dart';
import 'package:gym_tracker/data/repositories/exercise_repo.dart';
import 'package:gym_tracker/data/repositories/session_repo.dart';
import 'package:gym_tracker/data/repositories/set_repo.dart';
import 'package:gym_tracker/domain/metrics.dart';
import 'package:gym_tracker/domain/rest_advice.dart';
import 'package:gym_tracker/domain/types.dart';
import 'package:gym_tracker/state/active_session_controller.dart';

/// 端到端回归：一条链串起 5 条主旅程。
///
/// 它跨了 exerciseRepo / sessionRepo / setRepo / ActiveSessionController 四处，
/// **没有任何分层测试覆盖这条链**。旧项目这条链第一次跑就抓出了一个分层测试
/// 没抓到的问题（判据写岔，而分层测试里那条用例同时写错了同一个判据）。
void main() {
  late FfiExecutor exec;

  setUp(() async {
    exec = await FfiExecutor.openInMemory();
    await migrate(exec);
    await seedExercisesIfEmpty(exec);
  });

  tearDown(() async => exec.close());

  test('主旅程：播种 → 开训练 → 加动作 → 完成多组 → 结束 → 数据落地正确', () async {
    // ── 旅程 1：全新库播种 ──
    final all = await listExercises(exec);
    expect(all, hasLength(52));

    final squat = all.firstWhere((e) => e.name == '深蹲');
    final bench = all.firstWhere((e) => e.name == '卧推');

    // ── 旅程 2：开一场训练并加两个动作 ──
    final c = ActiveSessionController(exec);
    expect(await c.startNew(), StartResult.started);
    await c.addExercise(squat.id);
    await c.addExercise(bench.id);
    expect(c.exercises, hasLength(2));
    expect(c.currentIndex, 1);

    // ── 旅程 3：在深蹲上完成 3 组，中间有休息 ──
    c.setCurrentIndex(0);
    final seId = c.exercises[0].sessionExercise.id;

    for (var i = 0; i < 3; i++) {
      await c.completeCurrentSet(40, 8);
      // 模拟 90 秒休息：把开始时间往前推，再结束它。
      //
      // `AND rest_started_at IS NOT NULL` 这一条不能省 —— 没有它，这条
      // UPDATE 会连**上一组已经结束掉的那段休息**一起重新点亮（第 2 轮循环时
      // 第 0 组的 rest_seconds 已是 90、rest_started_at 已是 NULL），于是同时
      // 出现两段「进行中」的休息，而 beginNextSet 只结束它找到的第一段
      // （position 最小的那组），第 1 组那段就被永久留在运行中、rest_seconds
      // 永远是 null。实测证据（临时探针脚本逐轮 dump）：
      //   宽 WHERE    → beginNext i=1 之后 pos0[started=0] pos1[started=1]
      //   收窄 WHERE  → beginNext i=1 之后 pos0[started=0] pos1[started=0] rs=90
      // 「同时两段休息在跑」这个状态在真实 App 里到不了：记录页在休息期间整个
      // body 被 RestView 顶替（计划 6287-6298 行），「完成这组」根本不在屏幕上。
      // 所以这里是模拟手法写宽了，不是实现错了。
      if (i < 2) {
        final back = DateTime.now().millisecondsSinceEpoch - 90000;
        await exec.run(
          '''UPDATE set_entry SET rest_started_at = ?
               WHERE session_exercise_id = ? AND is_completed = 1
                 AND rest_started_at IS NOT NULL''',
          [back, seId],
        );
        await c.resume();
        await c.beginNextSet();
      }
    }

    final squatSets =
        (await listSets(exec, seId)).where((s) => s.isCompleted).toList();
    expect(squatSets, hasLength(3));
    expect(squatSets.every((s) => s.weight == 40 && s.reps == 8), isTrue);
    // 前两组有休息数据，最后一组没有（它后面没有休息）
    expect(squatSets[0].restSeconds, closeTo(90, 2));
    expect(squatSets[1].restSeconds, closeTo(90, 2));
    expect(squatSets[2].restSeconds, isNull);

    // ── 旅程 4：结束训练，controller 立刻清空 ──
    final finishedId = await c.endWorkout();
    expect(finishedId, isNotNull);
    expect(c.session, isNull);
    expect(await getActiveSession(exec), isNull);

    // ── 旅程 5：数据落地逐字段核对 ──
    final stored = (await listSessions(exec, 50)).single;
    expect(stored.id, finishedId);
    expect(stored.finishedAt, isNotNull);

    final storedSets = await listSets(exec, seId);
    expect(storedSets.where((s) => s.isCompleted), hasLength(3));
    // 未完成的占位组留着，不清理 —— 各处靠 is_completed 排除它
    expect(storedSets.where((s) => !s.isCompleted), hasLength(1));

    // `SetEntry` 与 `SetLike` 是两个独立的类（`SetLike` 是算容量负荷所需的
    // 最小形状，见 domain/types.dart），这里显式折算一次再交给 metrics。
    final volume = totalVolumeLoad(squatSets
        .map((s) => SetLike(
              weight: s.weight,
              reps: s.reps,
              isCompleted: s.isCompleted,
            ))
        .toList());
    expect(volume, 40 * 8 * 3); // 960

    final feedback = buildRestFeedback(
      squatSets.map((s) => s.reps).toList(),
      squatSets.map((s) => s.restSeconds).toList(),
    )!;
    expect(feedback.kind, RestFeedbackKind.positive);
    expect(feedback.message, contains('8 / 8 / 8'));
  });

  test('主旅程：强杀后 resume 能恢复，且「上次成绩」被下一场沿用', () async {
    final all = await listExercises(exec);
    final squat = all.firstWhere((e) => e.name == '深蹲');

    // 第一场：练 3 组 40kg
    final c1 = ActiveSessionController(exec);
    await c1.startNew();
    await c1.addExercise(squat.id);
    for (var i = 0; i < 3; i++) {
      await c1.completeCurrentSet(40, 5);
    }
    await c1.endWorkout();

    // 第二场：新 controller（模拟重开 App）
    final c2 = ActiveSessionController(exec);
    expect(await c2.startNew(), StartResult.started);
    // 动作组合应被复制过来
    expect(c2.exercises.single.exerciseName, '深蹲');
    // 第一组应预填上次的 40kg × 5
    expect(c2.exercises.single.sets.single.weight, 40);
    expect(c2.exercises.single.sets.single.reps, 5);
  });

  test('主旅程：训练中强杀 → 重开 resume 捡回那一场，且组数正确', () async {
    final all = await listExercises(exec);
    final squat = all.firstWhere((e) => e.name == '深蹲');

    final c1 = ActiveSessionController(exec);
    await c1.startNew();
    await c1.addExercise(squat.id);
    await c1.completeCurrentSet(40, 5);
    await c1.completeCurrentSet(40, 5);
    // 不调 endWorkout —— 模拟进程被强杀

    final c2 = ActiveSessionController(exec);
    expect(await c2.resume(), isTrue);
    final done = c2.exercises.single.sets.where((s) => s.isCompleted);
    expect(done, hasLength(2));
    // 还有一组待完成，界面才能继续记
    expect(c2.exercises.single.sets.where((s) => !s.isCompleted), hasLength(1));
  });

  test('主旅程：冲突 —— 有进行中的训练时不新建，且那一场可直接接着练', () async {
    final all = await listExercises(exec);
    final squat = all.firstWhere((e) => e.name == '深蹲');

    final c1 = ActiveSessionController(exec);
    await c1.startNew();
    await c1.addExercise(squat.id);

    final c2 = ActiveSessionController(exec);
    expect(await c2.startNew(), StartResult.conflict);
    // ⭐ 那一场必须已装进 controller，否则「接着练」进到一屏空白
    expect(c2.exercises, hasLength(1));

    final rows = await exec.all("SELECT id FROM session WHERE finished_at IS NULL");
    expect(rows, hasLength(1));
  });

  test('主旅程：30 分钟闸门 —— 隔夜打开不会被堵在休息页，也不污染休息数据', () async {
    final all = await listExercises(exec);
    final squat = all.firstWhere((e) => e.name == '深蹲');

    final c1 = ActiveSessionController(exec);
    await c1.startNew();
    await c1.addExercise(squat.id);
    await c1.completeCurrentSet(40, 5);

    // 把休息开始时间推到 8 小时前 —— 显然是忘了按「开始下一组」
    await exec.run('UPDATE set_entry SET rest_started_at = ?',
        [DateTime.now().millisecondsSinceEpoch - 8 * 3600 * 1000]);

    final c2 = ActiveSessionController(exec);
    await c2.resume();
    final done = c2.exercises.single.sets.singleWhere((s) => s.isCompleted);
    expect(done.restStartedAt, isNull);
    // 关键：8 小时不能被记成真实休息，否则平均值彻底带偏
    expect(done.restSeconds, isNull);
  });
}
