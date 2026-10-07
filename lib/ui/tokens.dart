import 'package:flutter/material.dart';

/// 纯视觉层的**唯一来源**。
///
/// 规格 §6.4：**界面不写裸数值** —— 颜色、字号、间距一律从这里取。
/// 这条纪律的收益很具体：休息计时的钟面与记录页的大数字是两个不同尺寸，
/// 共用一个 display 会让其中一处偏大或偏小（旧项目落地时才发现，
/// 于是多出了一档 clock 76）。
class AppColors {
  /// 近黑，**不用纯黑** —— 纯黑在 OLED 上和边框糊在一起，看不出边界
  final Color background;
  final Color surface;
  final Color surfacePressed;

  /// 信号橙。同时是杠铃片、警示带、力量器械的颜色。
  ///
  /// 刻意避开 `#2b7fff` 蓝（AI 生成界面的最典型特征）与荧光绿
  /// （与健身房「安全色」语义冲突）。
  final Color accent;
  final Color success;
  final Color danger;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color border;

  const AppColors({
    required this.background,
    required this.surface,
    required this.surfacePressed,
    required this.accent,
    required this.success,
    required this.danger,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.border,
  });

  /// 力量感 · 暗色仪表盘。默认配色。
  static const AppColors dark = AppColors(
    background: Color(0xFF0B0C0E),
    surface: Color(0xFF141619),
    surfacePressed: Color(0xFF1C1F24),
    accent: Color(0xFFFF6A1A),
    success: Color(0xFF32D74B),
    danger: Color(0xFFFF453A),
    textPrimary: Color(0xFFF2F4F7),
    textSecondary: Color(0xFF9BA1AC),
    textTertiary: Color(0xFF656B76),
    border: Color(0xFF2A2E35),
  );

  /// 浅色是**同色相映射**，不是简单反色：暖白底 + 略深一档的橙。
  static const AppColors light = AppColors(
    background: Color(0xFFFAFAF8),
    surface: Color(0xFFFFFFFF),
    surfacePressed: Color(0xFFF0EFEC),
    accent: Color(0xFFE4580A),
    success: Color(0xFF1F9D3A),
    danger: Color(0xFFD32F2F),
    textPrimary: Color(0xFF16181C),
    textSecondary: Color(0xFF5A606B),
    textTertiary: Color(0xFF8B9099),
    border: Color(0xFFDDDCD8),
  );
}

/// 字号尺度。**下面是实际值，不是设计稿的值。**
///
/// 设计阶段写的是 display 88，落地时收敛到 84，并多出一档 clock 76。
class AppFontSize {
  AppFontSize._();

  /// 记录页那个超大数字
  static const double display = 84;

  /// 休息计时的钟面
  static const double clock = 76;

  /// 统计块里的主数字
  static const double stat = 30;
  static const double h1 = 30;
  static const double h2 = 22;

  /// 列表行主文本、按钮
  static const double title = 17;
  static const double body = 15;

  /// 次要说明、元信息
  static const double caption = 13;

  /// 分组小标题、单位标注（通常配 letterSpacing）
  static const double label = 11;
}

/// 字间距。
///
/// 单独抽出来是因为它**踩过 DRY**：`theme.dart` 的 `labelSmall` 与
/// `stat_block.dart` 里各写了一遍 `letterSpacing: 0.8`，两处会各自漂移，
/// 而它们本该是同一种「分组小标题」的观感 —— 这正是「tokens 是唯一来源」
/// 那条纪律要防的东西。
class AppTracking {
  AppTracking._();

  /// 分组小标题 / 单位标注。配 [AppFontSize.label] 使用。
  static const double label = 0.8;
}

class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// 屏幕左右安全边距
  static const double screenH = 20;

  /// 圆角
  static const double radius = 14;
  static const double radiusSm = 8;
}

/// 数字专用文字样式：**等宽数字**。
///
/// `FontFeature.tabularFigures()` 让数字宽度恒定 —— 拖动那个 84px 的大数字时
/// `9 → 10` 不会让整块抖一下。
///
/// 字体用**系统字体**，不引第三方字体文件：中文字体动辄 5–10MB 会拖慢启动；
/// 引拉丁数字字体则会制造中西混排差异。**品牌感靠排版、间距、颜色做，
/// 不靠字体文件。**
const List<FontFeature> tabularNums = [FontFeature.tabularFigures()];
