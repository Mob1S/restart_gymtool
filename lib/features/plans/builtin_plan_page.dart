import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../data/builtin_programs.dart';
import '../../data/repositories/executor_access.dart';
import '../../data/repositories/exercise_catalog_repo.dart';
import '../../data/repositories/exercise_repo.dart';
import '../../data/repositories/builtin_program_repo.dart';
import '../../domain/types.dart';
import '../../state/data_revision.dart';
import '../workout/exercise_picker.dart';

class BuiltinPlanPage extends StatelessWidget {
  const BuiltinPlanPage({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('内置计划')),
    body: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('按你的时间和经验选择，导入后可编辑动作、组次、阶段及休息安排。'),
        for (final preset in builtinPrograms)
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(20),
              title: Text(preset.name),
              subtitle: Text(
                '${preset.days.where((d) => !d.rest).length} 个训练日 · ${preset.days.where((d) => d.rest).length} 个休息日 · ${preset.stages.length} 个阶段\n${preset.sourceTitle}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => _BuiltinPreview(preset: preset),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

class _BuiltinPreview extends StatefulWidget {
  final BuiltinProgram preset;
  const _BuiltinPreview({required this.preset});
  @override
  State<_BuiltinPreview> createState() => _BuiltinPreviewState();
}

class _BuiltinPreviewState extends State<_BuiltinPreview> {
  final Map<String, String> _overrides = {};
  final Set<String> _restore = {};
  Map<String, String> _bindings = {};
  List<Exercise>? _all;
  bool _busy = false;
  String? _error;
  int _stage = 0, _copies = 0;
  late final List<BuiltinDay> _cycle = [...widget.preset.days];
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final db = context.read<SqlExecutor>();
      await syncExerciseCatalog(db);
      final all = await listExercises(db, includeArchived: true);
      final bindings = await readCatalogBindings(db);
      final copies = await countBuiltinProgramCopies(db, widget.preset.key);
      if (mounted) {
        setState(() {
          _all = all;
          _bindings = bindings;
          _copies = copies;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      final plan = await importBuiltinProgram(
        context.read<SqlExecutor>(),
        widget.preset,
        overrides: _overrides,
        restoreArchivedIds: _restore,
        cycle: _cycle,
      );
      if (mounted) {
        context.read<DataRevision?>()?.changed();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('已添加「${plan.name}」，可在我的计划中编辑')));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.preset;
    final unique = {
      for (final d in p.days)
        for (final e in d.exercises) e.key: e,
    };
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(title: const Text('计划预览')),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(p.name, style: Theme.of(context).textTheme.headlineSmall),
            SelectableText(p.sourceTitle),
            Text(p.notes),
            TextButton(
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: p.sourceUrl)),
              child: const Text('复制来源链接'),
            ),
            if (_copies > 0) Text('已有 $_copies 个导入副本；再次导入会创建独立副本。'),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            if (_all == null)
              const LinearProgressIndicator()
            else ...[
              ExpansionTile(
                title: const Text('调整周期与休息'),
                subtitle: const Text('可调整顺序，在任意训练日后加入休息'),
                children: [
                  for (var i = 0; i < _cycle.length; i++)
                    ListTile(
                      title: Text('${i + 1}. ${_cycle[i].name}'),
                      subtitle: Wrap(
                        children: [
                          IconButton(
                            tooltip: '上移周期日',
                            onPressed: _busy || i == 0
                                ? null
                                : () => setState(() {
                                    final d = _cycle.removeAt(i);
                                    _cycle.insert(i - 1, d);
                                  }),
                            icon: const Icon(Icons.arrow_upward),
                          ),
                          IconButton(
                            tooltip: '下移周期日',
                            onPressed: _busy || i == _cycle.length - 1
                                ? null
                                : () => setState(() {
                                    final d = _cycle.removeAt(i);
                                    _cycle.insert(i + 1, d);
                                  }),
                            icon: const Icon(Icons.arrow_downward),
                          ),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => setState(
                                    () => _cycle.insert(
                                      i + 1,
                                      const BuiltinDay('休息', []),
                                    ),
                                  ),
                            child: const Text('后加休息'),
                          ),
                          if (_cycle[i].rest)
                            IconButton(
                              tooltip: '移除此休息日',
                              onPressed: _busy
                                  ? null
                                  : () => setState(() => _cycle.removeAt(i)),
                              icon: const Icon(Icons.delete_outline),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
              ExpansionTile(
                title: const Text('动作匹配与替代'),
                children: [
                  for (final entry in unique.entries)
                    Builder(
                      builder: (ctx) {
                        final id =
                            _overrides[entry.key] ?? _bindings[entry.key];
                        final e = _all!.where((e) => e.id == id).firstOrNull;
                        return Column(
                          children: [
                            ListTile(
                              title: Text(entry.value.name),
                              subtitle: Text(
                                e == null
                                    ? '请选择对应动作'
                                    : '${e.name} · ${e.equipment ?? ''}${e.isArchived ? ' · 已归档' : ''}',
                              ),
                              trailing: TextButton(
                                onPressed: _busy
                                    ? null
                                    : () async {
                                        final chosen = await showExercisePicker(
                                          context,
                                        );
                                        if (chosen != null && mounted) {
                                          setState(
                                            () => _overrides[entry.key] =
                                                chosen.id,
                                          );
                                        }
                                      },
                                child: const Text('选择／替换'),
                              ),
                            ),
                            if (e?.isArchived == true)
                              CheckboxListTile(
                                title: Text('导入时恢复「${e!.name}」'),
                                value: _restore.contains(e.id),
                                onChanged: _busy
                                    ? null
                                    : (v) => setState(() {
                                        if (v == true) {
                                          _restore.add(e.id);
                                        } else {
                                          _restore.remove(e.id);
                                        }
                                      }),
                              ),
                          ],
                        );
                      },
                    ),
                ],
              ),
              DropdownButtonFormField<int>(
                initialValue: _stage,
                decoration: const InputDecoration(labelText: '预览阶段（导入从首阶段开始）'),
                items: [
                  for (var i = 0; i < p.stages.length; i++)
                    DropdownMenuItem(value: i, child: Text(p.stages[i])),
                ],
                onChanged: (v) => setState(() => _stage = v ?? 0),
              ),
              for (var i = 0; i < _cycle.length; i++)
                Card(
                  child: ExpansionTile(
                    initiallyExpanded: i == 0,
                    title: Text('${i + 1}. ${_cycle[i].name}'),
                    subtitle: Text(
                      _cycle[i].rest
                          ? '自然日休息'
                          : '${_cycle[i].exercises.length} 个动作',
                    ),
                    children: [
                      for (final e in _cycle[i].exercises)
                        ListTile(
                          title: Text('${e.name} · ${e.equipment}'),
                          subtitle: Text(
                            e.at(_stage).map((t) => t.label).join('\n'),
                          ),
                        ),
                    ],
                  ),
                ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _busy ? null : _import,
                icon: const Icon(Icons.playlist_add),
                label: Text(
                  _busy
                      ? '正在导入'
                      : _copies > 0
                      ? '再导入一个副本'
                      : '导入为我的计划',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
