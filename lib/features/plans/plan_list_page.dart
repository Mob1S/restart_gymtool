import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../state/plan_controller.dart';

class PlanListPage extends StatefulWidget {
  const PlanListPage({super.key});
  @override
  State<PlanListPage> createState() => _PlanListPageState();
}

class _PlanListPageState extends State<PlanListPage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) context.read<PlanController>().loadList();
    });
  }

  Future<void> _edit(String route) async {
    await context.push(route);
    if (mounted) await context.read<PlanController>().loadList();
  }

  Future<void> _delete(String id) async {
    final c = context.read<PlanController>();
    final preview = await c.previewDelete(id);
    if (preview == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除计划「${preview.name}」？'),
        content: Text(
          '将移除 ${preview.exerciseCount} 个计划动作。${preview.completedReferences} 场历史训练和 ${preview.activeReferences} 场活动训练仍会保留，只解除计划关联。此操作无法撤销。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除计划'),
          ),
        ],
      ),
    );
    if (confirmed == true) await c.confirmDelete(preview);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PlanController>();
    return Scaffold(
      appBar: AppBar(
        title: const Text('训练计划'),
        actions: [
          TextButton(
            onPressed: c.busy ? null : () => _edit('/plans/new'),
            child: const Text('新建'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('计划只保存动作清单和顺序。重量、次数沿用上次成绩；完成一场后自动轮转到下一套。'),
          if (c.busy) const LinearProgressIndicator(),
          if (c.message != null) Text(c.message!),
          if (c.plans.isEmpty && !c.busy)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('还没有计划，点击右上角新建。'),
            ),
          for (var i = 0; i < c.plans.length; i++)
            Card(
              child: Column(
                children: [
                  ListTile(
                    title: Text(c.plans[i].template.name),
                    subtitle: Text('${c.plans[i].exerciseCount} 个动作'),
                    onTap: c.busy
                        ? null
                        : () => _edit('/plans/${c.plans[i].template.id}/edit'),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: '上移计划',
                        onPressed: c.busy || i == 0
                            ? null
                            : () => c.movePlan(c.plans[i].template.id, -1),
                        icon: const Icon(Icons.arrow_upward),
                      ),
                      IconButton(
                        tooltip: '下移计划',
                        onPressed: c.busy || i == c.plans.length - 1
                            ? null
                            : () => c.movePlan(c.plans[i].template.id, 1),
                        icon: const Icon(Icons.arrow_downward),
                      ),
                      IconButton(
                        tooltip: '删除计划',
                        onPressed: c.busy
                            ? null
                            : () => _delete(c.plans[i].template.id),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
