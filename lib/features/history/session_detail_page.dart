import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';

import '../../state/record_management_controller.dart';
import 'delete_session_dialog.dart';
import '../../state/data_revision_loader.dart';

// 执行器从**仓储层**拿，不从 data/db/ 直接拿 —— 见 executor_access.dart 的说明
import '../../data/repositories/executor_access.dart';
import '../../data/repositories/session_summary_loader.dart';
import '../../domain/session_summary.dart';
import '../../domain/local_date.dart';
import '../../ui/theme.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/session_summary_view.dart';

/// 历史详情：翻一场旧账。
///
/// 正文与总结页**逐像素一致** —— 因为它们就是同一个 [SessionSummaryView]，
/// 数字也来自同一个 [loadSessionSummary]。这一层只管三件事：加载中、找不到，
/// 以及给正文套一个滚动容器（那个 view 是**不滚动**的 Column）。
///
/// 与总结页的唯一差别在 AppBar：这里**有返回键**，用的是默认行为 —— 所以
/// 类里一个字都不用写。总结页的 `automaticallyImplyLeading: false` 是它刻意的
/// 另一回事（结束不可逆，只给一个出口），不要照抄到这里。
class SessionDetailPage extends StatefulWidget {
  final String sessionId;
  final LocalDate? historyDate;

  const SessionDetailPage({
    super.key,
    required this.sessionId,
    this.historyDate,
  });

  @override
  State<SessionDetailPage> createState() => _SessionDetailPageState();
}

class _SessionDetailPageState extends State<SessionDetailPage>
    with DataRevisionLoader<SessionDetailPage> {
  SessionSummary? _summary;
  bool _loading = true;

  @override
  Future<void> reloadData() => _load();

  Future<void> _load() async {
    final exec = context.read<SqlExecutor>();
    final summary = await loadSessionSummary(exec, widget.sessionId);

    if (!mounted) return;
    setState(() {
      _summary = summary;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('训练详情'),
        backgroundColor: c.background,
        actions: [
          if (context.watch<RecordManagementController?>() != null &&
              _summary != null)
            IconButton(
              tooltip: '删除这场训练',
              onPressed:
                  context.watch<RecordManagementController?>()?.busy == true
                  ? null
                  : () async {
                      if (await showDeleteSessionDialog(
                            context,
                            widget.sessionId,
                          ) &&
                          context.mounted) {
                        context.go(
                          '/history${widget.historyDate == null ? '' : '?date=${widget.historyDate!.key}'}',
                        );
                      }
                    },
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final summary = _summary;
    if (summary == null) {
      // 文案与总结页一字不差。**AppBar 留着**：详情是可以被深链进来的，
      // 这一个状态里若没有返回键，用户就卡在一个死页上。
      return const Center(child: Text('这场训练不存在'));
    }
    return ListView(
      padding: const EdgeInsets.all(AppSpacing.screenH),
      children: [
        if (summary.session.note?.isNotEmpty == true)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(summary.session.note!),
          ),
        SessionSummaryView(summary: summary),
      ],
    );
  }
}
