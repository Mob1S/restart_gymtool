import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gym_tracker/app/app_shell.dart';
import 'package:gym_tracker/app/router.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/sql_executor.dart';
import 'package:gym_tracker/data/repositories/exercise_repo.dart';
import 'package:gym_tracker/data/repositories/session_repo.dart';
import 'package:gym_tracker/data/repositories/set_repo.dart';
import 'package:gym_tracker/state/active_session_controller.dart';
import 'package:gym_tracker/state/theme_controller.dart';
import 'package:gym_tracker/ui/theme.dart';
import 'package:gym_tracker/ui/tokens.dart';
import 'package:provider/provider.dart';

/// 路由表本身的回归。
///
/// ## 为什么要有这一个文件
///
/// `/history/:id` 与外壳里的 `/history` **前缀相同**。哪一条先匹配上，
/// 决定了点开一条历史记录之后看到的是「详情页占满全屏、带返回键」，
/// 还是「详情页被塞进标签外壳里、没有返回键」—— 后者不是崩，是**看着能用
/// 但退不出去**。
///
/// 计划里给这一条的处置是「写完要在 Chrome 上实际点一次确认，不要只看代码
/// 推理」。真点一次当然可以，但那个结论**下次改路由表就失效了**，
/// 而没人会记得再点一次。所以改成一条会跑的断言：真建 `buildRouter()`、
/// 真 `go()` 过去、看落在哪个页面上。
///
/// 这里断言的是**结构**（外壳在不在），不是文案 —— 文案归各页面自己的测试管。
void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  /// 让**真实异步**（sqlite 的真 I/O）跑完 —— 假时钟推不动它。
  /// 理由与 `widget/smoke_test.dart` 同。
  Future<void> settleReal(WidgetTester tester, {int rounds = 12}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
  }

  /// 起一棵与 `AppBootstrap` 同形的树，返回那个 router 供 `go()` 用。
  Future<GoRouter> pumpApp(WidgetTester tester, FfiExecutor exec) async {
    final theme = ThemeController(exec);
    await tester.runAsync(theme.load);
    final router = buildRouter();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<SqlExecutor>.value(value: exec),
          ChangeNotifierProvider<ActiveSessionController>.value(
            value: ActiveSessionController(exec),
          ),
          ChangeNotifierProvider<ThemeController>.value(value: theme),
        ],
        child: MaterialApp.router(
          theme: buildTheme(AppColors.dark),
          routerConfig: router,
        ),
      ),
    );
    await settleReal(tester);
    return router;
  }

  Future<FfiExecutor> seededDb(WidgetTester tester) async {
    late FfiExecutor exec;
    await tester.runAsync(() async {
      exec = await FfiExecutor.openMigrated();
      await seedExercisesIfEmpty(exec);
    });
    return exec;
  }

  /// 造一场**已结束**的训练，返回它的 id。写法与 `history_pages_test` 同源。
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

  /// 推进**假时钟**，把路由入场 / 退场动画跑完。
  ///
  /// `settleReal` 里那些 `pump()` 是零时长的，推不动转场动画 —— 转场没跑完时
  /// 上一层的 widget 还在树里，`findsOneWidget` 会变成 `findsNWidgets(2)`。
  Future<void> finishAnimations(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  testWidgets('⭐ 标签页在外壳里：/history 与 /progress 都带外壳', (tester) async {
    final exec = await seededDb(tester);
    addTearDown(exec.close);
    final router = await pumpApp(tester, exec);

    for (final path in ['/history', '/progress']) {
      router.go(path);
      await settleReal(tester);
      expect(
        find.byType(AppShell),
        findsOneWidget,
        reason: '$path 是标签页，应当在标签外壳里',
      );
    }
  });

  testWidgets('⭐ 详情页在外壳外：/history/:id 不被 /history 抢走', (tester) async {
    final exec = await seededDb(tester);
    addTearDown(exec.close);
    final router = await pumpApp(tester, exec);

    router.go('/history/不存在的id');
    await settleReal(tester);

    // 这一条正是计划要求「实际点一次」的那件事。若 /history/:id 没接上
    // 或被外壳那条抢走，下面第一个断言就会红（详情页根本不会渲染），
    // 第二个断言则守住「详情页要占满全屏」这个产品要求。
    expect(
      find.text('这场训练不存在'),
      findsOneWidget,
      reason: '/history/:id 应当落到历史详情页（这里用一个取不到的 id 探路）',
    );
    expect(
      find.byType(AppShell),
      findsNothing,
      reason: '详情页要占满全屏、自带返回键，不该被塞进标签外壳',
    );
  });

  testWidgets('⭐ /progress/:exerciseId 同样在外壳外', (tester) async {
    final exec = await seededDb(tester);
    addTearDown(exec.close);
    final router = await pumpApp(tester, exec);

    router.go('/progress/不存在的动作');
    await settleReal(tester);

    expect(
      find.text('这个动作还没有记录'),
      findsOneWidget,
      reason: '/progress/:exerciseId 应当落到动作详情页，且深链坏 id 不崩',
    );
    expect(find.byType(AppShell), findsNothing, reason: '动作详情的三张卡要占满全屏');
    expect(tester.takeException(), isNull);
  });

  testWidgets('⭐ 从列表点进详情页：有返回键，且能退回列表', (tester) async {
    final exec = await seededDb(tester);
    addTearDown(exec.close);
    // 列表上得先有一条真的记录，才有东西可点
    await seedFinishedSession(
      tester,
      exec,
      name: '推日',
      startedAt: DateTime(2023, 11, 15, 9).millisecondsSinceEpoch,
      durationSeconds: 90,
      sets: const [(20, 8)],
    );
    final router = await pumpApp(tester, exec);

    // ⚠️ 这一条是本文件存在的**主要理由**，而且它的写法是被一次假绿逼出来的。
    //
    // 第一版这里是直接 `router.push('/history/xxx')` —— 那样**守不住它该守的东西**：
    // 列表页当时用的是 `context.go`（`go` 会把整个导航栈换成详情页那一层，
    // 于是详情页上没有返回键，用户点进一条记录就出不来了），而把 `push` 换回
    // `go` 之后这一条**照样是绿的** —— 因为它是测试自己在 push，
    // 根本没走列表页的 `onTap`。
    //
    // 所以现在改成**真的点那一行**：只有这样才能覆盖到列表页写的是 `go` 还是 `push`。
    // 改这一段之前，先把 `history_page.dart` 的 `push` 改成 `go` 跑一遍，
    // 确认它会红。
    router.go('/history');
    await settleReal(tester);
    expect(find.text('推日'), findsOneWidget, reason: '列表上应当有那一行可点');

    await tester.tap(find.text('推日'));
    await settleReal(tester);
    await finishAnimations(tester);

    expect(
      find.byType(BackButton),
      findsOneWidget,
      reason: '从列表点进详情页之后必须有返回键，否则用户卡在详情页出不来',
    );
    expect(find.text('训练详情'), findsOneWidget, reason: '应当真的进到详情页');

    await tester.tap(find.byType(BackButton));
    await settleReal(tester);
    await finishAnimations(tester);

    expect(find.text('训练详情'), findsNothing, reason: '返回之后不该还停在详情页');
    expect(find.text('推日'), findsOneWidget, reason: '返回之后应当回到列表，那条记录还在');
  });

  testWidgets('⭐ 从进步列表点进动作详情：同样有返回键，能退回列表', (tester) async {
    final exec = await seededDb(tester);
    addTearDown(exec.close);
    await seedFinishedSession(
      tester,
      exec,
      name: '腿日',
      startedAt: DateTime(2023, 11, 15, 9).millisecondsSinceEpoch,
      durationSeconds: 90,
      sets: const [(20, 8)],
    );
    final router = await pumpApp(tester, exec);

    // 与上一条同形：进步列表页也踩过同一个坑（`go` → 详情页上没有返回键），
    // 所以它也需要一条**真的点下去**的断言，不能只靠历史那条顺带覆盖 ——
    // 两个页面各有各的 `onTap`，一个用 push 不等于另一个也是。
    router.go('/progress');
    await settleReal(tester);
    expect(find.text('深蹲'), findsOneWidget, reason: '列表上应当有那个动作可点');

    await tester.tap(find.text('深蹲'));
    await settleReal(tester);
    await finishAnimations(tester);

    expect(
      find.byType(BackButton),
      findsOneWidget,
      reason: '从进步列表进动作详情之后必须有返回键',
    );
    expect(find.text('最大重量'), findsOneWidget, reason: '应当真的进到三张卡那一页');

    await tester.tap(find.byType(BackButton));
    await settleReal(tester);
    await finishAnimations(tester);

    expect(find.text('最大重量'), findsNothing, reason: '返回之后不该还停在动作详情');
    expect(find.text('深蹲'), findsOneWidget, reason: '返回之后应当回到进步列表');
  });
}
