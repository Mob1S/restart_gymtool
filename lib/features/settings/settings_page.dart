import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../data/repositories/settings_repo.dart';
import '../../state/theme_controller.dart';
import '../../state/backup_controller.dart';
import '../../plugins/flutter/plugin_ui_adapter.dart';
import '../../plugins/runtime/plugin_manager.dart';
import 'backup_section.dart';
import '../../ui/theme.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/app_card.dart';
import '../../ui/widgets/segmented_control.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    final theme = context.watch<ThemeController>();
    final backup = context.watch<BackupController?>();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
      children: [
        const SizedBox(height: AppSpacing.xl),

        AppCard(
          child: Material(
            type: MaterialType.transparency,
            child: ListTile(
              leading: const Icon(Icons.extension_outlined),
              title: const Text('插件管理'),
              subtitle: const Text('启停饮料热量和动作分析，保留已有数据'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push('/settings/plugins'),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),

        Text(
          '外观',
          style: TextStyle(
            fontSize: AppFontSize.label,
            letterSpacing: AppTracking.label,
            color: c.textTertiary,
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '主题',
                style: TextStyle(
                  fontSize: AppFontSize.title,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              // 三态，不是布尔 —— 布尔表达不了「跟随系统」，
              // 而它才是默认值、也是大多数人想要的
              SegmentedControl<AppThemeMode>(
                options: AppThemeMode.values,
                value: theme.mode,
                labelOf: (m) => switch (m) {
                  AppThemeMode.system => '跟随系统',
                  AppThemeMode.light => '浅色',
                  AppThemeMode.dark => '深色',
                },
                onChanged: (m) => context.read<ThemeController>().setMode(m),
              ),
            ],
          ),
        ),
        if (backup != null) ...[
          const SizedBox(height: AppSpacing.xl),
          BackupSection(controller: backup),
          const SizedBox(height: AppSpacing.xl),
        ],
        const SizedBox(height: 24),
        for (final section
            in context.read<PluginUiRegistry?>()?.settingsSections(
                  context.watch<PluginManager?>(),
                ) ??
                <PluginSettingsSection>[])
          AppCard(
            child: Material(
              type: MaterialType.transparency,
              child: ListTile(
                title: Text(section.label),
                subtitle: section.description.isEmpty
                    ? null
                    : Text(section.description),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(section.route),
              ),
            ),
          ),
      ],
    );
  }
}
