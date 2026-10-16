import 'package:flutter/material.dart';

import '../../domain/format.dart';
import '../../domain/import_preview.dart';
import '../../domain/workout_csv.dart';
import '../../state/import_controller.dart';

class ImportPreviewView extends StatelessWidget {
  final ImportController controller;
  const ImportPreviewView({super.key, required this.controller});
  @override
  Widget build(BuildContext context) {
    final c = controller;
    final draft = c.draft!;
    final selection = c.selection!;
    void update({
      Set<int>? selected,
      Map<String, String?>? matches,
      bool? acknowledge,
    }) => c.updateSelection(
      ImportSelection(
        selected: selected ?? selection.selected,
        matches: matches ?? selection.matches,
        acknowledgeSkipped: acknowledge ?? selection.acknowledgeSkipped,
      ),
    );
    final selectedStats = [
      for (final i in selection.selected) draft.parsed.statsByWorkout[i],
    ];
    final pounds = selectedStats.fold(0, (n, s) => n + s.poundsConverted);
    final unknown = selectedStats.where((s) => s.durationUnknown).length;
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(16),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  c.fileName ?? '手动补记',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(
                  '来源：${draft.parsed.source == CsvSource.unknown ? '手动' : draft.parsed.source.name} · ${draft.parsed.workouts.length} 场候选',
                ),
                if (draft.parsed.source == CsvSource.strong)
                  DropdownButtonFormField<WeightUnit>(
                    initialValue: c.unit,
                    decoration: const InputDecoration(labelText: '无单位重量按'),
                    items: WeightUnit.values
                        .map(
                          (u) =>
                              DropdownMenuItem(value: u, child: Text(u.name)),
                        )
                        .toList(),
                    onChanged: c.busy
                        ? null
                        : (v) {
                            if (v != null) c.changeUnit(v);
                          },
                  ),
                const Text(
                  '无时区时间按本机时区解释；仅日期数据按中午 12:00。同日、同名且无具体时间的记录会合为一场。相同组数值会保留，重复提示仅比较完整训练。',
                ),
                Text(
                  '所选：${selection.selected.length} 场 · 磅换算 $pounds 行 · 时长未知 $unknown 场',
                ),
                if (draft.parsed.unknownDurationCount > 0)
                  const Text('来源没有结束时间的训练将显示 0 秒占位；详情保留「时长未知」说明。'),
                if (draft.parsed.skipped.isNotEmpty) ...[
                  ListTile(
                    title: Text('${draft.parsed.skipped.length} 行无效，查看原因'),
                    onTap: () => showDialog<void>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('跳过的行'),
                        content: SizedBox(
                          width: 500,
                          height: 360,
                          child: ListView.builder(
                            itemCount: draft.parsed.skipped.length,
                            itemBuilder: (_, i) {
                              final issue = draft.parsed.skipped[i];
                              return ListTile(
                                title: Text('第 ${issue.line} 行'),
                                subtitle: Text(issue.reason),
                              );
                            },
                          ),
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('关闭'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  CheckboxListTile(
                    value: selection.acknowledgeSkipped,
                    title: Text('已了解将跳过 ${draft.parsed.skipped.length} 行'),
                    onChanged: c.busy ? null : (v) => update(acknowledge: v),
                  ),
                ],
                const Divider(),
                for (final entry in draft.matches.entries) ...[
                  if (entry.value.length > 1)
                    DropdownButtonFormField<String>(
                      key: ValueKey((entry.key, selection.matches[entry.key])),
                      initialValue: selection.matches.containsKey(entry.key)
                          ? selection.matches[entry.key] ?? '__new__'
                          : null,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: '同名动作需确认：${entry.key}',
                      ),
                      items: [
                        for (final e in entry.value)
                          DropdownMenuItem(
                            value: e.id,
                            child: Text(
                              '${e.name}${e.isArchived ? '（归档）' : ''} · ${e.id.substring(0, e.id.length.clamp(0, 8))}',
                            ),
                          ),
                        const DropdownMenuItem(
                          value: '__new__',
                          child: Text('新建动作'),
                        ),
                      ],
                      onChanged: c.busy
                          ? null
                          : (v) => update(
                              matches: {
                                ...selection.matches,
                                entry.key: v == '__new__' ? null : v,
                              },
                            ),
                    )
                  else
                    ListTile(
                      dense: true,
                      title: Text(
                        entry.value.isEmpty
                            ? '${entry.key} → 新建动作'
                            : '${entry.value.single.name} → 复用已有${entry.value.single.isArchived ? '（归档）' : ''}',
                      ),
                    ),
                ],
                const Divider(),
              ],
            ),
          ),
        ),
        SliverList.builder(
          itemCount: draft.parsed.workouts.length,
          itemBuilder: (context, i) => CheckboxListTile(
            value: selection.selected.contains(i),
            title: Text(
              '${draft.parsed.workouts[i].name ?? '训练'} · ${formatDateTime(draft.parsed.workouts[i].startedAt)}',
            ),
            subtitle: Text(
              '${draft.duplicates.contains(i) ? '疑似重复，默认不追加\n' : ''}${draft.parsed.workouts[i].exercises.map((e) => '${e.name} ${e.sets.length} 组').join('、')}\n${draft.parsed.workouts[i].exercises.map((e) => e.sets.map((s) => '${s.weight.toStringAsFixed(2)} kg × ${s.reps}').join(' / ')).join('\n')}',
            ),
            onChanged: c.busy
                ? null
                : (v) => update(
                    selected: {...selection.selected}
                      ..removeWhere((x) => x == i && v != true)
                      ..addAll(v == true ? [i] : []),
                  ),
          ),
        ),
        if (draft.parsed.workouts.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text('没有可导入的有效训练，请重新选择文件。'),
            ),
          ),
      ],
    );
  }
}
