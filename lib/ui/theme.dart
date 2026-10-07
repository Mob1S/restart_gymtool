import 'package:flutter/material.dart';

import 'tokens.dart';

/// 把 [AppColors] 装配成 ThemeData。
///
/// 这里**只做映射，不做设计决策** —— 所有取值都来自 tokens。
ThemeData buildTheme(AppColors colors) {
  final isDark = colors.background.computeLuminance() < 0.5;

  return ThemeData(
    useMaterial3: true,
    brightness: isDark ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: colors.background,
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: colors.accent,
          brightness: isDark ? Brightness.dark : Brightness.light,
        ).copyWith(
          surface: colors.surface,
          primary: colors.accent,
          error: colors.danger,
        ),
    dividerColor: colors.border,
    textTheme: TextTheme(
      displayLarge: TextStyle(
        fontSize: AppFontSize.display,
        fontWeight: FontWeight.w700,
        color: colors.textPrimary,
        fontFeatures: tabularNums,
      ),
      headlineLarge: TextStyle(
        fontSize: AppFontSize.h1,
        fontWeight: FontWeight.w700,
        color: colors.textPrimary,
      ),
      titleLarge: TextStyle(
        fontSize: AppFontSize.h2,
        fontWeight: FontWeight.w600,
        color: colors.textPrimary,
      ),
      titleMedium: TextStyle(
        fontSize: AppFontSize.title,
        fontWeight: FontWeight.w600,
        color: colors.textPrimary,
      ),
      bodyMedium: TextStyle(
        fontSize: AppFontSize.body,
        color: colors.textPrimary,
      ),
      bodySmall: TextStyle(
        fontSize: AppFontSize.caption,
        color: colors.textSecondary,
      ),
      labelSmall: TextStyle(
        fontSize: AppFontSize.label,
        letterSpacing: AppTracking.label,
        color: colors.textTertiary,
      ),
    ),
    extensions: <ThemeExtension<dynamic>>[AppColorsExtension(colors)],
  );
}

/// 让任意 widget 通过 `Theme.of(context).extension<AppColorsExtension>()`
/// 拿到当前配色 —— 不必在每个 widget 里判断亮暗。
class AppColorsExtension extends ThemeExtension<AppColorsExtension> {
  final AppColors colors;

  const AppColorsExtension(this.colors);

  @override
  AppColorsExtension copyWith({AppColors? colors}) =>
      AppColorsExtension(colors ?? this.colors);

  @override
  AppColorsExtension lerp(ThemeExtension<AppColorsExtension>? other, double t) {
    if (other is! AppColorsExtension) return this;
    return t < 0.5 ? this : other;
  }
}

/// 取当前配色的便捷入口。
AppColors appColors(BuildContext context) =>
    Theme.of(context).extension<AppColorsExtension>()?.colors ?? AppColors.dark;
