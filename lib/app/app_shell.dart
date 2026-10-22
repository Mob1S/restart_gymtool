import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../state/backup_controller.dart';
import '../state/data_revision.dart';
import '../plugins/bundled/bundled_catalog.dart';
import '../plugins/flutter/plugin_ui_adapter.dart';
import '../plugins/runtime/plugin_manager.dart';

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
    final manager = context.watch<PluginManager?>();
    final registry =
        context.read<PluginUiRegistry?>() ?? bundledUi(PluginExitRegistry());
    final destinations = registry.destinations(manager);
    final matched = destinations.indexWhere((d) => d.matches(location));
    final index = matched < 0 ? 0 : matched;

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
              title: Text(destinations[index].label),
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
        onDestinationSelected: (i) => context.go(destinations[i].route),
        destinations: [
          for (final destination in destinations)
            NavigationDestination(
              icon: Icon(destination.icon),
              label: destination.label,
            ),
        ],
      ),
    );
  }
}
