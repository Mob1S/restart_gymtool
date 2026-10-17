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
    final preview = c.plans.where((plan) => plan.id == id).firstOrNull;
    if (preview == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除计划「${preview.name}」？'),
        content: Text(
          '将移除 ${preview.days.length} 个训练日及其动作清单。历史训练和进行中的训练仍会保留，只解除计划关联。此操作无法撤销。',
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
            child: const Text('新建计划'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('一套计划包含多个训练日。完成整次训练后，按该计划的训练日顺序轮换，也可手动选择。'),
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
                    title: Text(c.plans[i].name),
                    subtitle: Text(
                      '${c.plans[i].days.length} 个训练日 · ${c.plans[i].days.fold<int>(0, (n, day) => n + day.exerciseIds.length)} 个动作',
                    ),
                    onTap: c.busy
                        ? null
                        : () => _edit('/plans/${c.plans[i].id}/edit'),
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      IconButton(
                        tooltip: '上移计划',
                        onPressed: c.busy || i == 0
                            ? null
                            : () => c.movePlan(c.plans[i].id, -1),
                        icon: const Icon(Icons.arrow_upward),
                      ),
                      IconButton(
                        tooltip: '下移计划',
                        onPressed: c.busy || i == c.plans.length - 1
                            ? null
                            : () => c.movePlan(c.plans[i].id, 1),
                        icon: const Icon(Icons.arrow_downward),
                      ),
                      IconButton(
                        tooltip: '删除计划',
                        onPressed: c.busy ? null : () => _delete(c.plans[i].id),
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
