import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

// 执行器从**仓储层**拿，不从 data/db/ 直接拿 —— 见 executor_access.dart 的说明
import '../../data/repositories/executor_access.dart';
import '../../data/repositories/exercise_repo.dart';
import '../../data/repositories/progress_repo.dart';
import '../../domain/format.dart';
import '../../domain/progress_index.dart';
import '../../ui/theme.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/app_card.dart';
import '../../ui/widgets/empty_state.dart';
import '../../ui/widgets/trend_chart.dart';

/// 进步列表：练过的动作，最近练过的在最上面。
///
/// 数据只查一次：[listAllCompletedSetFacts] 的结果同时喂给行上的数字与右侧的
/// 迷你走势。按动作逐个查是 N+1，在手机上会肉眼可见地卡（规格 §3.1）。
class ProgressPage extends StatefulWidget {
  const ProgressPage({super.key});

  @override
  State<ProgressPage> createState() => _ProgressPageState();
}

class _ProgressPageState extends State<ProgressPage> {
  List<ExerciseProgressRow>? _rows;
  Map<String, String> _nameById = const {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final exec = context.read<SqlExecutor>();
    final facts = await listAllCompletedSetFacts(exec);
    // 名字**一次全取**，不按行逐个 `getExercise` —— 那正是 N+1 的形状，
    // 而这一页要的只是一张 id → 名字的映射表。
    // 代价（明确接受）：`listExercises` 不含已归档的动作，被归档的旧动作会落到
    // 「未知动作」上。今天没有任何入口能归档动作；真出现时也只是名字显示不出来，
    // **不崩**。
    final exercises = await listExercises(exec);

    if (!mounted) return;
    setState(() {
      _rows = buildProgressIndex(facts);
      _nameById = {for (final e in exercises) e.id: e.name};
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final rows = _rows!;

    if (rows.isEmpty) {
      // 只写这一句：「没练过」不是「0」，也不给假数据把列表填满（规格 §6）
      return const EmptyState(message: '还没有练过的动作');
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.screenH,
        vertical: AppSpacing.lg,
      ),
      itemCount: rows.length,
      itemBuilder: (context, i) {
        final row = rows[i];
        return Padding(
          padding: const EdgeInsets.only(bottom: AppSpacing.md),
          child: _ProgressRow(
            row: row,
            // 取不到名字也照常显示这一行 —— 走势是这个动作仅剩的东西了
            name: _nameById[row.exerciseId] ?? '未知动作',
          ),
        );
      },
    );
  }
}

/// 进步列表的一行：动作名 / 「最近 … · 最重 …」 / 右侧迷你走势。
///
/// 不拆单独文件 —— 行内就这几行文本，没有值得单独被测的逻辑。
class _ProgressRow extends StatelessWidget {
  final ExerciseProgressRow row;
  final String name;

  const _ProgressRow({required this.row, required this.name});

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    return AppCard(
      // go 而不是 push：动作详情在标签外壳**外面**（占满全屏、带返回键），
      // 由路由表决定它落在哪儿，这一层只说「去那里」
      onTap: () => context.go('/progress/${row.exerciseId}'),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: AppFontSize.title,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  // 两个数**必须是同一天的**：日期与「最重」都取自最近那一场。
                  // 换成历史最大值，屏幕上会出现「最近 9/10 · 最重 100 kg」——
                  // 日期与数字各说各话，比不显示还糟（`ExerciseProgressRow` 的说明）
                  '最近 ${formatDate(row.lastTrainedAt)} · 最重 ${_fmtKg(row.topWeight)} kg × ${row.topWeightReps}',
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    color: c.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          // 迷你走势画的是**这一行自己那个数**（最重）的走势 ——
          // 数字和图讲同一件事，读起来才不会串
          TrendChart(
            values: [for (final p in row.recent) p.topWeight],
            compact: true,
          ),
        ],
      ),
    );
  }
}

/// `60` / `62.5` —— 整数不写成 `60.0`。
///
/// 与 `record_page` 里那个 `_fmt` 同一条规则：显示成 `60.0` 会让人以为
/// 重量的精度到 0.1 kg。
String _fmtKg(double v) =>
    v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
