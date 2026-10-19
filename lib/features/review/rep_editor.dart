import 'package:flutter/material.dart';

import '../../domain/video_review.dart';

Future<ReviewRep?> editReviewRep(BuildContext context, ReviewRep rep) async {
  final fields = rep
      .toJson()
      .map((t) => TextEditingController(text: (t / 1000).toStringAsFixed(3)))
      .toList();
  const labels = ['下降开始（秒）', '到达底部（秒）', '离开底部（秒）', '推起结束（秒）'];
  String? error;
  try {
    return await showDialog<ReviewRep>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: const Text('修正这一次'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('使用原视频时间。没有停顿时，到达与离开底部填写相同时间。'),
                for (var i = 0; i < 4; i++)
                  TextField(
                    controller: fields[i],
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(labelText: labels[i]),
                  ),
                if (error != null)
                  Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final values = fields
                    .map((f) => double.tryParse(f.text))
                    .toList();
                if (values.any(
                  (n) => n == null || !n.isFinite || n < 0 || n > 86400,
                )) {
                  update(() => error = '请输入有效的非负时间');
                  return;
                }
                final r = ReviewRep.fromJson(
                  values.map((n) => (n! * 1000).round()).toList(),
                );
                if (!validReviewReps([r], 0, 86400000)) {
                  update(() => error = '开始 < 到达底部 ≤ 离开底部 < 结束');
                  return;
                }
                Navigator.pop(context, r);
              },
              child: const Text('采用'),
            ),
          ],
        ),
      ),
    );
  } finally {
    for (final field in fields) {
      field.dispose();
    }
  }
}
