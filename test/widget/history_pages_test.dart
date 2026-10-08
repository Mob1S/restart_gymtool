import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/sql_executor.dart';
import 'package:gym_tracker/data/repositories/exercise_repo.dart';
import 'package:gym_tracker/data/repositories/session_repo.dart';
import 'package:gym_tracker/data/repositories/set_repo.dart';
import 'package:gym_tracker/features/history/history_page.dart';
import 'package:gym_tracker/features/history/session_detail_page.dart';
import 'package:gym_tracker/features/workout/summary_page.dart';
import 'package:gym_tracker/state/active_session_controller.dart';
import 'package:gym_tracker/ui/theme.dart';
import 'package:gym_tracker/ui/tokens.dart';
import 'package:gym_tracker/ui/widgets/session_summary_view.dart';
import 'package:provider/provider.dart';

/// 历史两条页面（列表 / 详情）的界面断言。
///
/// 工具与教训沿用 `widget/smoke_test.dart`：
/// - `settleReal` —— `flutter_test` 的假时钟推不动 sqlite ffi 的真 I/O，
///   用 `pumpAndSettle` 只会超时；
/// - 两个 provider 都要给，少一个页面会卡在加载态**而不报错**，
///   表现成「什么都没渲染」，很容易误判成异步没等到。
///
/// **这里不搭 `GoRouter`**：两页各自 pump 出来即可。路由表（`app/router.dart`）
/// 的正确性该由它自己的测试守，不该让这两页的断言依赖它 —— 唯一的例外是
/// 返回键那条，它的前提就是「页面上真有一层可退」，见那个用例里的说明。
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

  /// 造一场**已结束**的训练，返回它的 id。
  ///
  /// 时间显式写死，不用 `createSession` 记的真实 now —— 历史行的日期与时长
  /// 全靠这两个数；「赌两次调用落在不同毫秒」那种写法实测会闪
  /// （`session_summary_list_test` 里记着这个数）。
  ///
  /// 组走仓储的两步（[addSet] → [completeSet]）而不是手写 INSERT，
  /// 路径与记录界面一致。
  Future<String> seedFinishedSession(
    WidgetTester tester,
    FfiExecutor exec, {
    required String? name,
    required int startedAt,
    required int durationSeconds,
    List<(double, int)> sets = const [],
  }) async {
    late String id;
    await tester.runAsync(() async {
      final session = await createSession(exec, name: name);
      if (sets.isNotEmpty) {
        final squat = (await listExercises(exec))
            .firstWhere((e) => e.name == '深蹲');
        final se = await addExerciseToSession(exec, session.id, squat.id);
        for (final (weight, reps) in sets) {
          final set = await addSet(exec, se.id, weight, reps);
          await completeSet(exec, set.id, startedAt);
        }
      }
      await exec.run(
        'UPDATE session SET started_at = ?, finished_at = ? WHERE id = ?',
        [startedAt, startedAt + durationSeconds * 1000, session.id],
      );
      id = session.id;
    });
    return id;
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

  /// 推进**假时钟**，把路由入场 / 退场动画跑完（零时长的 `pump()` 推不动它）。
  Future<void> finishAnimations(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  /// 把一屏放进最小可用的环境里 pump 出来，并等真实异步跑完。
  ///
  /// 两个 provider 都给（理由见 smoke_test 的 `pumpScreen`）—— 这两页今天只
  /// 用 `SqlExecutor`，但少给的那天不会报错，只会卡在加载态。
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

  /// 2023-11-15 09:00（周三）的本地时间戳。
  ///
  /// 用**本地时间**造、再由 `formatDate` 排回同一串 —— 写成固定 epoch 毫秒
  /// 的话，这台机器在哪个时区，断言的日期就跟着变。
  int nov15() => DateTime(2023, 11, 15, 9).millisecondsSinceEpoch;
  int nov13() => DateTime(2023, 11, 13, 9).millisecondsSinceEpoch;

  testWidgets('⭐ 历史行：日期 / 未命名训练 / 时长 · 组数 · 容量', (tester) async {
    final exec = await seededDb(tester);
    addTearDown(exec.close);
    // 1 组 20 kg × 8 次 = 160 kg，时长 90 秒 —— 与规格 §7.4 那组手工核算的数字同源
    await seedFinishedSession(
      tester,
      exec,
      name: null,
      startedAt: nov15(),
      durationSeconds: 90,
      sets: const [(20, 8)],
    );

    await pumpScreen(tester, exec, const Scaffold(body: HistoryPage()));

    expect(find.text('11月15日 周三'), findsOneWidget);
    // 没填名字的训练必须有个标题，否则这一行只剩日期和数字
    expect(find.text('未命名训练'), findsOneWidget);
    // 三个数缺一不可：时长走 formatDuration、组数与容量来自聚合查询
    expect(find.text('1 分 30 秒 · 1 组 · 160 kg'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('0 组训练也在历史里：显示「0 组 · 0 kg」而不是消失', (tester) async {
    final exec = await seededDb(tester);
    addTearDown(exec.close);
    // 先建旧的 0 组训练、再建新的 —— 插入顺序与显示顺序相反，
    // 才能证明排序来自 started_at 而不是建库顺序
    await seedFinishedSession(
      tester,
      exec,
      name: '推日',
      startedAt: nov13(),
      durationSeconds: 60,
    );
    await seedFinishedSession(
      tester,
      exec,
      name: null,
      startedAt: nov15(),
      durationSeconds: 90,
      sets: const [(20, 8)],
    );

    await pumpScreen(tester, exec, const Scaffold(body: HistoryPage()));

    expect(find.text('推日'), findsOneWidget);
    // 0 组时 SUM 是 NULL 不是 0 —— 界面必须写成「0 组 · 0 kg」，
    // 不是「null kg」，也不是整行消失（规格 §3.2）
    expect(find.text('1 分 00 秒 · 0 组 · 0 kg'), findsOneWidget);

    // 最近的在前
    final newer = tester.getTopLeft(find.text('11月15日 周三')).dy;
    final older = tester.getTopLeft(find.text('11月13日 周一')).dy;
    expect(newer, lessThan(older), reason: '11月15日那一场应排在 11月13日上面');
    expect(tester.takeException(), isNull);
  });

  testWidgets('⭐ 空库：历史列表显示空态，两句都在', (tester) async {
    final exec = await seededDb(tester);
    addTearDown(exec.close);

    await pumpScreen(tester, exec, const Scaffold(body: HistoryPage()));

    // 文案逐字来自规格 §6 与 §4.1，不得同义替换
    expect(find.text('还没有已完成的训练'), findsOneWidget);
    expect(find.text('完成第一次训练后，这里会留下记录'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('⭐ 历史详情：正文就是总结页那个视图，数字也是那一份', (tester) async {
    final exec = await seededDb(tester);
    addTearDown(exec.close);
    final id = await seedFinishedSession(
      tester,
      exec,
      name: null,
      startedAt: nov15(),
      durationSeconds: 90,
      sets: const [(20, 8)],
    );

    await pumpScreen(tester, exec, SessionDetailPage(sessionId: id));

    // ⭐ 两页共用一个视图（规格 §4.2）—— 各画一套的话，口径字样迟早分叉，
    // 而且不会有任何测试变红
    expect(find.byType(SessionSummaryView), findsOneWidget);
    expect(find.text('总容量（重量 × 次数）'), findsOneWidget);
    expect(find.text('160'), findsOneWidget); // 20 × 8
    expect(find.text('8'), findsOneWidget); // 原始次数数组原样
    expect(find.text('组数不足 3 组，暂不判断'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('⭐ 历史详情有返回键；总结页刻意没有', (tester) async {
    final exec = await seededDb(tester);
    addTearDown(exec.close);
    final id = await seedFinishedSession(
      tester,
      exec,
      name: null,
      startedAt: nov15(),
      durationSeconds: 90,
      sets: const [(20, 8)],
    );

    // 详情页是被 push 进来的（历史行的点击目标）。**不能直接当 `home:` pump**
    // —— 它上面没有下一层时，AppBar 本来就不会画返回键，那样断言等于什么都没测。
    // 所以给一个空白底页，再把详情页推进栈里。
    await pumpScreen(tester, exec, const Scaffold());
    final nav = tester.state<NavigatorState>(find.byType(Navigator));

    unawaited(
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => SessionDetailPage(sessionId: id),
        ),
      ),
    );
    await finishAnimations(tester);
    await settleReal(tester);
    expect(find.byType(BackButton), findsOneWidget);

    // 反向：同一个栈里，总结页没有返回键 —— 那是它刻意的差别
    // （结束不可逆，只给一个出口），不是忘了写
    nav.pop();
    await finishAnimations(tester);
    unawaited(
      nav.push(
        MaterialPageRoute<void>(builder: (_) => SummaryPage(sessionId: id)),
      ),
    );
    await finishAnimations(tester);
    await settleReal(tester);
    expect(find.text('训练总结'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('详情页：不存在的 id 显示「这场训练不存在」，不抛', (tester) async {
    final exec = await seededDb(tester);
    addTearDown(exec.close);

    await pumpScreen(
      tester,
      exec,
      const SessionDetailPage(sessionId: '不存在的-id'),
    );

    expect(find.text('这场训练不存在'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
