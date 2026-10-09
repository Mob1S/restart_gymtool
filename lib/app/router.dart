import 'package:go_router/go_router.dart';

import '../features/history/history_page.dart';
import '../features/history/session_detail_page.dart';
import '../features/progress/exercise_detail_page.dart';
import '../features/progress/progress_page.dart';
import '../features/settings/settings_page.dart';
import '../features/workout/record_page.dart';
import '../features/workout/summary_page.dart';
import '../features/workout/workout_home_page.dart';
import 'app_shell.dart';

/// 路由表。
///
/// ⚠️ **只调用一次**（见 `providers.dart` 的 `_router`）——
/// 每次重建都新建一个 `GoRouter` 会把导航栈整个丢掉。
GoRouter buildRouter() => GoRouter(
  initialLocation: '/',
  routes: [
    ShellRoute(
      builder: (context, state, child) => AppShell(child: child),
      routes: [
        GoRoute(path: '/', builder: (_, _) => const WorkoutHomePage()),
        GoRoute(path: '/history', builder: (_, _) => const HistoryPage()),
        GoRoute(path: '/progress', builder: (_, _) => const ProgressPage()),
        GoRoute(path: '/settings', builder: (_, _) => const SettingsPage()),
      ],
    ),
    // 记录页与总结页**不在标签外壳里** —— 它们要占满全屏
    GoRoute(
      path: '/session/:id',
      builder: (_, s) => RecordPage(sessionId: s.pathParameters['id']!),
    ),
    GoRoute(
      path: '/summary/:id',
      builder: (_, s) => SummaryPage(sessionId: s.pathParameters['id']!),
    ),
    // 历史详情与动作详情**也不在标签外壳里** —— 它们要占满全屏、带返回键。
    //
    // ⚠️ `/history/:id` 与上面 ShellRoute 里那条 `/history` **前缀相同**。
    // 这不是靠读 go_router 的匹配规则推出来的结论 ——
    // `test/app/router_test.dart` 里有一条真建 `buildRouter()`、
    // 断言 `/history/abc` 解析到历史详情页（而不是被 `/history` 抢走）的用例。
    // 改这张表之前先让它跑一遍。
    GoRoute(
      path: '/history/:id',
      builder: (_, s) => SessionDetailPage(sessionId: s.pathParameters['id']!),
    ),
    GoRoute(
      path: '/progress/:exerciseId',
      builder: (_, s) =>
          ExerciseDetailPage(exerciseId: s.pathParameters['exerciseId']!),
    ),
  ],
);
