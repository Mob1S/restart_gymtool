import 'package:flutter/material.dart';

import '../../ui/widgets/empty_state.dart';

/// ⚠️ **临时占位** —— Task 17「记录页」会用真正的记录页替换本文件。
///
/// 路由表里的 `/session/:id` 指向它，所以 `sessionId` 这个构造参数必须先在。
class RecordPage extends StatelessWidget {
  final String sessionId;

  const RecordPage({super.key, required this.sessionId});

  @override
  Widget build(BuildContext context) =>
      const EmptyState(message: '记录页将在后续 Task 交付');
}
