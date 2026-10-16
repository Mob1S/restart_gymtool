import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/executor_access.dart';
import '../../data/repositories/exercise_repo.dart';
import '../../state/plan_controller.dart';
import '../workout/exercise_picker.dart';

class PlanEditorPage extends StatefulWidget {
  final String? id;
  const PlanEditorPage({super.key, this.id});
  @override
  State<PlanEditorPage> createState() => _PlanEditorPageState();
}

class _PlanEditorPageState extends State<PlanEditorPage> {
  final _name = TextEditingController();
  Map<String, String> _names = {};
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final c = context.read<PlanController>();
      final exec = context.read<SqlExecutor>();
      await c.loadDraft(widget.id);
      final exercises = await listExercises(exec, includeArchived: true);
      if (mounted) {
        setState(() {
          _names = {
            for (final e in exercises)
              e.id: '${e.name}${e.isArchived ? '（归档）' : ''}',
          };
          _name.text = c.draft?.name ?? '';
        });
      }
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
              if (draft.exerciseIds.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Text('空计划也可以保存，开训后可再添加动作。'),
                ),
              for (var i = 0; i < draft.exerciseIds.length; i++)
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        title: Text(
                          '${i + 1}. ${_names[draft.exerciseIds[i]] ?? '动作'}',
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          IconButton(
                            tooltip: '上移动作',
                            onPressed: c.busy || i == 0
                                ? null
                                : () => c.moveDraftItem(i, -1),
                            icon: const Icon(Icons.arrow_upward),
                          ),
                          IconButton(
                            tooltip: '下移动作',
                            onPressed:
                                c.busy || i == draft.exerciseIds.length - 1
                                ? null
                                : () => c.moveDraftItem(i, 1),
                            icon: const Icon(Icons.arrow_downward),
                          ),
                          IconButton(
                            tooltip: '移除计划动作',
                            onPressed: c.busy
                                ? null
                                : () => c.removeDraftItem(i),
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              OutlinedButton(
                onPressed: c.busy
                    ? null
                    : () async {
                        final e = await showExercisePicker(context);
                        if (e != null && mounted) {
                          setState(() => _names[e.id] = e.name);
                          c.addExercise(e.id);
                        }
                      },
                child: const Text('添加动作'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
