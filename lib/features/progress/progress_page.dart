import 'package:flutter/material.dart';

import '../../ui/widgets/empty_state.dart';

/// 进步页占位 —— 计划里「下一期交付」。
class ProgressPage extends StatelessWidget {
  const ProgressPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const EmptyState(message: '进步曲线将在下一期交付');
}
