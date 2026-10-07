import 'package:flutter/material.dart';

/// 用户对「已经有一场没结束的训练」的选择。
enum ConflictChoice { resume, endAndStartNew, cancel }

/// 询问用户怎么处理那一场没结束的训练。
///
/// ⚠️ **这里是三按钮，不是旧项目的两按钮。**
///
/// 旧项目（React Native）的设计文档 §5.2 记着：原始设计是三按钮
/// `[接着练] [结束它，开始新的] [取消]`，但实现被迫改成两按钮 + cancelable ——
/// 原因是 **Android 的 Alert 最多三个按钮，且 RN 的映射顺序是
/// `[neutral, negative, positive]`，三个按钮时必有一个落进加粗主按钮位**，
/// 「无论放哪个都是误导」。
///
/// **Flutter 自己绘制对话框，没有这个限制**，因此还原原始设计：
/// 「取消」与「结束它」是两个不同性质的选项，值得各占一个按钮。
Future<ConflictChoice?> showConflictDialog(
  BuildContext context, {
  required String description,
}) {
  return showDialog<ConflictChoice>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      title: const Text('上一场训练还没结束'),
      content: Text(description),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, ConflictChoice.cancel),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, ConflictChoice.endAndStartNew),
          child: const Text('结束它，开始新的'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, ConflictChoice.resume),
          child: const Text('接着练'),
        ),
      ],
    ),
  );
}
