import '../db/sql_executor.dart';

/// 主题模式在 `app_setting` 里的键名。英文键名，与 `schema_version` 保持一致。
const String themeModeKey = 'theme_mode';

/// 主题模式。
///
/// **三态而不是布尔。** 布尔（深色 / 浅色）表达不了「跟随系统」—— 那才是
/// 默认行为，也是大多数用户想要的。用户一进设置页看到的是「跟随系统」被选中，
/// 而不是被迫在两种颜色里挑一个。
enum AppThemeMode { system, light, dark }

/// 读一个设置项。
///
/// **键不存在时返回 null**（不是空串 —— 空串是一个合法的、被显式写入过的值，
/// 两者必须能区分）。
Future<String?> getSetting(SqlExecutor exec, String key) async {
  final row = await exec.first<Map<String, Object?>>(
    'SELECT value FROM app_setting WHERE key = ?',
    [key],
  );
  return row?['value'] as String?;
}

/// 写一个设置项。键已存在则覆盖。
///
/// 用 `ON CONFLICT ... DO UPDATE` 而不是「先删再插」：后者在两个 await 之间
/// 被打断会留下「键没了」的中间状态，而这个键丢了界面会退回默认主题，
/// 用户看到的是自己刚设的偏好莫名消失。
Future<void> setSetting(SqlExecutor exec, String key, String value) async {
  await exec.run(
    '''INSERT INTO app_setting (key, value) VALUES (?, ?)
       ON CONFLICT(key) DO UPDATE SET value = excluded.value''',
    [key, value],
  );
}

/// 读主题模式。
///
/// **没设置过、或库里存的是个非法值时一律返回 [AppThemeMode.system]。**
/// 非法值不当错误抛出：主题读不出来不该让整个 App 起不来，
/// 退回默认跟随系统是唯一合理的降级。
Future<AppThemeMode> getThemeMode(SqlExecutor exec) async {
  final stored = await getSetting(exec, themeModeKey);
  for (final mode in AppThemeMode.values) {
    if (mode.name == stored) return mode;
  }
  return AppThemeMode.system;
}

Future<void> setThemeMode(SqlExecutor exec, AppThemeMode mode) =>
    setSetting(exec, themeModeKey, mode.name);
