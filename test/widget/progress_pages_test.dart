import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/sql_executor.dart';
import 'package:gym_tracker/data/repositories/exercise_repo.dart';
import 'package:gym_tracker/data/repositories/session_repo.dart';
import 'package:gym_tracker/data/repositories/set_repo.dart';
import 'package:gym_tracker/features/progress/exercise_detail_page.dart';
import 'package:gym_tracker/features/progress/progress_page.dart';
import 'package:gym_tracker/state/active_session_controller.dart';
import 'package:gym_tracker/ui/theme.dart';
import 'package:gym_tracker/ui/tokens.dart';
import 'package:gym_tracker/ui/widgets/app_card.dart';
import 'package:gym_tracker/ui/widgets/trend_chart.dart';
import 'package:provider/provider.dart';

/// 进步两条页面（列表 / 动作详情）的界面断言。
///
/// 工具与教训沿用 `widget/smoke_test.dart`：
/// - `settleReal` —— `flutter_test` 的假时钟推不动 sqlite ffi 的真 I/O，
///   用 `pumpAndSettle` 只会超时；
/// - 两个 provider 都要给，少一个页面会卡在加载态**而不报错**，
///   表现成「什么都没渲染」，很容易误判成异步没等到。
///
/// **这里不搭 `GoRouter`**：两页各自 pump 出来即可。路由表（`app/router.dart`）
/// 的接线由主 agent 负责，不该让这两页的断言依赖它 —— 所以「点行进详情」只断言
/// 行是可点的，不断言目标 URL。
///
/// 本文件守着三条产品红线（规格 §4.4）：
/// 1. 最大重量 / 估算 1RM 写「最好」，**总容量写「最高」**；
/// 2. `个人最好` 在动作详情页上**一次都不许出现**（容量是训练量，不是力量成绩）；
/// 3. 最大重量卡取的是**全部点位的最大值**，不是最近那一场的最重一组。
void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  /// 造一个已迁移 + 已播种的内存库（建库必须包在 `runAsync` 里，理由同 smoke_test）。
  Future<FfiExecutor> seededDb(WidgetTester tester) async {
    late FfiExecutor exec;
    await tester.runAsync(() async {
      exec = await FfiExecutor.openMigrated();
      await seedExercisesIfEmpty(exec);
    });
    return exec;
  }

  /// 造一场训练：练 [exerciseName] 这个动作，[sets] 是已完成的组，
  /// [placeholders] 是没完成的占位组（`is_completed = 0`）。返回动作 id。
  ///
  /// 开始时间显式写死，不用 `createSession` 记的真实 now —— 列表行的「最近」
  /// 与卡片头的「最好 · 日期」全靠它；「赌两次调用落在不同毫秒」那种写法会闪。
  ///
  /// 组走仓储的两步（[addSet] → [completeSet]）而不是手写 INSERT，
  /// 路径与记录界面一致。
  Future<String> seedSession(
    WidgetTester tester,
    FfiExecutor exec, {
    required String exerciseName,
    required int startedAt,
    List<(double, int)> sets = const [],
    List<(double, int)> placeholders = const [],
    bool finished = true,
  }) async {
    late String exerciseId;
    await tester.runAsync(() async {
      final exercise = (await listExercises(exec))
          .firstWhere((e) => e.name == exerciseName);
      exerciseId = exercise.id;

      final session = await createSession(exec, name: null);
      final se = await addExerciseToSession(exec, session.id, exercise.id);
      for (final (weight, reps) in sets) {
        final set = await addSet(exec, se.id, weight, reps);
        await completeSet(exec, set.id, startedAt);
      }
      for (final (weight, reps) in placeholders) {
        // 刻意不 completeSet：占位组是界面上的「下一组」，用户还没做过它
        await addSet(exec, se.id, weight, reps);
      }

      await exec.run(
        finished
            ? 'UPDATE session SET started_at = ?, finished_at = ? WHERE id = ?'
            : 'UPDATE session SET started_at = ? WHERE id = ?',
        finished
            ? [startedAt, startedAt + 60000, session.id]
            : [startedAt, session.id],
      );
    });
    return exerciseId;
  }

  /// 让**真实异步**（数据库 I/O）跑完，再把结果渲染出来 —— 不能用
  /// `pumpAndSettle`，理由见文件头与 smoke_test。
  Future<void> settleReal(WidgetTester tester, {int rounds = 12}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
  }

  /// 把一屏放进最小可用的环境里 pump 出来，并等真实异步跑完。
  ///
  /// 两个 provider 都给（理由见 smoke_test 的 `pumpScreen`）—— 这两页今天只用
  /// `SqlExecutor`，但少给的那天不会报错，只会卡在加载态。
  Future<void> pumpScreen(
    WidgetTester tester,
    SqlExecutor exec,
    Widget screen,
  ) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<SqlExecutor>.value(value: exec),
          ChangeNotifierProvider<ActiveSessionController>.value(
            value: ActiveSessionController(exec),
          ),
        ],
        child: MaterialApp(theme: buildTheme(AppColors.dark), home: screen),
      ),
    );
    await settleReal(tester);
  }

  /// 翻到第 [index] 张卡（0 起）。
  ///
  /// 走**拖拽**（用户的手势路径），不走 `controller.jumpToPage` —— 后者绕开
  /// 手势，翻页挂掉了测试照样绿。
  ///
  /// 一个 move 拖到位、立刻抬手（框架自己的 `page_view_test.dart` 也是这么写的）。
  /// **不用 `timedDrag`**：它按帧分步发事件，抬手时带着速度，实测拖满一页会顺着
  /// 惯性一次掠过两张（0 → 2），后面按页码找文字的断言就全错位了。只发一个 move，
  /// 测速样本不够（`getVelocityEstimate` 要两组以上），抬手速度是零 —— 吸附只看
  /// 拖了多远，正是用户「过半就翻页」的那条规则。
  ///
  /// 距离取页宽的四分之三：过了一半才吸到下一张，又不到一张半，一次只走一张。
  ///
  /// 每拖一下都回头断一句 **页码**：这个助手错了，后面「找不到某段文字」的失败
  /// 会把人引到卡片内容上去，而其实是根本没翻过去。
  Future<void> goToCard(WidgetTester tester, int index) async {
    final pageView = find.byType(PageView);
    final controller = tester.widget<PageView>(pageView).controller!;
    // 从**当前**那张数起：同一个用例里常连着翻两次（先第 2 张、再第 3 张），
    // 一律当成从第一张出发，会读出「本该 1，实际 2」那种假失败
    for (var page = controller.page!.round(); page < index; page++) {
      final width = tester.getSize(pageView).width;
      final gesture = await tester.startGesture(tester.getCenter(pageView));
      await gesture.moveBy(Offset(-width * 0.75, 0));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(
        controller.page,
        (page + 1).toDouble(),
        reason: '拖了一下本该到第 ${page + 2} 张卡',
      );
    }
  }

  /// 页码点的宽度：Column 里、`PageView` 之外，带显式宽高的那些 Container。
  ///
  /// 不按颜色断 —— 颜色归主题管；宽高才是「现在在第几张」的载体
  /// （当前那张拉成 20 宽的胶囊，另外两张是 8 的圆点）。
  List<double> dotWidths(WidgetTester tester) {
    final column = find
        .ancestor(of: find.byType(PageView), matching: find.byType(Column))
        .first;
    final containers = tester.widgetList<Container>(
      find.descendant(of: column, matching: find.byType(Container)),
    );
    return [
      for (final c in containers)
        if (c.constraints != null) c.constraints!.maxWidth,
    ];
  }

  /// 本地时间造的三个日子。用**本地时间**造、再由 `formatDate` 排回同一串 ——
  /// 写死 epoch 毫秒的话，这台机器在哪个时区，断言的日期就跟着变。
  /// 2023-11-13 是周一、11-15 周三、11-17 周五。
  int nov13() => DateTime(2023, 11, 13, 9).millisecondsSinceEpoch;
  int nov15() => DateTime(2023, 11, 15, 9).millisecondsSinceEpoch;
  int nov17() => DateTime(2023, 11, 17, 9).millisecondsSinceEpoch;

  /// 三场深蹲，数字是刻意挑的（规格 §2.1 那组参考数字）：
  /// - 60×10（11-13）→ e1RM **78.5118**，屏显 79 —— **高于**下一场的 70×3；
  /// - 70×3（11-15）→ e1RM 76.4154，屏显 76 —— 更重，但 e1RM 更低；
  /// - 50×8（11-17）→ e1RM 62.3198，屏显 62 —— 最近一场**最轻**，
  ///   所以「最大重量」卡若误用最近那一场，屏上会出现 50 而不是 70。
  /// 容量依次是 600 / 210 / 400 —— 最大的也不在最近那一场。
  Future<String> seedThreeSquatSessions(
    WidgetTester tester,
    FfiExecutor exec,
  ) async {
    await seedSession(
      tester,
      exec,
      exerciseName: '深蹲',
      startedAt: nov13(),
      sets: const [(60, 10)],
    );
    await seedSession(
      tester,
      exec,
      exerciseName: '深蹲',
      startedAt: nov15(),
      sets: const [(70, 3)],
    );
    return seedSession(
      tester,
      exec,
      exerciseName: '深蹲',
      startedAt: nov17(),
      sets: const [(50, 8)],
    );
  }

  // ---------------------------------------------------------------------
  // 进步列表
  // ---------------------------------------------------------------------

  testWidgets('⭐ 进步行：动作名 / 「最近 … · 最重 …」 / 迷你走势', (tester) async {
    final exec = await seededDb(tester);
    addTearDown(exec.close);
    // 最近那一场**更轻**（11-13 的 70×3 比 11-15 的 60×10 重）——
    // 这样「最近」和「最强」不是同一个数，才分得出这一行说的是哪一个
    await seedSession(
      tester,
      exec,
      exerciseName: '深蹲',
      startedAt: nov13(),
      sets: const [(70, 3)],
    );
    await seedSession(
      tester,
      exec,
      exerciseName: '深蹲',
      startedAt: nov15(),
      sets: const [(60, 10)],
    );

    await pumpScreen(tester, exec, const Scaffold(body: ProgressPage()));

    expect(find.text('深蹲'), findsOneWidget);
    // 日期与「最重」**必须是同一天的**：都取自最近那一场（11-15 的 60×10）。
    // 换成历史最大值，屏幕上会出现「最近 11月15日 · 最重 70 kg」——
    // 日期与数字各说各话，比不显示还糟
    expect(find.text('最近 11月15日 周三 · 最重 60 kg × 10'), findsOneWidget);
    expect(find.textContaining('70'), findsNothing, reason: '历史最大值不是这一行要说的事');
    expect(find.byType(TrendChart), findsOneWidget, reason: '行右侧的迷你走势');
    // 行是可点的 —— 目标 URL 归路由表管，这里探不到（文件头写了为什么）
    expect(
      tester.widgetList<AppCard>(find.byType(AppCard)).single.onTap,
      isNotNull,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('进步列表：最近练过的在最上面', (tester) async {
    final exec = await seededDb(tester);
    addTearDown(exec.close);
    // 先建旧的、再建新的 —— 插入顺序与显示顺序相反，
    // 才能证明排序来自「最近练过」而不是建库顺序
    await seedSession(
      tester,
      exec,
      exerciseName: '深蹲',
      startedAt: nov13(),
      sets: const [(60, 10)],
    );
    await seedSession(
      tester,
      exec,
      exerciseName: '卧推',
      startedAt: nov15(),
      sets: const [(40, 8)],
    );

    await pumpScreen(tester, exec, const Scaffold(body: ProgressPage()));

    final bench = tester.getTopLeft(find.text('卧推')).dy;
    final squat = tester.getTopLeft(find.text('深蹲')).dy;
    expect(bench, lessThan(squat), reason: '11-15 练的卧推应在 11-13 的深蹲上面');
    expect(tester.takeException(), isNull);
  });

  testWidgets('⭐ 进步列表：进行中的训练不进列表（末点会在眼前跳）', (tester) async {
    final exec = await seededDb(tester);
    addTearDown(exec.close);
    await seedSession(
      tester,
      exec,
      exerciseName: '深蹲',
      startedAt: nov13(),
      sets: const [(60, 10)],
    );
    // 后面这场更新、但**没结束** —— 过滤坏掉的话列表会多出一行，且日期是新的
    await seedSession(
      tester,
      exec,
      exerciseName: '卧推',
      startedAt: nov17(),
      sets: const [(40, 8)],
      finished: false,
    );

    await pumpScreen(tester, exec, const Scaffold(body: ProgressPage()));

    expect(find.text('深蹲'), findsOneWidget);
    expect(find.text('卧推'), findsNothing, reason: '进行中的那一场不该出现在进步列表里');
    expect(find.text('最近 11月13日 周一 · 最重 60 kg × 10'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('进步列表：未完成的占位组不算数', (tester) async {
    final exec = await seededDb(tester);
    addTearDown(exec.close);
    // 完成 60×10，另留一条没完成的 100×1 占位（`is_completed = 0`）
    await seedSession(
      tester,
      exec,
      exerciseName: '深蹲',
      startedAt: nov13(),
      sets: const [(60, 10)],
      placeholders: const [(100, 1)],
    );

    await pumpScreen(tester, exec, const Scaffold(body: ProgressPage()));

    // 占位组是「下一组」，用户还没做过它 —— 它上屏就是一句假话
    expect(find.text('最近 11月13日 周一 · 最重 60 kg × 10'), findsOneWidget);
    expect(find.textContaining('100'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('进步列表：名字取不到时写「未知动作」，不崩', (tester) async {
    final exec = await seededDb(tester);
    addTearDown(exec.close);
    final squatId = await seedSession(
      tester,
      exec,
      exerciseName: '深蹲',
      startedAt: nov13(),
      sets: const [(60, 10)],
    );
    // 归档一个练过的动作：`listExercises` 过滤了 is_archived，取不到它。
    // （今天没有任何入口能归档动作，这是「取不到名字」的唯一现实路径。）
    await tester.runAsync(
      () => exec.run('UPDATE exercise SET is_archived = 1 WHERE id = ?', [
        squatId,
      ]),
    );

    await pumpScreen(tester, exec, const Scaffold(body: ProgressPage()));

    // 名字没了，但这一行照常显示 —— 有曲线就不该整行消失
    expect(find.text('未知动作'), findsOneWidget);
    expect(find.text('最近 11月13日 周一 · 最重 60 kg × 10'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('⭐ 空库：进步列表显示「还没有练过的动作」', (tester) async {
    final exec = await seededDb(tester);
    addTearDown(exec.close);

    await pumpScreen(tester, exec, const Scaffold(body: ProgressPage()));

    // 文案逐字来自规格 §6，不得同义替换
    expect(find.text('还没有练过的动作'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  // ---------------------------------------------------------------------
  // 动作详情：三张卡
  // ---------------------------------------------------------------------

  testWidgets('⭐ 动作详情：三张卡的措辞与数字（最好 × 2 / 最高 × 1）', (tester) async {
    final exec = await seededDb(tester);
    addTearDown(exec.close);
    final squatId = await seedThreeSquatSessions(tester, exec);

    await pumpScreen(tester, exec, ExerciseDetailPage(exerciseId: squatId));

    // 页面标题就是动作名 —— 三张卡说的是哪个动作，得先写清楚
    expect(find.text('深蹲'), findsOneWidget);

    // ---- 第 1 张：最大重量 ----
    expect(find.text('最大重量'), findsOneWidget);
    // ⚠️ 70 是**全部三场里的最大值**（11-15 那场）。若误用列表行的
    // `topWeight`（最近一场 = 11-17 的 50），下面两句就会红成 '50'
    expect(find.text('70'), findsOneWidget);
    expect(find.text('50'), findsNothing, reason: '绝不能是最近那一场的最重值');
    expect(find.text('最好 · 11月15日 周三'), findsOneWidget);

    // ---- 第 2 张：估算 1RM ----
    await goToCard(tester, 1);
    expect(find.text('估算 1RM'), findsOneWidget);
    // 79 来自 11-13 那场的 60×10（78.5118）—— 比更重的 70×3（76.4154）高。
    // 取成「最近那一场」或「最重那组的 e1RM」，这一句都会红
    expect(find.text('79'), findsOneWidget);
    expect(
      find.text('最好 · 11月13日 周一'),
      findsOneWidget,
      reason: '最好是哪一场的日期——与列表行的「最近」不是一回事',
    );
    expect(find.text('估算 · 仅供参考'), findsOneWidget);
    expect(find.text('来自 60 kg × 10'), findsOneWidget);

    // ---- 第 3 张：总容量 ----
    await goToCard(tester, 2);
    expect(find.text('总容量'), findsOneWidget);
    expect(find.text('600'), findsOneWidget); // 60×10 = 600，是三场里最高的
    expect(find.text('最高 · 11月13日 周一'), findsOneWidget);
    // 容量卡上**一个字都不许提「最好」**（规格 §4.4 的红线）——
    // 当前页只有这一张卡，所以这等于逐字检查它
    expect(find.textContaining('最好'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('⭐ 动作详情：全页找不到「个人最好」', (tester) async {
    final exec = await seededDb(tester);
    addTearDown(exec.close);
    // 用能凑齐三张卡的那组数据，三页都要翻到
    final squatId = await seedThreeSquatSessions(tester, exec);

    await pumpScreen(tester, exec, ExerciseDetailPage(exerciseId: squatId));

    // 容量是训练量不是力量成绩：练得轻但组数多的那一天容量反而更高，
    // 「个人最好」在这张卡上是一句关于用户身体的假话
    for (var i = 0; i < 3; i++) {
      await goToCard(tester, i);
      expect(
        find.textContaining('个人最好'),
        findsNothing,
        reason: '第 ${i + 1} 张卡上出现了「个人最好」',
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('⭐ 动作详情：只练过一次 → 一个点不画线 + 「再练一次就能看到走势」', (tester) async {
    final exec = await seededDb(tester);
    addTearDown(exec.close);
    final squatId = await seedSession(
      tester,
      exec,
      exerciseName: '深蹲',
      startedAt: nov13(),
      sets: const [(60, 10)],
    );

    await pumpScreen(tester, exec, ExerciseDetailPage(exerciseId: squatId));

    expect(find.text('60'), findsOneWidget);
    expect(find.text('最好 · 11月13日 周一'), findsOneWidget);
    // 一个点连不成线 —— 不许画一条平的线假装有走势（规格 §6）
    expect(find.text('再练一次就能看到走势'), findsOneWidget);
    expect(find.byType(TrendChart), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('⭐ 动作详情：没练过的动作 / 不存在的 id 都「这个动作还没有记录」，不崩', (tester) async {
    final exec = await seededDb(tester);
    addTearDown(exec.close);
    // 动作库里真实存在、但一场都没练过的动作（深链着它的 id 进来）
    final squatId = (await tester.runAsync(
      () =>
          listExercises(exec).then((l) => l.firstWhere((e) => e.name == '深蹲')),
    ))!.id;

    await pumpScreen(tester, exec, ExerciseDetailPage(exerciseId: squatId));
    expect(find.text('这个动作还没有记录'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 连动作库里都没有的 id —— 不许抛，也不许显示三条空曲线
    await pumpScreen(
      tester,
      exec,
      const ExerciseDetailPage(exerciseId: '不存在的-id'),
    );
    expect(find.text('这个动作还没有记录'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('⭐ e1RM 卡：所有场的次数都 > 10 → 一个点都没有 + 写明为什么', (tester) async {
    final exec = await seededDb(tester);
    addTearDown(exec.close);
    final squatId = await seedSession(
      tester,
      exec,
      exerciseName: '深蹲',
      startedAt: nov13(),
      sets: const [(60, 12)],
    );
    await seedSession(
      tester,
      exec,
      exerciseName: '深蹲',
      startedAt: nov15(),
      sets: const [(55, 15)],
    );

    await pumpScreen(tester, exec, ExerciseDetailPage(exerciseId: squatId));

    // 最大重量卡不受影响（换算不了的是 e1RM，不是重量）
    expect(find.text('60'), findsOneWidget);

    await goToCard(tester, 1);
    expect(find.text('估算 1RM'), findsOneWidget);
    // 不写「部分数据缺失」那种含糊说法 —— 说清次数、说清为什么（规格 §5）
    expect(find.text('还没有可用于换算的组（次数都 > 10）'), findsOneWidget);
    expect(
      find.textContaining('仅供参考'),
      findsNothing,
      reason: '一个数都没有，就不必给免责声明',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('⭐ e1RM 卡：有缺口 → 图下写明「有 N 次训练…」', (tester) async {
    final exec = await seededDb(tester);
    addTearDown(exec.close);
    final squatId = await seedSession(
      tester,
      exec,
      exerciseName: '深蹲',
      startedAt: nov13(),
      sets: const [(60, 10)],
    );
    // 这一场所有组的次数都 > 10 —— e1RM 序列上的一个缺口
    await seedSession(
      tester,
      exec,
      exerciseName: '深蹲',
      startedAt: nov15(),
      sets: const [(60, 12)],
    );

    await pumpScreen(tester, exec, ExerciseDetailPage(exerciseId: squatId));

    await goToCard(tester, 1);
    // 曲线直接连过去，但缺口要由一个数字交代清楚
    expect(find.text('有 1 次训练没有可用于换算的组（次数 > 10）'), findsOneWidget);
    expect(find.text('79'), findsOneWidget);

    // 这句只属于 e1RM 卡：总容量没有被换算规则影响的点
    await goToCard(tester, 2);
    expect(find.textContaining('没有可用于换算'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('动作详情：页码点跟着翻页走', (tester) async {
    final exec = await seededDb(tester);
    addTearDown(exec.close);
    final squatId = await seedThreeSquatSessions(tester, exec);

    await pumpScreen(tester, exec, ExerciseDetailPage(exerciseId: squatId));

    // 三个点：当前那个拉成 20 宽的胶囊，另外两个是 8 的圆点
    expect(dotWidths(tester).where((w) => w == 20).length, 1);
    expect(dotWidths(tester).where((w) => w == 8).length, 2);

    await goToCard(tester, 2);
    expect(dotWidths(tester).where((w) => w == 20).length, 1);
    expect(dotWidths(tester).where((w) => w == 8).length, 2);
    expect(tester.takeException(), isNull);
  });
}
