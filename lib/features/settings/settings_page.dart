import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/settings_repo.dart';
import '../../state/theme_controller.dart';
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

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
      children: [
        const SizedBox(height: AppSpacing.xl),
        Text(
          '设置',
          style: TextStyle(
            fontSize: AppFontSize.h1,
            fontWeight: FontWeight.w700,
            color: c.textPrimary,
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
      ],
    );
  }
}
