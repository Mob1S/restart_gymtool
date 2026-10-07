import 'package:flutter/material.dart';

import '../../ui/widgets/empty_state.dart';

/// ⚠️ **临时占位** —— Task 20「主题三态与设置页」会用真正的设置页替换本文件。
///
/// 它现在就存在，只是因为 [buildRouter] 的路由表引用了 `/settings` 这个目的地，
/// 四标签外壳少一个标签就不成立。
class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const EmptyState(message: '设置将在后续 Task 交付');
}
