import 'package:flutter/material.dart';

import '../../domain/import_records.dart';
import '../../domain/workout_csv.dart';
import '../../state/import_controller.dart';
import '../workout/exercise_picker.dart';

class _SetDraft {
  final weight = TextEditingController(text: '20');
  final reps = TextEditingController(text: '8');
  void dispose() {
    weight.dispose();
    reps.dispose();
  }
}

class _ExerciseDraft {
  final String name;
  final String? id;
  final List<_SetDraft> sets = [_SetDraft()];
  _ExerciseDraft(this.name, this.id);
  void dispose() {
    for (final s in sets) {
      s.dispose();
    }
  }
}

class ManualWorkoutForm extends StatefulWidget {
  final ImportController controller;
  const ManualWorkoutForm({super.key, required this.controller});
  @override
  State<ManualWorkoutForm> createState() => _ManualWorkoutFormState();
}

class _ManualWorkoutFormState extends State<ManualWorkoutForm> {
  final _name = TextEditingController();
  final _start = TextEditingController();
  final _end = TextEditingController();
  final _newName = TextEditingController();
  final List<_ExerciseDraft> _exercises = [];
  bool _dirty = false;
  String? _error;
  @override
  void dispose() {
    _name.dispose();
    _start.dispose();
    _end.dispose();
    _newName.dispose();
    for (final e in _exercises) {
      e.dispose();
    }
    super.dispose();
  }

  Future<void> _preview() async {
    try {
      if (!RegExp(r'\d{1,2}:\d{2}').hasMatch(_start.text) ||
          !RegExp(r'\d{1,2}:\d{2}').hasMatch(_end.text)) {
        throw const ImportValidationException('请填写实际开始和结束时间，包含小时与分钟');
      }
      final grouped = <String, (String, List<ImportedSet>)>{};
      final matches = <String, String?>{};
      for (final e in _exercises) {
        final key = normalizeExerciseName(e.name);
        if (matches.containsKey(key) && matches[key] != e.id) {
          throw const ImportValidationException('同名动作选择了不同目标，请分别补记');
        }
        matches[key] = e.id;
        final sets = grouped
            .putIfAbsent(key, () => (e.name, <ImportedSet>[]))
            .$2;
        for (final s in e.sets) {
          final w = double.tryParse(s.weight.text.trim());
          final r = int.tryParse(s.reps.text.trim());
          if (w == null || r == null) {
            throw const ImportValidationException('请输入有效重量和整数次数');
          }
          sets.add(ImportedSet(weight: w, reps: r));
        }
      }
      final workout = ImportedWorkout(
        sourceRow: 1,
        startedAt: parseImportDate(_start.text),
        finishedAt: parseImportDate(_end.text),
        name: _name.text.trim().isEmpty ? null : _name.text.trim(),
        note: '来源：手动补记',
        exercises: [
          for (final e in grouped.values)
            ImportedExercise(name: e.$1, sets: e.$2),
        ],
      );
      await widget.controller.previewManual([workout], matches: matches);
    } on ImportValidationException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_dirty,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop || widget.controller.busy) return;
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('丢弃未保存的补记？'),
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
        setState(() => _dirty = false);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) Navigator.pop(context);
        });
      }
    },
    child: ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (_error != null) Text(_error!),
        TextField(
          controller: _name,
          decoration: const InputDecoration(labelText: '训练名称（可空）'),
          onChanged: (_) => setState(() => _dirty = true),
        ),
        TextField(
          controller: _start,
          decoration: const InputDecoration(
            labelText: '开始时间',
            hintText: '2026-10-16 19:30',
          ),
          onChanged: (_) => setState(() => _dirty = true),
        ),
        TextField(
          controller: _end,
          decoration: const InputDecoration(
            labelText: '结束时间',
            hintText: '2026-10-16 20:30',
          ),
          onChanged: (_) => setState(() => _dirty = true),
        ),
        for (var i = 0; i < _exercises.length; i++)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(_exercises[i].name),
                    trailing: IconButton(
                      tooltip: '移除草稿动作',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() {
                        _exercises.removeAt(i).dispose();
                        _dirty = true;
                      }),
                    ),
                  ),
                  for (var j = 0; j < _exercises[i].sets.length; j++)
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _exercises[i].sets[j].weight,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: const InputDecoration(
                              labelText: '重量 kg',
                            ),
                            onChanged: (_) => setState(() => _dirty = true),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _exercises[i].sets[j].reps,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: '次数'),
                            onChanged: (_) => setState(() => _dirty = true),
                          ),
                        ),
                        IconButton(
                          tooltip: '删除草稿组',
                          onPressed: () => setState(() {
                            _exercises[i].sets.removeAt(j).dispose();
                            _dirty = true;
                          }),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                      ],
                    ),
                  TextButton(
                    onPressed: () => setState(() {
                      _exercises[i].sets.add(_SetDraft());
                      _dirty = true;
                    }),
                    child: const Text('添加一组'),
                  ),
                ],
              ),
            ),
          ),
        OutlinedButton(
          onPressed: widget.controller.busy
              ? null
              : () async {
                  final e = await showExercisePicker(context);
                  if (e != null && mounted) {
                    setState(() {
                      _exercises.add(_ExerciseDraft(e.name, e.id));
                      _dirty = true;
                    });
                  }
                },
          child: const Text('选择已有动作'),
        ),
        TextField(
          controller: _newName,
          onChanged: (_) => setState(() => _dirty = true),
          decoration: const InputDecoration(labelText: '或输入新动作名称'),
        ),
        TextButton(
          onPressed: () => setState(() {
            if (_newName.text.trim().isNotEmpty) {
              _exercises.add(_ExerciseDraft(_newName.text.trim(), null));
              _newName.clear();
              _dirty = true;
            }
          }),
          child: const Text('加入新动作草稿'),
        ),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: widget.controller.busy ? null : _preview,
          child: const Text('预览补记'),
        ),
      ],
    ),
  );
}
