import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/plan_controller.dart';
import 'day_editor_sheet.dart';

class PlanEditorPage extends StatefulWidget {
  final String? id;
  const PlanEditorPage({super.key, this.id});
  @override
  State<PlanEditorPage> createState() => _PlanEditorPageState();
}

class _PlanEditorPageState extends State<PlanEditorPage> {
  final _name = TextEditingController();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final c = context.read<PlanController>();
      await c.loadDraft(widget.id);
      if (mounted) _name.text = c.draft?.name ?? '';
    });
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<PlanController>();
    final draft = c.draft;
    return PopScope(
      canPop: !c.busy && !c.dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || c.busy) return;
        final discard = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('丢弃未保存的计划？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('继续编辑'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('丢弃'),
              ),
            ],
          ),
        );
        if (discard == true && context.mounted) {
          c.discardDraft();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) Navigator.pop(context);
          });
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.id == null ? '新建计划' : '编辑计划'),
          actions: [
            TextButton(
              onPressed: c.busy || draft == null
                  ? null
                  : () async {
                      if (await c.saveDraft() && context.mounted) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (context.mounted) Navigator.pop(context);
                        });
                      }
                    },
              child: const Text('保存'),
            ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (c.busy) const LinearProgressIndicator(),
            if (c.message != null) Text(c.message!),
            if (draft != null) ...[
              TextField(
                controller: _name,
                onChanged: c.updateName,
                enabled: !c.busy,
                decoration: const InputDecoration(labelText: '计划名称'),
              ),
              const SizedBox(height: 24),
              Text(
                '训练日 · ${draft.days.length} 天',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              const Text('按这里的顺序轮换，训练日数量和名称可自由设置。'),
              if (draft.days.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('还没有训练日。可以先保存计划，稍后配置。'),
                ),
              for (var i = 0; i < draft.days.length; i++)
                Card(
                  key: ValueKey(c.dayKeys[i]),
                  child: Column(
                    children: [
                      ListTile(
                        title: Text('${i + 1}. ${draft.days[i].name}'),
                        subtitle: Text(
                          '${draft.days[i].exerciseIds.length} 个动作',
                        ),
                        onTap: c.busy
                            ? null
                            : () async {
                                final day = await showDayEditorSheet(
                                  context,
                                  day: draft.days[i],
                                );
                                if (day != null && mounted) c.updateDay(i, day);
                              },
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            tooltip: '编辑训练日',
                            onPressed: c.busy
                                ? null
                                : () async {
                                    final day = await showDayEditorSheet(
                                      context,
                                      day: draft.days[i],
                                    );
                                    if (day != null && mounted) {
                                      c.updateDay(i, day);
                                    }
                                  },
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            tooltip: '上移训练日',
                            onPressed: c.busy || i == 0
                                ? null
                                : () => c.moveDay(i, -1),
                            icon: const Icon(Icons.arrow_upward),
                          ),
                          IconButton(
                            tooltip: '下移训练日',
                            onPressed: c.busy || i == draft.days.length - 1
                                ? null
                                : () => c.moveDay(i, 1),
                            icon: const Icon(Icons.arrow_downward),
                          ),
                          IconButton(
                            tooltip: '删除训练日',
                            onPressed: c.busy
                                ? null
                                : () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                        title: Text(
                                          '删除训练日「${draft.days[i].name}」？',
                                        ),
                                        content: const Text(
                                          '保存计划后移除这个训练日，已有训练记录会保留。',
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, false),
                                            child: const Text('取消'),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, true),
                                            child: const Text('删除训练日'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm == true && mounted) {
                                      c.removeDay(i);
                                    }
                                  },
                            icon: const Icon(Icons.delete_outline),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              OutlinedButton.icon(
                onPressed: c.busy
                    ? null
                    : () async {
                        final day = await showDayEditorSheet(context);
                        if (day != null && mounted) c.addDay(day);
                      },
                icon: const Icon(Icons.add),
                label: const Text('添加训练日'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
