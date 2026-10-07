import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/sql_executor.dart';
import 'package:gym_tracker/data/repositories/exercise_repo.dart';
import 'package:gym_tracker/features/workout/record_page.dart';
import 'package:gym_tracker/features/workout/summary_page.dart';
import 'package:gym_tracker/features/workout/workout_home_page.dart';
import 'package:gym_tracker/state/active_session_controller.dart';
import 'package:gym_tracker/ui/theme.dart';
import 'package:gym_tracker/ui/tokens.dart';
import 'package:provider/provider.dart';
// `wakelockPlusPlatformInstance` 这个顶层变量定义在主包里（它在 import 时
// 就把平台实例捕获走了），所以要替换实现必须 import 它。
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

/// `WakelockPlus` 的假平台实现。
///
/// ## 为什么需要它
///
/// `RecordPage.initState` 调 `WakelockPlus.enable()`（记录全程屏幕常亮）。
/// 在测试环境里没有原生侧，那个调用会**异步抛**
/// `PlatformException(channel-error, Unable to establish connection on channel:
/// "dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle")`，
/// 把测试判失败。
///
/// ## 一处值得记住的教训
///
/// 这个异常是**异步抛的**。第一版冒烟测试只等了一轮微任务，异常还没浮上来，
/// 于是**测试通过得有问题的** —— 看着像「不需要 mock」，实际是没等到。
/// 是后来把等待改扎实（`settleReal`）才暴露出来的。
///
/// **凡是「火并忘记」的异步调用（`initState` 里不 await 的那种），
/// 都要怀疑它是不是还没跑完。**
///
/// 替换的是主包的顶层变量 `wakelockPlusPlatformInstance`（它在 import 时
/// 就把实例捕获走了），所以直接赋值即可，不必去 mock pigeon 的
/// `BasicMessageChannel`（那需要自造 codec，麻烦得多）。
class _FakeWakelock extends WakelockPlusPlatformInterface {
  @override
  Future<void> toggle({required bool enable}) async {}

  @override
  Future<bool> get enabled async => false;
}

/// 界面层的冒烟测试。
///
/// ## 这一层为什么存在（一条**被推翻**的旧决定）
///
/// 计划最初写着「界面层不写单元测试」，理由是旧项目的一条纪律：
/// 「纯逻辑留在带 JSX 的文件里等于永远测不到」。
///
/// **但那条纪律的根因是 jest 的 babel 没配 JSX 预设 —— 是工具限制，
/// 不是设计原则。** Flutter 的 `flutter_test` 自带 `WidgetTester`，
/// widget 测试是白送的。按本项目的原则「为绕开平台限制而做的妥协，
/// 换栈后要重新审视」，这条被推翻。
///
/// ## 实施时的实测：成本比预想的低
///
/// 原以为有两处会挡路，实测**都不成立**：
/// - 「`flutter_test` 的假异步时钟和 sqlite ffi 的真 I/O 会冲突」——
///   把建库包进 `tester.runAsync` 就够了，不需要 mock 数据库
/// - 「`RecordPage` 用了 `WakelockPlus`（平台通道），必须 mock」——
///   实测直接渲染通过，不需要任何 mock
///
/// ## 它测什么、不测什么
///
/// **测**：屏幕能不能渲染、关键文案在不在、**口径字样对不对**（那是产品红线，
/// 值得自动化守着）。
///
/// **不测**：手感、触觉、安全区、息屏、原生差异 —— 那些只有真机能照到。
/// **这一层不替代真机验收**（见计划 Task 22）。
void main() {
  setUpAll(TestWidgetsFlutterBinding.ensureInitialized);

  // 每个用例都换掉屏幕常亮的平台实现 —— 见 `_FakeWakelock` 的说明
  setUp(() => wakelockPlusPlatformInstance = _FakeWakelock());

  /// 造一个已迁移 + 已播种的内存库。
  ///
  /// **建库必须包在 `tester.runAsync` 里** —— `flutter_test` 默认跑在假异步
  /// 时钟上，而 sqlite ffi 是真 I/O，不放进 `runAsync` 会永远卡住。
  Future<FfiExecutor> seededDb(WidgetTester tester) async {
    late FfiExecutor exec;
    await tester.runAsync(() async {
      exec = await FfiExecutor.openMigrated();
      await seedExercisesIfEmpty(exec);
    });
    return exec;
  }

  /// 让**真实异步**（数据库 I/O）跑完，再把结果渲染出来。
  ///
  /// ## 为什么不能用 `pumpAndSettle`
  ///
  /// `pumpAndSettle` 推进的是 `flutter_test` 的**假时钟**，而 sqlite ffi 走的是
  /// 真实 I/O —— 假时钟推不动它，结果就是 `pumpAndSettle timed out`。
  /// 同理，只 `await` 一个 `Duration.zero` 也不够：多个仓储调用串起来的链
  /// （`getSession` → `listSessionExercises` → 每个动作一次 `listSets`）
  /// 需要好几轮真实事件循环才走得完。
  ///
  /// 所以这里显式交替「在 `runAsync` 里等一会儿真实时间」与「pump 一帧」，
  /// 跑若干轮直到界面把结果渲染出来。
  Future<void> settleReal(WidgetTester tester, {int rounds = 12}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
  }

  /// 把一个屏幕包进最小可用的环境里 pump 出来，并等真实异步跑完。
  ///
  /// **两个 provider 都要给**：`ActiveSessionController` 给记录页与首页，
  /// `SqlExecutor` 给总结页与动作弹层（它们按 `context.read<SqlExecutor>()`
  /// 直接调仓储）。少任何一个，那个屏幕会卡在加载态而不报错 ——
  /// 表现是「什么都没渲染」，很容易误判成「异步没等到」。
  Future<void> pumpScreen(
    WidgetTester tester,
    ActiveSessionController controller,
    SqlExecutor exec,
    Widget screen,
  ) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<SqlExecutor>.value(value: exec),
          ChangeNotifierProvider<ActiveSessionController>.value(
            value: controller,
          ),
        ],
        child: MaterialApp(theme: buildTheme(AppColors.dark), home: screen),
      ),
    );
    await settleReal(tester);
  }

  testWidgets('训练首页：没有进行中训练时显示「开始训练」', (tester) async {
    final exec = await seededDb(tester);
    addTearDown(exec.close);

    await pumpScreen(
      tester,
      ActiveSessionController(exec),
      exec,
      const Scaffold(body: WorkoutHomePage()),
    );

    expect(find.text('开始训练'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('记录页：空训练不是死路（有整宽的添加入口）', (tester) async {
    final exec = await seededDb(tester);
    addTearDown(exec.close);
    final controller = ActiveSessionController(exec);
    await tester.runAsync(controller.startNew);

    await pumpScreen(
      tester,
      controller,
      exec,
      RecordPage(sessionId: controller.session!.id),
    );

    // 旧项目在这里踩过坑：空态只写了一句「这次训练还没有动作」、
    // 没有任何添加入口，用户进到那里就是一条死路。
    expect(find.text('这次训练还没有动作'), findsOneWidget);
    expect(find.text('添加动作'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('记录页：有动作时显示「第 1 / 1 组」与完成按钮', (tester) async {
    final exec = await seededDb(tester);
    addTearDown(exec.close);
    final controller = ActiveSessionController(exec);
    final squat = (await tester.runAsync(
      () =>
          listExercises(exec).then((l) => l.firstWhere((e) => e.name == '深蹲')),
    ))!;

    await tester.runAsync(() async {
      await controller.startNew();
      await controller.addExercise(squat.id);
    });

    await pumpScreen(
      tester,
      controller,
      exec,
      RecordPage(sessionId: controller.session!.id),
    );

    expect(find.text('深蹲'), findsWidgets);
    expect(find.text('第 1 / 1 组'), findsOneWidget);
    expect(find.text('✓ 完成这组'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('⭐ 总结页：口径字样、次数数组原样、粗略参考、组数不足时沉默', (tester) async {
    final exec = await seededDb(tester);
    addTearDown(exec.close);
    final controller = ActiveSessionController(exec);
    final list = (await tester.runAsync(() => listExercises(exec)))!;
    final squat = list.firstWhere((e) => e.name == '深蹲');
    final bench = list.firstWhere((e) => e.name == '卧推');

    late String sessionId;
    await tester.runAsync(() async {
      await controller.startNew();
      await controller.addExercise(squat.id);
      await controller.addExercise(bench.id);

      // 深蹲完成 3 组（够 3 组，会有提示），卧推只完成 1 组（不足 3 组，应沉默）
      controller.setCurrentIndex(0);
      for (var i = 0; i < 3; i++) {
        await controller.completeCurrentSet(20, 8);
      }
      controller.setCurrentIndex(1);
      await controller.completeCurrentSet(30, 10);

      sessionId = (await controller.endWorkout())!;
    });

    await pumpScreen(
      tester,
      ActiveSessionController(exec),
      exec,
      SummaryPage(sessionId: sessionId),
    );

    // ① 三个数字：3×20×8 + 1×30×10 = 480 + 300 = 780
    expect(find.text('780'), findsOneWidget);
    expect(find.text('4'), findsOneWidget); // 总组数

    // ② **口径字样** —— 规格附录要求界面必须写「总容量（重量 × 次数）」，
    //    且**不能**写成「个人最好」（容量是训练量，不是力量成绩）
    expect(find.text('总容量（重量 × 次数）'), findsOneWidget);
    expect(find.textContaining('个人最好'), findsNothing);

    // ③ 区块必须标注「粗略参考」
    expect(find.textContaining('粗略参考'), findsOneWidget);

    // ④ **次数数组原样显示** —— 只给结论不给原始数字，用户无法核对
    expect(find.text('8 / 8 / 8'), findsOneWidget);
    expect(find.text('10'), findsOneWidget);

    // ⑤ 组数 < 3 时明确沉默
    expect(find.text('组数不足 3 组，暂不判断'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  testWidgets('总结页：一场不存在的训练不崩', (tester) async {
    final exec = await seededDb(tester);
    addTearDown(exec.close);

    await pumpScreen(
      tester,
      ActiveSessionController(exec),
      exec,
      const SummaryPage(sessionId: '不存在的-id'),
    );

    expect(find.text('这场训练不存在'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('动作弹层：按肌群分组，且「胸」排在第一位', (tester) async {
    final exec = await seededDb(tester);
    addTearDown(exec.close);
    final controller = ActiveSessionController(exec);
    await tester.runAsync(controller.startNew);

    await pumpScreen(
      tester,
      controller,
      exec,
      RecordPage(sessionId: controller.session!.id),
    );

    // 空训练态那个整宽的「添加动作」按钮打开弹层。
    // **不用 `pumpAndSettle`** —— 弹层要读库取动作列表，那是真实异步，
    // 假时钟推不动它（见 settleReal 的注释）。
    await tester.tap(find.text('添加动作'));
    await settleReal(tester);

    // 肌群名是按 muscleGroupOrder 渲染的分组标题，胸在最上
    expect(find.text('胸'), findsWidgets);
    // 弹层里应能看到预置动作
    expect(find.textContaining('卧推'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
