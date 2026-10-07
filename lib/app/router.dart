import 'package:go_router/go_router.dart';

import '../features/history/history_page.dart';
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
      ],
    );
