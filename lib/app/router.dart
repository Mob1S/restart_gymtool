import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';

import '../features/history/history_page.dart';
import '../plugins/bundled/bundled_catalog.dart';
import '../plugins/flutter/plugin_ui_adapter.dart';
import '../plugins/runtime/plugin_manager.dart';
import '../features/settings/plugin_management_page.dart';
import '../features/history/session_detail_page.dart';
import '../features/progress/exercise_detail_page.dart';
import '../features/progress/progress_page.dart';
import '../features/settings/settings_page.dart';
import '../features/workout/record_page.dart';
import '../features/workout/summary_page.dart';
import '../features/workout/workout_home_page.dart';
import 'app_shell.dart';
import '../features/import/import_page.dart';
import '../features/plans/plan_list_page.dart';
import '../features/plans/plan_editor_page.dart';
import '../features/plans/builtin_plan_page.dart';
import '../features/plans/program_editor.dart';
import '../domain/local_date.dart';

/// 路由表。
///
/// ⚠️ **只调用一次**（见 `providers.dart` 的 `_router`）——
/// 每次重建都新建一个 `GoRouter` 会把导航栈整个丢掉。
GoRouter buildRouter({
  PluginManager? plugins,
  PluginUiRegistry? registry,
  PluginExitRegistry? exits,
  String? initialLocation,
}) {
  final ui = registry ?? bundledUi(exits ?? PluginExitRegistry());
  return GoRouter(
    initialLocation: initialLocation ?? '/',
    overridePlatformDefaultLocation: initialLocation != null,
    refreshListenable: plugins,
    redirect: (_, state) {
      if (plugins == null) return null;
      final id = ui.ownerOf(state.uri.path);
      if (id != null && !plugins.isEnabled(id)) {
        return Uri(
          path: '/plugins/disabled',
          queryParameters: {'id': id, 'from': state.uri.toString()},
        ).toString();
      }
      return null;
    },
    routes: [
      GoRoute(
        path: '/settings/plugins',
        builder: (_, _) => const PluginManagementPage(),
      ),
      GoRoute(
        path: '/plugins/disabled',
        builder: (_, s) {
          final id = s.uri.queryParameters['id'] ?? '';
          final from = s.uri.queryParameters['from'];
          return DisabledPluginPage(
            pluginId: id,
            destination: ui.validTarget(id, from) ? from : null,
          );
        },
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => Scaffold(
          appBar: AppBar(
            title: const Text('设置'),
            leading: BackButton(
              onPressed: () {
                if (context.canPop()) {
                  context.pop();
                } else {
                  final from = state.uri.queryParameters['from'];
                  context.go(
                    {
                          '/',
                          '/calories',
                          '/analysis',
                          '/history',
                          '/progress',
                        }.contains(from)
                        ? from!
                        : '/',
                  );
                }
              },
            ),
          ),
          body: const SafeArea(child: SettingsPage()),
        ),
      ),
      GoRoute(path: '/plans', builder: (_, _) => const PlanListPage()),
      GoRoute(
        path: '/plans/builtin',
        builder: (_, _) => const BuiltinPlanPage(),
      ),
      GoRoute(
        path: '/plans/:id/program',
        builder: (_, s) => ProgramEditor(planId: s.pathParameters['id']!),
      ),
      GoRoute(path: '/plans/new', builder: (_, _) => const PlanEditorPage()),
      GoRoute(
        path: '/plans/:id/edit',
        builder: (_, s) => PlanEditorPage(id: s.pathParameters['id']!),
      ),
      GoRoute(path: '/records/import', builder: (_, _) => const ImportPage()),
      GoRoute(
        path: '/records/manual',
        builder: (_, state) => ImportPage(
          manual: true,
          initialDate: LocalDate.tryParse(state.uri.queryParameters['date']),
        ),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(path: '/', builder: (_, _) => const WorkoutHomePage()),
          for (final adapter in ui.adapters) ...adapter.routes,
          GoRoute(
            path: '/history',
            builder: (_, state) {
              final raw = state.uri.queryParameters['date'];
              final date = LocalDate.tryParse(raw);
              return HistoryPage(
                date: date,
                invalidDate: raw != null && date == null,
              );
            },
          ),
          GoRoute(path: '/progress', builder: (_, _) => const ProgressPage()),
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
        builder: (_, s) => SessionDetailPage(
          sessionId: s.pathParameters['id']!,
          historyDate: LocalDate.tryParse(s.uri.queryParameters['date']),
        ),
      ),
      GoRoute(
        path: '/progress/:exerciseId',
        builder: (_, s) =>
            ExerciseDetailPage(exerciseId: s.pathParameters['exerciseId']!),
      ),
    ],
  );
}

String? pluginForLocation(String path) =>
    bundledUi(PluginExitRegistry()).ownerOf(path);

bool validPluginDestination(String id, String? raw) =>
    bundledUi(PluginExitRegistry()).validTarget(id, raw);
