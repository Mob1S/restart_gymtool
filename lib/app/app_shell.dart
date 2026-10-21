import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../state/backup_controller.dart';
import '../state/data_revision.dart';

import '../ui/theme.dart';

/// 五标签外壳。**`SafeArea` 不可省** ——
/// 旧项目在隐藏导航栏后出现过「顶部动作条压住状态栏」。
class AppShell extends StatelessWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    final location = GoRouterState.of(context).uri.path;
    final revision =
        context.watch<DataRevision?>()?.value ??
        context.watch<BackupController?>()?.revision ??
        0;
    final index = switch (location) {
      '/calories' => 1,
      final p when p == '/analysis' || p.startsWith('/analysis/') => 2,
      '/history' => 3,
      '/progress' => 4,
      _ => 0,
    };

    return Scaffold(
      appBar:
          {
            '/',
            '/calories',
            '/analysis',
            '/history',
            '/progress',
          }.contains(location)
          ? AppBar(
              title: Text(['训练', '热量', '动作分析', '历史', '进步'][index]),
              actions: [
                IconButton(
                  tooltip: '设置',
                  icon: const Icon(Icons.settings_outlined),
                  onPressed: () => context.push(
                    '/settings?from=${Uri.encodeComponent(location)}',
                  ),
                ),
              ],
            )
          : null,
      body: SafeArea(
        // Home observes DataRevision itself. Replacing its state here would
        // interrupt end-and-start and discard the user's temporary day choice.
        child: KeyedSubtree(
          key: ValueKey((
            location,
            location == '/' ||
                    location == '/calories' ||
                    location.startsWith('/analysis/')
                ? null
                : revision,
          )),
          child: child,
        ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        backgroundColor: c.surface,
        indicatorColor: c.accent.withValues(alpha: 0.18),
        onDestinationSelected: (i) => switch (i) {
          0 => context.go('/'),
          1 => context.go('/calories'),
          2 => context.go('/analysis'),
          3 => context.go('/history'),
          _ => context.go('/progress'),
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.fitness_center), label: '训练'),
          NavigationDestination(
            icon: Icon(Icons.local_drink_outlined),
            label: '热量',
          ),
          NavigationDestination(
            icon: Icon(Icons.accessibility_new),
            label: '动作分析',
          ),
          NavigationDestination(icon: Icon(Icons.history), label: '历史'),
          NavigationDestination(icon: Icon(Icons.show_chart), label: '进步'),
        ],
      ),
    );
  }
}
