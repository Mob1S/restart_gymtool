import 'package:flutter/material.dart';

import '../../plugins/flutter/plugin_ui_adapter.dart';
import '../../domain/beverage.dart';
import '../../domain/beverage_trends.dart';
import '../../domain/local_date.dart';
import '../../state/data_revision_loader.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/app_card.dart';

class CalorieTrendsPage extends StatefulWidget {
  final LocalDate date;
  const CalorieTrendsPage({super.key, required this.date});
  @override
  State<CalorieTrendsPage> createState() => _CalorieTrendsPageState();
}

class _CalorieTrendsPageState extends State<CalorieTrendsPage>
    with DataRevisionLoader<CalorieTrendsPage> {
  int _days = 7, _generation = 0;
  List<DrinkRecord>? _records;
  String? _error;
  @override
  Future<void> reloadData() async {
    final generation = ++_generation;
    try {
      final records = await caloriesClient(context).records(
        from: LocalDate.fromDateTime(
          DateTime(widget.date.year, widget.date.month, widget.date.day - 29),
        ),
        through: widget.date,
      );
      if (mounted && generation == _generation) {
        setState(() {
          _records = records;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = '趋势读取失败，请重试');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final trend = beverageTrend(_records ?? [], widget.date, _days);
    final records = trend.values.expand((t) => t.records).toList();
    final total = DrinkTotal(records);
    final contributions = beverageContributions(records);
    final max = trend.values.fold<double>(
      1,
      (m, t) => t.calories.asDouble > m ? t.calories.asDouble : m,
    );
    return Scaffold(
      appBar: AppBar(title: const Text('饮料热量趋势')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screenH),
        children: [
          Text('截至 ${widget.date.key} 的已记录饮料热量'),
          const SizedBox(height: AppSpacing.md),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 7, label: Text('近 7 天')),
              ButtonSegment(value: 30, label: Text('近 30 天')),
            ],
            selected: {_days},
            onSelectionChanged: (s) => setState(() => _days = s.single),
          ),
          const SizedBox(height: AppSpacing.lg),
          if (_error != null) ...[
            Text(_error!),
            TextButton(onPressed: reloadData, child: const Text('重试')),
          ] else if (_records == null)
            const LinearProgressIndicator()
          else ...[
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('区间已知合计'),
                  Text(
                    total.display,
                    style: Theme.of(context).textTheme.headlineLarge,
                  ),
                  Text(total.note),
                  const Text('只统计已记录饮料；缺口代表未记录，不代表零摄入。'),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            // Every bar has a visible textual value; zero and unknown are distinct.
            for (final entry in trend.entries)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: AppSpacing.md,
                      children: [
                        Text(entry.key.key),
                        Text(entry.value.display),
                        if (entry.value.note.isNotEmpty) Text(entry.value.note),
                      ],
                    ),
                    if (entry.value.records.isNotEmpty &&
                        entry.value.unknown < entry.value.records.length)
                      LinearProgressIndicator(
                        value: (entry.value.calories.asDouble / max).clamp(
                          0,
                          1,
                        ),
                        minHeight: AppSpacing.sm,
                        semanticsLabel:
                            '${entry.key.key} ${entry.value.display}',
                      ),
                  ],
                ),
              ),
            const Divider(height: AppSpacing.xxl),
            Text('饮料热量贡献', style: Theme.of(context).textTheme.titleLarge),
            for (final group in contributions)
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(group.records.first.snapshot.name),
                subtitle: Text(
                  '${group.records.first.snapshot.description}\n${group.records.length} 条 · ${group.note}',
                ),
                trailing: Text(group.display),
              ),
          ],
        ],
      ),
    );
  }
}
