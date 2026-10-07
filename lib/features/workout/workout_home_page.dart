import 'package:flutter/material.dart';

import '../../ui/widgets/empty_state.dart';

/// ⚠️ **临时占位** —— Task 16「训练首页」会用真正的首页替换本文件。
///
/// 它现在就存在，只是因为 [buildRouter] 的路由表引用了 `/` 这个目的地；
/// 没有它路由表编译不过。
class WorkoutHomePage extends StatelessWidget {
  const WorkoutHomePage({super.key});

  @override
  Widget build(BuildContext context) =>
      const EmptyState(message: '训练首页将在后续 Task 交付');
}
