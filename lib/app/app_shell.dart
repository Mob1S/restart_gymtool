import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../state/backup_controller.dart';

import '../ui/theme.dart';

/// 四标签外壳。**`SafeArea` 不可省** ——
/// 旧项目在隐藏导航栏后出现过「顶部动作条压住状态栏」。
class AppShell extends StatelessWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    final location = GoRouterState.of(context).uri.path;
    final revision = context.watch<BackupController?>()?.revision ?? 0;
    final index = switch (location) {
      '/history' => 1,
      '/progress' => 2,
      '/settings' => 3,
      _ => 0,
    };

    return Scaffold(
      body: SafeArea(
        child: KeyedSubtree(key: ValueKey((location, revision)), child: child),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        backgroundColor: c.surface,
        indicatorColor: c.accent.withValues(alpha: 0.18),
        onDestinationSelected: (i) => switch (i) {
          0 => context.go('/'),
          1 => context.go('/history'),
          2 => context.go('/progress'),
          _ => context.go('/settings'),
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.fitness_center), label: '训练'),
          NavigationDestination(icon: Icon(Icons.history), label: '历史'),
          NavigationDestination(icon: Icon(Icons.show_chart), label: '进步'),
          NavigationDestination(icon: Icon(Icons.settings), label: '设置'),
        ],
      ),
    );
  }
}
