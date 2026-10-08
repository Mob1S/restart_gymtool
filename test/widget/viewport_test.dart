import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/sql_executor.dart';
import 'package:gym_tracker/data/repositories/exercise_repo.dart';
import 'package:gym_tracker/features/workout/record_page.dart';
import 'package:gym_tracker/features/workout/summary_page.dart';
import 'package:gym_tracker/state/active_session_controller.dart';
import 'package:gym_tracker/ui/theme.dart';
import 'package:gym_tracker/ui/tokens.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

/// 视口适配回归。
///
/// ## 这一层为什么存在
///
/// 界面层原先只有「一台 800×600 默认测试视口 + 正常字号」这一种条件下的
/// 冒烟测试，而**真机上不止这一种条件**。一次模拟真机视口的探针照出四条
/// 溢出，全部是「桌面默认视口」照不到的：
///
/// | 场景 | 探针原始结果 |
/// |---|---|
/// | 记录页 320×480 | `RenderFlex overflowed by 59 pixels on the bottom` |
/// | 休息页 640×360 横屏 | `RenderFlex overflowed by 31 pixels on the bottom` |
/// | 总结页 360×640 @字号 2.0 | `RenderFlex overflowed by 156 pixels on the right` |
/// | 动作弹层 + 300dp 键盘 | 列表 6 行只剩 **1** 行露在键盘上方 |
///
/// 前三条切掉的都是**主操作或关键数字**（「完成这组」「开始第 N 组」「总容量」），
/// 第四条会让搜索框一打开就盖住结果 —— 而那个弹层是带 `autofocus` 的。
///
/// > 这四条**用户自己那台手机一条都没命中**（他那台是正常竖屏 + 默认字号），
/// > 所以「用户说用着还行」和「这四条不存在」是两件事。这正是本文件的意义：
/// > 把「只有某些视口才暴露」这一类固化成会跑的断言，而不是靠碰运气。
///
/// ## 这些断言不是「真机验收」
///
/// 它跑在 `flutter_test` 的模拟视口里，**不覆盖**触感、息屏、原生渲染差异。
/// 它守的是「布局在极端视口下不塌」这一件事（计划 Task 22 那条仍然要真机跑）。
void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  // 记录页会调 WakelockPlus.enable()，测试环境没有原生侧，异步会抛 —— 换掉平台实现
  setUp(() => wakelockPlusPlatformInstance = _FakeWakelock());

  /// 造一个已迁移 + 已播种的内存库。
  Future<FfiExecutor> seededDb(WidgetTester tester) async {
    late FfiExecutor exec;
    await tester.runAsync(() async {
      exec = await FfiExecutor.openMigrated();
      await seedExercisesIfEmpty(exec);
    });
    return exec;
  }

  /// 让**真实异步**（sqlite 的真 I/O）跑完 —— 假时钟推不动它，
  /// 所以不能用 `pumpAndSettle`。理由与 `widget/smoke_test.dart` 同。
  Future<void> settleReal(WidgetTester tester, {int rounds = 12}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
  }

  /// 推进**假时钟**，把弹层 / 路由的入场动画跑完（零时长的 `pump()` 推不动它）。
  Future<void> finishAnimations(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  /// 把测试视口调成一台真机的尺寸，并给出状态栏 / 导航栏占位。
  ///
  /// 归还写在 `addTearDown` 里 —— 三条 `reset*` 少一条，后面所有用例都会
  /// 莫名其妙地失败（而且看起来像被测代码的问题）。
  void setDevice(
    WidgetTester tester,
    double wDp,
    double hDp, {
    double topInsetDp = 24,
    double bottomInsetDp = 24,
  }) {
    const dpr = 3.0;
    tester.view.devicePixelRatio = dpr;
    tester.view.physicalSize = Size(wDp * dpr, hDp * dpr);
    tester.view.padding = FakeViewPadding(
      top: topInsetDp * dpr,
      bottom: bottomInsetDp * dpr,
    );
    tester.view.viewPadding = FakeViewPadding(
      top: topInsetDp * dpr,
      bottom: bottomInsetDp * dpr,
    );
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.view.resetPadding();
      tester.view.resetViewPadding();
      tester.view.resetViewInsets();
    });
  }

  /// 两个 provider 都要给（理由见 `widget/smoke_test.dart` 的 `pumpScreen`）。
  Future<void> pumpScreen(
    WidgetTester tester,
    ActiveSessionController controller,
    SqlExecutor exec,
    Widget screen, {
    TextScaler? scaler,
  }) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<SqlExecutor>.value(value: exec),
          ChangeNotifierProvider<ActiveSessionController>.value(
            value: controller,
          ),
        ],
        child: MaterialApp(
          theme: buildTheme(AppColors.dark),
          home: Builder(
            builder: (ctx) => scaler == null
                ? screen
                : MediaQuery(
                    data: MediaQuery.of(ctx).copyWith(textScaler: scaler),
                    child: screen,
                  ),
          ),
        ),
      ),
    );
    await settleReal(tester);
  }

  /// 开一场训练并加一个深蹲。
  Future<ActiveSessionController> sessionWithSquat(
    WidgetTester tester,
    FfiExecutor exec,
  ) async {
    final controller = ActiveSessionController(exec);
    final squat = (await tester.runAsync(
      () =>
          listExercises(exec).then((l) => l.firstWhere((e) => e.name == '深蹲')),
    ))!;
    await tester.runAsync(() async {
      await controller.startNew();
      await controller.addExercise(squat.id);
    });
    return controller;
  }

  /// 断言某个 widget **整块**落在可视区里，不是被切在边上。
  ///
  /// 只断言「存在」是不够的 —— 溢出报错的那一版里，被切掉一半的按钮
  /// 照样 `findsOneWidget`。
  void expectFullyOnScreen(WidgetTester tester, Finder finder, double screenH) {
    final r = tester.getRect(finder);
    expect(r.top, greaterThanOrEqualTo(0), reason: '被顶部切掉：rect=$r');
    expect(
      r.bottom,
      lessThanOrEqualTo(screenH),
      reason: '被底部切掉：rect=$r，屏幕高 $screenH',
    );
  }

  testWidgets('⭐ 记录页在 320×480 上不溢出，且「完成这组」滚一下够得到', (tester) async {
    final exec = await seededDb(tester);
    addTearDown(exec.close);
    const h = 480.0;
    final c = await sessionWithSquat(tester, exec);
    setDevice(tester, 320, h);

    await pumpScreen(tester, c, exec, RecordPage(sessionId: c.session!.id));

    // 修复前：RenderFlex overflowed by 59 pixels on the bottom
    expect(
      tester.takeException(),
      isNull,
      reason: '320×480 下记录页不该溢出（切掉的是底部唯一的「完成这组」）',
    );

    // 「存在」不等于「够得到」—— 溢出那一版它也在，只是被切在屏幕外
    final btn = find.text('✓ 完成这组');
    expect(btn, findsOneWidget);
    await tester.ensureVisible(btn);
    await tester.pump();
    expectFullyOnScreen(tester, btn, h);
  });

  testWidgets('⭐ 休息页在 640×360 横屏下不溢出，且「开始第 2 组」够得到', (tester) async {
    final exec = await seededDb(tester);
    addTearDown(exec.close);
    const h = 360.0;
    final c = await sessionWithSquat(tester, exec);
    await tester.runAsync(() => c.completeCurrentSet(20, 8));
    setDevice(tester, 640, h);

    await pumpScreen(tester, c, exec, RecordPage(sessionId: c.session!.id));

    // 修复前：RenderFlex overflowed by 31 pixels on the bottom
    expect(tester.takeException(), isNull, reason: '横屏下休息页不该溢出（切掉的是「开始第 2 组」）');

    final btn = find.text('开始第 2 组');
    expect(btn, findsOneWidget);
    await tester.ensureVisible(btn);
    await tester.pump();
    expectFullyOnScreen(tester, btn, h);
  });

  testWidgets('⭐ 总结页在 360×640 + 字号 2.0 下不溢到屏外，关键数字与口径字样都在', (tester) async {
    final exec = await seededDb(tester);
    addTearDown(exec.close);
    const h = 640.0;
    final c = ActiveSessionController(exec);
    final list = (await tester.runAsync(() => listExercises(exec)))!;
    final squat = list.firstWhere((e) => e.name == '深蹲');

    late String sid;
    await tester.runAsync(() async {
      await c.startNew();
      await c.addExercise(squat.id);
      for (var i = 0; i < 3; i++) {
        // 刻意用**四位数容量**（3 × 122.5 × 12 = 4410）—— 探针当初正是拿这组
        // 数字照出 156px 的横向溢出；三位数只会溢出 95px，守得松一档。
        await c.completeCurrentSet(122.5, 12);
      }
      sid = (await c.endWorkout())!;
    });

    setDevice(tester, 360, h);
    await pumpScreen(
      tester,
      ActiveSessionController(exec),
      exec,
      SummaryPage(sessionId: sid),
      scaler: TextScaler.linear(2.0),
    );

    // 修复前：RenderFlex overflowed by 156 pixels on the right
    expect(tester.takeException(), isNull, reason: '字号放大 2 倍时三个统计块不该挤出屏幕');

    // 数字宁可换行也不许被切 —— 总容量正是要求用户拿笔手工核对的那个数
    final volume = find.text('4410');
    expect(volume, findsOneWidget);
    expectFullyOnScreen(tester, volume, h);
    expect(find.text('总容量（重量 × 次数）'), findsOneWidget);
  });

  testWidgets('⭐ 动作弹层 + 300dp 键盘：列表让位到键盘上方', (tester) async {
    final exec = await seededDb(tester);
    addTearDown(exec.close);
    const h = 640.0;
    const kbd = 300.0;
    final c = ActiveSessionController(exec);
    await tester.runAsync(c.startNew);
    setDevice(tester, 360, h);
    await pumpScreen(tester, c, exec, RecordPage(sessionId: c.session!.id));

    await tester.tap(find.text('添加动作'));
    await settleReal(tester);
    await finishAnimations(tester);

    // 搜索框是 autofocus 的，键盘一打开就在 —— 这里模拟它弹出来
    tester.view.viewInsets = const FakeViewPadding(bottom: kbd * 3.0);
    await tester.pump();
    await finishAnimations(tester);
    await settleReal(tester, rounds: 4);

    expect(tester.takeException(), isNull);

    final listRect = tester.getRect(
      find
          .descendant(
            of: find.byType(DraggableScrollableSheet),
            matching: find.byType(ListView),
          )
          .first,
    );

    // 不变量：列表的可视区底边**在键盘之上**。
    // 修复前弹层照样铺到屏幕最底（bottom=640，键盘顶=340），6 行只剩 1 行露出来。
    expect(
      listRect.bottom,
      lessThanOrEqualTo(h - kbd + 1),
      reason: '列表底部应让位到键盘上方：list=$listRect，键盘顶 y=${h - kbd}',
    );
    expect(listRect.height, greaterThan(0), reason: '让位之后列表不该被压成 0 高');
  });

  testWidgets('⭐ 动作弹层拖到最高：搜索框不钻到状态栏下面', (tester) async {
    final exec = await seededDb(tester);
    addTearDown(exec.close);
    const h = 640.0;
    const topInset = 24.0;
    final c = ActiveSessionController(exec);
    await tester.runAsync(c.startNew);
    setDevice(tester, 360, h, topInsetDp: topInset);
    await pumpScreen(tester, c, exec, RecordPage(sessionId: c.session!.id));

    await tester.tap(find.text('添加动作'));
    await settleReal(tester);
    await finishAnimations(tester);

    final listFinder = find
        .descendant(
          of: find.byType(DraggableScrollableSheet),
          matching: find.byType(ListView),
        )
        .first;
    await tester.timedDrag(
      listFinder,
      const Offset(0, -400),
      const Duration(milliseconds: 300),
    );
    await finishAnimations(tester);
    await settleReal(tester, rounds: 4);

    expect(tester.takeException(), isNull);

    // 修复前 TextField 顶边是 16，状态栏到 24 —— 压住 8dp
    final tf = tester.getRect(find.byType(TextField));
    expect(
      tf.top,
      greaterThanOrEqualTo(topInset),
      reason: '搜索框不该被状态栏压住：TextField=$tf，状态栏高 $topInset',
    );
  });
}

/// `WakelockPlus` 的假平台实现（理由见 `widget/smoke_test.dart`）。
class _FakeWakelock extends WakelockPlusPlatformInterface {
  @override
  Future<void> toggle({required bool enable}) async {}

  @override
  Future<bool> get enabled async => false;
}
