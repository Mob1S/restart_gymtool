import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../state/import_controller.dart';
import '../../domain/local_date.dart';
import 'import_preview_view.dart';
import 'manual_workout_form.dart';

class ImportPage extends StatefulWidget {
  final bool manual;
  final LocalDate? initialDate;
  const ImportPage({super.key, this.manual = false, this.initialDate});
  @override
  State<ImportPage> createState() => _ImportPageState();
}

class _ImportPageState extends State<ImportPage> {
  @override
  void initState() {
    super.initState();
    context.read<ImportController>().cancel(notify: false);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ImportController>();
    return PopScope(
      canPop: !c.committing,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) c.cancel(notify: false);
      },
      child: Scaffold(
        appBar: AppBar(title: Text(widget.manual ? '手动补记录' : '从 CSV 追加记录')),
        body: Column(
          children: [
            if (c.busy) const LinearProgressIndicator(),
            if (c.message != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text(c.message!),
              ),
            Expanded(
              child: c.draft != null
                  ? ImportPreviewView(controller: c)
                  : widget.manual
                  ? ManualWorkoutForm(
                      controller: c,
                      initialDate: widget.initialDate,
                    )
                  : Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('支持本应用、Strong、Hevy、训记 CSV。先预览，再追加到历史。'),
                            const SizedBox(height: 16),
                            FilledButton(
                              onPressed: c.busy ? null : () => c.selectCsv(),
                              child: const Text('选择 CSV 文件'),
                            ),
                          ],
                        ),
                      ),
                    ),
            ),
            if (c.draft != null)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: c.busy ? null : c.cancel,
                        child: const Text('取消预览'),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: c.busy || c.confirmed == null
                              ? null
                              : () async {
                                  final result = await c.commit();
                                  if (context.mounted &&
                                      result !=
                                          ImportCommitOutcome.notCommitted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(c.message ?? '记录已导入'),
                                      ),
                                    );
                                    final stamp = c.lastImportedStartedAt;
                                    final date = widget.manual && stamp != null
                                        ? LocalDate.fromDateTime(
                                            DateTime.fromMillisecondsSinceEpoch(
                                              stamp,
                                            ),
                                          )
                                        : null;
                                    context.go(
                                      '/history${date == null ? '' : '?date=${date.key}'}',
                                    );
                                  }
                                },
                          child: Text(
                            '追加 ${c.confirmed?.workouts.length ?? 0} 场训练',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
