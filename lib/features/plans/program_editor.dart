import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/training_plans.dart';
import '../../domain/training_prescription.dart';
import '../../data/repositories/executor_access.dart';
import '../../data/repositories/training_plan_repo.dart';
import '../../data/repositories/training_program_repo.dart';
import '../../data/repositories/exercise_repo.dart';
import '../../state/data_revision.dart';
import 'target_editor.dart';

class ProgramEditor extends StatefulWidget {
  final String planId;
  const ProgramEditor({super.key, required this.planId});
  @override
  State<ProgramEditor> createState() => _ProgramEditorState();
}

class _ProgramEditorState extends State<ProgramEditor> {
  TrainingPlanDetail? _plan;
  TrainingProgram? _program;
  String? _original, _view, _error;
  Map<String, String> _names = {};
  bool _busy = false, _dirty = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = context.read<SqlExecutor>();
      final plan = await getTrainingPlan(db, widget.planId);
      final program = await readTrainingProgram(db, widget.planId);
      final names = {
        for (final e in await listExercises(db, includeArchived: true))
          e.id: e.name,
      };
      if (mounted) {
        setState(() {
          _plan = plan;
          _original = program?.encode();
          _program =
              program ??
              TrainingProgram(
                stages: [
                  ProgramStage(id: 'default', name: '基础阶段', targets: {}),
                ],
                currentStageId: 'default',
              );
          _view = _program!.currentStageId;
          _names = names;
          _dirty = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  TrainingProgram _withStages(List<ProgramStage> stages, {String? current}) {
    final p = _program!;
    return TrainingProgram(
      stages: stages,
      currentStageId: current ?? p.currentStageId,
      sourceTitle: p.sourceTitle,
      sourceUrl: p.sourceUrl,
      notes: p.notes,
      templateKey: p.templateKey,
    );
  }

  Future<void> _save({String? current}) async {
    if (_busy || _program == null) return;
    setState(() => _busy = true);
    try {
      final next = current == null ? _program! : _program!.select(current);
      await saveTrainingProgram(
        context.read<SqlExecutor>(),
        widget.planId,
        next,
        expectedPayload: _original,
      );
      if (mounted) {
        context.read<DataRevision?>()?.changed();
        setState(() {
          _program = next;
          _view = current ?? _view;
          _original = next.encode();
          _dirty = false;
          _error = null;
        });
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已保存，下次开训生效')));
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _name(String title, String initial) async {
    final c = TextEditingController(text: initial);
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          decoration: const InputDecoration(labelText: '阶段名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (c.text.trim().isNotEmpty) Navigator.pop(ctx, c.text.trim());
            },
            child: const Text('确定'),
          ),
        ],
      ),
    );
    c.dispose();
    return value;
  }

  @override
  Widget build(BuildContext context) {
    final p = _program, plan = _plan;
    return PopScope(
      canPop: !_busy && !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _busy || !_dirty) return;
        final discard = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('丢弃未保存的组次与阶段？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('继续编辑'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('丢弃'),
              ),
            ],
          ),
        );
        if (discard == true && mounted) {
          setState(() => _dirty = false);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) Navigator.pop(context);
          });
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('组次与阶段'),
          actions: [
            TextButton(
              onPressed: _busy || p == null ? null : () => _save(),
              child: const Text('保存'),
            ),
          ],
        ),
        body: p == null
            ? Center(child: Text(_error ?? '正在载入'))
            : plan == null
            ? const Center(child: Text('计划已不存在'))
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    plan.name,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  Text('当前执行：${p.current.name}'),
                  const Text('阶段由你推进，可重复当前阶段；训练日和休息进度保持不变。'),
                  if (_busy) const LinearProgressIndicator(),
                  if (_error != null) Text(_error!),
                  if (p.stages.length > 1)
                    DropdownButtonFormField<String>(
                      key: ValueKey('view-$_view'),
                      initialValue: _view,
                      decoration: const InputDecoration(labelText: '查看／编辑阶段'),
                      items: [
                        for (final s in p.stages)
                          DropdownMenuItem(value: s.id, child: Text(s.name)),
                      ],
                      onChanged: _busy
                          ? null
                          : (v) => setState(() => _view = v),
                    ),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final direction in [-1, 1])
                        IconButton(
                          tooltip: direction < 0 ? '上移阶段' : '下移阶段',
                          onPressed:
                              _busy ||
                                  p.stages.indexWhere((s) => s.id == _view) +
                                          direction <
                                      0 ||
                                  p.stages.indexWhere((s) => s.id == _view) +
                                          direction >=
                                      p.stages.length
                              ? null
                              : () => setState(() {
                                  final stages = [...p.stages];
                                  final index = stages.indexWhere(
                                    (s) => s.id == _view,
                                  );
                                  final stage = stages.removeAt(index);
                                  stages.insert(index + direction, stage);
                                  _program = _withStages(stages);
                                  _dirty = true;
                                }),
                          icon: Icon(
                            direction < 0
                                ? Icons.arrow_upward
                                : Icons.arrow_downward,
                          ),
                        ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                final name = await _name(
                                  '添加阶段',
                                  '第 ${p.stages.length + 1} 阶段',
                                );
                                if (name != null && mounted) {
                                  setState(() {
                                    final id =
                                        'stage-${DateTime.now().microsecondsSinceEpoch}';
                                    _program = _withStages([
                                      ...p.stages,
                                      ProgramStage(
                                        id: id,
                                        name: name,
                                        targets: p.stages
                                            .firstWhere((s) => s.id == _view)
                                            .targets,
                                      ),
                                    ]);
                                    _view = id;
                                    _dirty = true;
                                  });
                                }
                              },
                        child: const Text('添加阶段'),
                      ),
                      TextButton(
                        onPressed: _busy
                            ? null
                            : () async {
                                final stage = p.stages.firstWhere(
                                  (s) => s.id == _view,
                                );
                                final name = await _name('阶段名称', stage.name);
                                if (name != null && mounted) {
                                  setState(() {
                                    _program = _withStages([
                                      for (final s in p.stages)
                                        s.id == stage.id
                                            ? ProgramStage(
                                                id: s.id,
                                                name: name,
                                                targets: s.targets,
                                              )
                                            : s,
                                    ]);
                                    _dirty = true;
                                  });
                                }
                              },
                        child: const Text('更名'),
                      ),
                      if (p.stages.length > 1)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () {
                                  final kept = p.stages
                                      .where((s) => s.id != _view)
                                      .toList();
                                  setState(() {
                                    _program = _withStages(
                                      kept,
                                      current: p.currentStageId == _view
                                          ? kept.first.id
                                          : null,
                                    );
                                    _view = kept.first.id;
                                    _dirty = true;
                                  });
                                },
                          child: const Text('移除此阶段'),
                        ),
                      if (_view != p.currentStageId)
                        FilledButton.tonal(
                          onPressed: _busy ? null : () => _save(current: _view),
                          child: const Text('将此阶段设为当前'),
                        ),
                      if (p.stages.indexOf(p.current) < p.stages.length - 1)
                        OutlinedButton(
                          onPressed: _busy
                              ? null
                              : () => _save(
                                  current: p
                                      .stages[p.stages.indexOf(p.current) + 1]
                                      .id,
                                ),
                          child: const Text('进入下一阶段'),
                        ),
                    ],
                  ),
                  if (p.stages.indexOf(p.current) < p.stages.length - 1)
                    ExpansionTile(
                      title: Text(
                        '下一阶段：${p.stages[p.stages.indexOf(p.current) + 1].name} · 查看变化',
                      ),
                      children: [
                        for (final day in plan.days)
                          for (var i = 0; i < day.occurrenceIds.length; i++)
                            if (p.current.targets[day.occurrenceIds[i]]
                                    ?.map((t) => t.label)
                                    .join('\n') !=
                                p
                                    .stages[p.stages.indexOf(p.current) + 1]
                                    .targets[day.occurrenceIds[i]]
                                    ?.map((t) => t.label)
                                    .join('\n'))
                              ListTile(
                                title: Text(
                                  '${day.name} · ${_names[day.exerciseIds[i]] ?? '动作'}',
                                ),
                                subtitle: Text(
                                  (p
                                              .stages[p.stages.indexOf(
                                                    p.current,
                                                  ) +
                                                  1]
                                              .targets[day.occurrenceIds[i]] ??
                                          [])
                                      .map((t) => t.label)
                                      .join('\n'),
                                ),
                              ),
                        const Text('没有列出的动作保持原目标。阶段切换在下次开训生效。'),
                      ],
                    ),
                  for (final day in plan.days)
                    if (day.kind == TrainingDayKind.training) ...[
                      Padding(
                        padding: const EdgeInsets.only(top: 20, bottom: 8),
                        child: Text(
                          day.name,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      for (var i = 0; i < day.exerciseIds.length; i++)
                        Builder(
                          builder: (ctx) {
                            final occurrence = day.occurrenceIds[i];
                            final stage = p.stages.firstWhere(
                              (s) => s.id == _view,
                            );
                            final targets =
                                stage.targets[occurrence] ??
                                const <SetTarget>[];
                            final name = _names[day.exerciseIds[i]] ?? '未知动作';
                            return Card(
                              child: ListTile(
                                title: Text(name),
                                subtitle: Text(
                                  targets.isEmpty
                                      ? '尚未设置目标'
                                      : targets.map((t) => t.label).join('\n'),
                                ),
                                trailing: const Icon(Icons.edit_outlined),
                                onTap: _busy
                                    ? null
                                    : () async {
                                        final edited = await showTargetEditor(
                                          context,
                                          name,
                                          targets,
                                        );
                                        if (edited != null && mounted) {
                                          setState(() {
                                            _program = _withStages([
                                              for (final s in p.stages)
                                                s.id == _view
                                                    ? ProgramStage(
                                                        id: s.id,
                                                        name: s.name,
                                                        targets: {
                                                          ...s.targets,
                                                          occurrence: edited,
                                                        },
                                                      )
                                                    : s,
                                            ]);
                                            _dirty = true;
                                          });
                                        }
                                      },
                              ),
                            );
                          },
                        ),
                    ],
                  if (p.sourceTitle.isNotEmpty)
                    ExpansionTile(
                      title: const Text('来源与整理说明'),
                      children: [
                        SelectableText(p.sourceTitle),
                        SelectableText(p.sourceUrl),
                        Text(p.notes),
                      ],
                    ),
                ],
              ),
      ),
    );
  }
}
