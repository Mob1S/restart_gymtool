import 'package:flutter/foundation.dart';

import '../data/db/sql_executor.dart';
import '../data/repositories/settings_repo.dart';

/// 主题偏好的编排层。
///
/// 四条实现约定（规格 §6.5），每条都对应一个真实问题：
/// 1. 偏好存 `app_setting`（迁移 v2 引入）
/// 2. **非法值退回 system**（`getThemeMode` 负责）——
///    主题读不出来不该让 App 起不来
/// 3. **先改内存再写库，写库失败不回滚** ——
///    用户在设置页点一下必须立刻变色，不能等一次磁盘往返
/// 4. 偏好读出来之前不放行子树（由 `AppProviders` 负责），
///    否则每次启动都会闪一帧
class ThemeController extends ChangeNotifier {
  final SqlExecutor _exec;

  ThemeController(this._exec);

  AppThemeMode mode = AppThemeMode.system;

  Future<void> load() async {
    mode = await getThemeMode(_exec);
    notifyListeners();
  }

  Future<void> setMode(AppThemeMode next) async {
    if (next == mode) return;
    // 先改内存 —— 立刻变色
    mode = next;
    notifyListeners();
    try {
      await setThemeMode(_exec, next);
    } catch (_) {
      // 写库失败**不回滚**：用户看到的颜色是对的，下次启动会退回旧值。
      // 相比「点了没反应」，这个失败模式更容易接受。
    }
  }
}
