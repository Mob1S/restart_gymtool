import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

// 执行器从**仓储层**拿，不从 data/db/ 直接拿 —— 见 executor_access.dart 的说明
import '../../data/repositories/executor_access.dart';
import '../../state/data_revision_loader.dart';
import '../../state/summary_feedback_loader.dart';
import '../../ui/theme.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/primary_button.dart';
import '../../ui/widgets/session_summary_view.dart';

/// 训练总结。
///
/// **按路由参数 id 从库里读，不依赖 controller** —— 这正是 [endWorkout]
/// 敢于「结束就立刻清内存」的前提：总结页不受内存被清空的影响。
///
/// 数字不在这里算：装载一律走 [loadSessionSummary]，正文交给
/// [SessionSummaryView]（历史详情页共用同一处装载与渲染）。这一层只剩
/// 加载中、找不到，以及那个唯一的出口按钮。
class SummaryPage extends StatefulWidget {
  final String sessionId;
  const SummaryPage({super.key, required this.sessionId});

  @override
  State<SummaryPage> createState() => _SummaryPageState();
}

class _SummaryPageState extends State<SummaryPage>
    with DataRevisionLoader<SummaryPage>, SummaryFeedbackLoader<SummaryPage> {
  @override
  Future<void> reloadData() =>
      loadSummaryFeedback(context.read<SqlExecutor>(), widget.sessionId);

  @override
  void didUpdateWidget(covariant SummaryPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sessionId != widget.sessionId) reloadData();
  }

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    if (feedbackLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final summary = feedbackSummary;
    if (summary == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(feedbackError ?? '这场训练不存在'),
              if (feedbackError != null)
                TextButton(onPressed: reloadData, child: const Text('重试载入')),
              TextButton(
                onPressed: () => context.go('/'),
                child: const Text('返回训练'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('训练总结'),
        backgroundColor: c.background,
        // 总结页**没有返回键** —— 结束是不可逆的，这里只给一个出口
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screenH),
        children: [
          if (feedbackError != null) ...[
            Text(feedbackError!),
            TextButton(onPressed: reloadData, child: const Text('重试载入')),
          ],
          SessionSummaryView(
            summary: summary,
            comparisons: feedbackComparisons,
            comparisonLoading: comparisonsLoading,
            comparisonError: comparisonError,
            onComparisonRetry: reloadData,
          ),
          const SizedBox(height: AppSpacing.xl),
          PrimaryButton(label: '完成', onPressed: () => context.go('/')),
        ],
      ),
    );
  }
}
