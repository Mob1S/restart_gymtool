import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../domain/motion_catalog.dart';

class MotionCatalogPage extends StatefulWidget {
  const MotionCatalogPage({super.key});
  @override
  State<MotionCatalogPage> createState() => _MotionCatalogPageState();
}

class _MotionCatalogPageState extends State<MotionCatalogPage> {
  String query = '', equipment = '全部', bodyPart = '全部', category = '全部';

  @override
  Widget build(BuildContext context) {
    final found = MotionCatalog.profiles
        .where(
          (p) =>
              (query.isEmpty ||
                  p.name.contains(query) ||
                  p.id.contains(query.toLowerCase())) &&
              (equipment == '全部' || p.equipment == equipment) &&
              (bodyPart == '全部' || p.bodyPart == bodyPart) &&
              (category == '全部' || p.category == category),
        )
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('动作库')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: '搜索动作',
            ),
            onChanged: (v) => setState(() => query = v.trim()),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _filter('器械', equipment, [
                '全部',
                '杠铃',
                '自重',
              ], (v) => equipment = v),
              _filter('部位', bodyPart, [
                '全部',
                '腿部',
                '胸部',
                '背部',
              ], (v) => bodyPart = v),
              _filter('类别', category, [
                '全部',
                '蹲',
                '推',
                '拉',
              ], (v) => category = v),
            ],
          ),
          const SizedBox(height: 12),
          for (final p in found)
            Card(
              child: ListTile(
                title: Text(p.name),
                subtitle: Text(
                  '${p.equipment} · ${p.bodyPart} · ${p.category} · 实验性分析',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.go('/analysis/catalog/${p.id}'),
              ),
            ),
          if (found.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('没有找到匹配的动作。'),
            ),
        ],
      ),
    );
  }

  Widget _filter(
    String label,
    String value,
    List<String> values,
    void Function(String) change,
  ) => DropdownButton<String>(
    value: value,
    items: [
      for (final v in values)
        DropdownMenuItem(value: v, child: Text('$label：$v')),
    ],
    onChanged: (v) {
      if (v != null) setState(() => change(v));
    },
  );
}

class MotionDetailPage extends StatelessWidget {
  final String motionId;
  const MotionDetailPage({super.key, required this.motionId});
  @override
  Widget build(BuildContext context) {
    final p = MotionCatalog.byId(motionId);
    return Scaffold(
      appBar: AppBar(title: Text(p.name)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(p.description, style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(height: 16),
          Text('重复周期', style: Theme.of(context).textTheme.titleMedium),
          Text(p.phases.join(' → ')),
          Text('不计入：${p.exclusions.join('、')}'),
          const SizedBox(height: 16),
          Text('轨迹目标', style: Theme.of(context).textTheme.titleMedium),
          Text(p.trajectoryTargets.join('、')),
          const SizedBox(height: 16),
          Text('当前分析能力', style: Theme.of(context).textTheme.titleMedium),
          const Text('次数：实验性候选，需人工核对。人体关键点轨迹：可见时展示，缺失处断开。'),
          Text(
            p.id == MotionCatalog.bench
                ? '杠铃轨迹：侧面机位可手动标记近侧杠铃片后跟踪。'
                : '器械轨迹：尚无已验证检测器，不会以人体关键点代替。',
          ),
          Text('质量观察：${p.candidateObservations.join('、')}；尚未通过标注验证，当前不可评估。'),
          const SizedBox(height: 16),
          Text('建议机位与限制', style: Theme.of(context).textTheme.titleMedium),
          for (final view in MotionView.values)
            ListTile(
              title: Text(view.label),
              subtitle: Text(p.viewAdvice[view] ?? '暂无说明'),
              trailing: Text(
                p.capability(view) == MotionCapability.unavailable
                    ? '未开放'
                    : '实验性',
              ),
            ),
          const Text('质量观察需有标注样本验证；证据不足时显示不可评估。'),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => context.go('/analysis/import?motion=${p.id}'),
            child: const Text('导入视频分析'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => context.go('/analysis/camera?motion=${p.id}'),
            child: const Text('实时拍摄分析'),
          ),
        ],
      ),
    );
  }
}
