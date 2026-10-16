import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/data_revision_loader.dart';

// 执行器从**仓储层**拿，不从 data/db/ 直接拿 —— 见 executor_access.dart 的说明
import '../../data/repositories/executor_access.dart';
import '../../data/repositories/exercise_repo.dart';
import '../../data/repositories/progress_repo.dart';
import '../../domain/chart_geometry.dart';
import '../../domain/format.dart';
import '../../domain/progress.dart';
import '../../ui/theme.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/app_card.dart';
import '../../ui/widgets/stat_block.dart';
import '../../ui/widgets/trend_chart.dart';

/// 动作详情：横向分页的三张卡（最大重量 / 估算 1RM / 总容量）+ 页码点。
///
/// **三张卡的措辞是产品红线**（规格 §4.4）：两张力量卡写「最好」，容量卡写
/// 「最高」—— 容量是训练量不是力量成绩，练得轻但组数多的那一天容量反而更高；
/// 给它写「个人最好」是对用户身体的一句假话。
class ExerciseDetailPage extends StatefulWidget {
  final String exerciseId;

  const ExerciseDetailPage({super.key, required this.exerciseId});

  @override
  State<ExerciseDetailPage> createState() => _ExerciseDetailPageState();
}

class _ExerciseDetailPageState extends State<ExerciseDetailPage>
    with DataRevisionLoader<ExerciseDetailPage> {
  final PageController _controller = PageController();
  int _page = 0;

  /// 这个动作的**全部**点，按时间升序。null = 还在装载
  List<SessionPoint>? _points;

  /// 动作名。深链进来的陌生 id 取不到 —— 显示处一律兜「未知动作」，不崩
  String? _name;
  bool _loading = true;

  @override
  Future<void> reloadData() => _load();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final exec = context.read<SqlExecutor>();
    // 两条查询，各自「一次取全」：名字一条，已完成组一条 —— 不按动作逐个查组。
    //
    // **不复用进步列表的 `ExerciseProgressRow`**：它的 `recent` 只留最近 12 个点，
    // 而卡片头写的是「历史最好」（规格 §8 明确不设时间窗）。用截断过的序列求
    // 最大值，会在练满 12 次之后给出一个悄悄偏小的「最好」——不报错、不崩，
    // 只是数字是错的。
    final exercise = await getExercise(exec, widget.exerciseId);
    final facts = await listAllCompletedSetFacts(exec);

    if (!mounted) return;
    setState(() {
      _name = exercise?.name;
      _points = [
        for (final p in buildSessionPoints(facts))
          if (p.exerciseId == widget.exerciseId) p,
      ];
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    return Scaffold(
      appBar: AppBar(
        // 名字就是这一页的标题。取不到时写「未知动作」而不是留空 ——
        // 返回键仍然在（这一页在标签外壳外面，占满全屏）
        title: Text(_name ?? '未知动作'),
        backgroundColor: c.background,
      ),
      body: _body(),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final points = _points!;
    if (points.isEmpty) {
      // 没练过的动作（深链进来的陌生 id 也一样）—— 一句真话，不是三条假曲线。
      // AppBar 留着：深链进来时那是唯一的出口。
      return const Center(child: Text('这个动作还没有记录'));
    }

    final cards = _cards(points);
    return Column(
      children: [
        const SizedBox(height: AppSpacing.lg),
        _PageDots(count: cards.length, index: _page),
        const SizedBox(height: AppSpacing.lg),
        Expanded(
          child: PageView(
            controller: _controller,
            onPageChanged: (i) => setState(() => _page = i),
            children: cards,
          ),
        ),
      ],
    );
  }

  /// 三张卡。**顺序就是页序**：最大重量 / 估算 1RM / 总容量。
  List<Widget> _cards(List<SessionPoint> points) {
    final topWeights = [for (final p in points) p.topWeight];
    final e1rms = [for (final p in points) p.bestE1rm];
    final volumes = [for (final p in points) p.volumeLoad];

    final topIndex = _bestIndex(topWeights);
    final e1rmIndex = _bestIndex(e1rms);
    final volumeIndex = _bestIndex(volumes);

    // e1RM 序列里的缺口数。走 `countGaps` 而不是自己 `.where(...).length`
    // —— 图上的缺口（画线跳过的那些）与这句话里的 N **必须是同一个数**，
    // 两处各写一遍定义，将来定义一变就会在同一张图上写出两个不同的数。
    final gapCount = countGaps(e1rms);

    return [
      _MetricCard(
        title: '最大重量',
        // ⚠️ 值必须**自己从全部点位里取最大值**。`ExerciseProgressRow.topWeight`
        // 是最近那一场的最重一组（列表行要的是它），拿来做卡片头，日期与数字
        // 就不再是同一天的了。
        value: _fmtKg(topWeights[topIndex]),
        head: '最好 · ${formatDate(points[topIndex].startedAt)}',
        values: topWeights,
        trainedOnce: points.length == 1,
      ),
      _MetricCard(
        title: '估算 1RM',
        // 一个可换算的组都没有时没有值、也没有日期 —— 空空的一栏比编一个数诚实
        value: e1rmIndex == -1 ? null : e1rms[e1rmIndex]!.round().toString(),
        head: e1rmIndex == -1
            ? null
            : '最好 · ${formatDate(points[e1rmIndex].startedAt)}',
        // 两句都是强制的（规格 §4.4）：估算了要说明是估算，
        // 并写清这个数是从哪一组来的 —— 不写出来用户没法核对
        notes: e1rmIndex == -1
            ? const []
            : [
                '估算 · 仅供参考',
                '来自 ${_fmtKg(points[e1rmIndex].e1rmWeight!)} kg × ${points[e1rmIndex].e1rmReps!}',
              ],
        values: e1rms,
        emptyMessage: '还没有可用于换算的组（次数都 > 10）',
        gapMessage: gapCount == 0 ? null : '有 $gapCount 次训练没有可用于换算的组（次数 > 10）',
        trainedOnce: points.length == 1,
      ),
      _MetricCard(
        title: '总容量',
        // **「最高」，不是「最好」** —— 容量是训练量，不是力量成绩（规格 §4.4）
        value: volumes[volumeIndex].round().toString(),
        head: '最高 · ${formatDate(points[volumeIndex].startedAt)}',
        values: volumes,
        trainedOnce: points.length == 1,
      ),
    ];
  }
}

/// 序列里最大值所在的**第一个**下标；一个可用值都没有时返回 -1。
///
/// 并列时取最早的（规格 §8）：「你第一次做到这个数」比「你上次也做到了」
/// 更像一条记录 —— 与 `layoutChart` 取高亮点同一条规矩。
int _bestIndex(List<double?> values) {
  var best = -1;
  for (var i = 0; i < values.length; i++) {
    final v = values[i];
    if (v == null) continue;
    if (best == -1 || v > values[best]!) best = i;
  }
  return best;
}

/// `60` / `62.5` —— 整数不写成 `60.0`。
///
/// 与 `record_page` 里那个 `_fmt` 同一条规则：显示成 `60.0` 会让人以为
/// 重量的精度到 0.1 kg。
String _fmtKg(double v) => formatWeightKg(v);

/// 一张卡：标题 + 最好值 + 日期 + 折线。
///
/// 三张卡共用同一个壳，差别只在标题、序列与几句附加说明 —— 各写一遍的话，
/// 「最好」与「最高」这两个字的差别（正是产品红线）会在某一次改动里被抹平。
class _MetricCard extends StatelessWidget {
  final String title;

  /// null = 这条序列一个可用的点都没有（只有 e1RM 会这样），
  /// 此时整张卡只剩 [emptyMessage]
  final String? value;

  /// `最好 · 11月13日 周一` / `最高 · …`
  final String? head;

  /// 卡片头下的固定说明（e1RM 那两句）
  final List<String> notes;

  /// 喂给 [TrendChart] 的序列，与 [value] 同源
  final List<double?> values;

  final String? emptyMessage;

  /// 序列里有缺口时图下的说明
  final String? gapMessage;

  /// 这个动作只练过一次 —— 一个点画不出线，图下写一句为什么
  final bool trainedOnce;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.head,
    this.notes = const [],
    required this.values,
    this.emptyMessage,
    this.gapMessage,
    this.trainedOnce = false,
  });

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    final value = this.value;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
      // 一页就是一屏，字号放大时让卡片自己滚 —— 数字宁可滚一下也不许被切掉
      child: SingleChildScrollView(
        child: AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (value == null)
                // 与 StatBlock 的 label 同款，好让「没有值」的那张卡标题不跳档
                Text(
                  title,
                  style: TextStyle(
                    fontSize: AppFontSize.label,
                    letterSpacing: AppTracking.label,
                    color: c.textTertiary,
                  ),
                )
              else
                // Wrap 而不是 Row：字号放大 2 倍时「最好 · 日期」会与值挤在一行
                // 挤出屏幕（总结页三块统计踩过同一个坑）
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.end,
                  runSpacing: AppSpacing.sm,
                  children: [
                    StatBlock(label: title, value: value, unit: 'kg'),
                    Text(
                      head!,
                      style: TextStyle(
                        fontSize: AppFontSize.caption,
                        color: c.textSecondary,
                      ),
                    ),
                  ],
                ),
              if (value == null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  emptyMessage!,
                  style: TextStyle(
                    fontSize: AppFontSize.caption,
                    color: c.textTertiary,
                  ),
                ),
              ] else ...[
                for (final note in notes) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    note,
                    style: TextStyle(
                      fontSize: AppFontSize.caption,
                      color: c.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                // 坐标一个字都不在这里算 —— 全部来自 `layoutChart`（见 trend_chart）
                TrendChart(values: values),
                if (gapMessage != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    gapMessage!,
                    style: TextStyle(
                      fontSize: AppFontSize.caption,
                      color: c.textTertiary,
                    ),
                  ),
                ],
                if (trainedOnce) ...[
                  const SizedBox(height: AppSpacing.md),
                  // 一个点连不成线，说明白为什么 —— 不画一条平线假装有走势
                  Text(
                    '再练一次就能看到走势',
                    style: TextStyle(
                      fontSize: AppFontSize.caption,
                      color: c.textTertiary,
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 页码点：告诉用户「一共有三张、现在在第几张」。
///
/// 尺寸写在文件里，不进 `tokens.dart` —— 只有本文件一个使用者，混进全局清单
/// 只会稀释它（与 `trend_chart.dart` 的尺度同一条理由）。
const double _dotSize = 8;
const double _dotActiveWidth = 20;

class _PageDots extends StatelessWidget {
  final int count;
  final int index;

  const _PageDots({required this.count, required this.index});

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (var i = 0; i < count; i++)
          Container(
            margin: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
            width: i == index ? _dotActiveWidth : _dotSize,
            height: _dotSize,
            decoration: BoxDecoration(
              color: i == index ? c.accent : c.border,
              borderRadius: BorderRadius.circular(_dotSize / 2),
            ),
          ),
      ],
    );
  }
}
