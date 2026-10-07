import 'package:flutter/material.dart';

import '../../ui/widgets/empty_state.dart';

/// 历史页占位 —— 计划里「下一期交付」。
class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});

  @override
  Widget build(BuildContext context) =>
      const EmptyState(message: '历史记录将在下一期交付');
}
