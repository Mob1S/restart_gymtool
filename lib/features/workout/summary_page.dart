import 'package:flutter/material.dart';

import '../../ui/widgets/empty_state.dart';

/// ⚠️ **临时占位** —— Task 19「总结页」会用真正的总结页替换本文件。
///
/// 路由表里的 `/summary/:id` 指向它，所以 `sessionId` 这个构造参数必须先在。
class SummaryPage extends StatelessWidget {
  final String sessionId;

  const SummaryPage({super.key, required this.sessionId});

  @override
  Widget build(BuildContext context) =>
      const EmptyState(message: '总结页将在后续 Task 交付');
}
