import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

// 执行器从**仓储层**拿，不从 data/db/ 直接拿 —— 见 executor_access.dart 的说明
import '../../data/repositories/executor_access.dart';
import '../../data/repositories/session_repo.dart';
import '../../domain/format.dart';
import '../../ui/theme.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/app_card.dart';
import '../../ui/widgets/empty_state.dart';

/// 历史列表：已结束的训练，最近的在前。
///
/// 行上那三个数（时长 / 组数 / 容量）**一个都不在这里算** —— 它们来自
/// [listSessionSummaries] 的一条聚合查询。在这一层重算的话，同一场训练会在
/// 历史行与总结页上量出两个值，而且不会有任何测试变红。
class HistoryPage extends StatefulWidget {
  const HistoryPage({super.key});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
  List<SessionSummaryRow>? _rows;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final exec = context.read<SqlExecutor>();
    final rows = await listSessionSummaries(exec);

    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final rows = _rows!;

    if (rows.isEmpty) {
      // 两句都要写：只说「还没有」是死路，第二句才是下一步。
      // 第二句放进 action 槽位 —— 那里本来就是「给用户下一步」的位置；
      // 这一步不该做成按钮（「去练一次」在「训练」标签里）。
      return EmptyState(
        message: '还没有已完成的训练',
        action: Text(
          '完成第一次训练后，这里会留下记录',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: AppFontSize.caption,
            color: c.textTertiary,
          ),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenH,
        vertical: AppSpacing.lg,
      ),
      itemCount: rows.length,
      itemBuilder: (context, i) => Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.md),
        child: _HistoryRow(row: rows[i]),
      ),
    );
  }
}

/// 历史列表的一行：日期 / 名称 / `时长 · N 组 · M kg`。
///
/// 不拆单独文件 —— 行内就这几行文本，没有值得单独被测的逻辑。
class _HistoryRow extends StatelessWidget {
  final SessionSummaryRow row;

  const _HistoryRow({required this.row});

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    final session = row.session;

    return AppCard(
      // 必须用 **push 不是 go**：`go` 会把整个导航栈换成详情页那一层，
      // 于是详情页上**没有返回键** —— 用户点进一条记录就出不来了。
      // 这个坑只有真的从列表点一次才看得见：把详情页单独 pump 起来
      // （底下垫一个 home 当栈底）时，返回键是有的，测试会绿。
      // 守它的是 `test/app/router_test.dart` 里「从列表点进详情页」那一条
      // —— 它**点的是真行**，所以换回 `go` 会让它红。
      onTap: () => context.push('/history/${session.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            formatDate(session.startedAt),
            style: TextStyle(
              fontSize: AppFontSize.caption,
              color: c.textTertiary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            // 名字可以为空（直接开训练、没填名字）—— 不兜底的话这一行只剩
            // 日期和数字，读起来不像一条训练记录
            session.name ?? '未命名训练',
            style: TextStyle(
              fontSize: AppFontSize.title,
              fontWeight: FontWeight.w600,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            // 三个数全部照搬聚合查询的结果：时长走 domain/format 的
            // formatDuration、容量只做一次 round —— 不在行里做任何运算
            '${formatDuration(row.durationSeconds)} · ${row.setCount} 组 · ${row.volumeLoad.round()} kg',
            style: TextStyle(
              fontSize: AppFontSize.caption,
              color: c.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
