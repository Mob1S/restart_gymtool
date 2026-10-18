import 'package:flutter/material.dart';

import '../../domain/training_prescription.dart';

Future<List<SetTarget>?> showTargetEditor(
  BuildContext context,
  String name,
  List<SetTarget> targets,
) => showModalBottomSheet<List<SetTarget>>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _TargetList(name: name, targets: targets),
);

class _TargetList extends StatefulWidget {
  final String name;
  final List<SetTarget> targets;
  const _TargetList({required this.name, required this.targets});
  @override
  State<_TargetList> createState() => _TargetListState();
}

class _TargetListState extends State<_TargetList> {
  late final _targets = [...widget.targets];
  Future<void> _edit(int? index) async {
    final initial = index == null
        ? (_targets.isEmpty
              ? SetTarget(repsMin: 8, repsMax: 12)
              : _targets.last)
        : _targets[index];
    final value = await showDialog<SetTarget>(
      context: context,
      builder: (_) => _TargetDialog(initial: initial),
    );
    if (value != null && mounted) {
      setState(() {
        if (index == null) {
          _targets.add(value);
        } else {
          _targets[index] = value;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MediaQuery.sizeOf(context).height * .88,
    child: Scaffold(
      appBar: AppBar(
        title: Text(widget.name),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _targets),
            child: const Text('应用组次'),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('分别设置每组要求。实际完成的重量、次数和用力程度会单独记录。'),
          for (var i = 0; i < _targets.length; i++)
            Card(
              child: ListTile(
                title: Text('第 ${i + 1} 组 · ${_targets[i].label}'),
                subtitle: _targets[i].note.isEmpty
                    ? null
                    : Text(_targets[i].note),
                onTap: () => _edit(i),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: '上移这组',
                      onPressed: i == 0
                          ? null
                          : () => setState(() {
                              final t = _targets.removeAt(i);
                              _targets.insert(i - 1, t);
                            }),
                      icon: const Icon(Icons.arrow_upward),
                    ),
                    IconButton(
                      tooltip: '删除这组',
                      onPressed: () => setState(() => _targets.removeAt(i)),
                      icon: const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
              ),
            ),
          OutlinedButton.icon(
            onPressed: () => _edit(null),
            icon: const Icon(Icons.add),
            label: const Text('添加一组目标'),
          ),
        ],
      ),
    ),
  );
}

class _TargetDialog extends StatefulWidget {
  final SetTarget initial;
  const _TargetDialog({required this.initial});
  @override
  State<_TargetDialog> createState() => _TargetDialogState();
}

class _TargetDialogState extends State<_TargetDialog> {
  late final Map<String, TextEditingController> _fields = {
    '最少次数': TextEditingController(text: '${widget.initial.repsMin}'),
    '最多次数': TextEditingController(text: '${widget.initial.repsMax}'),
    '负荷数值': TextEditingController(
      text: widget.initial.loadValue?.toString() ?? '',
    ),
    '用力程度': TextEditingController(
      text: widget.initial.effort?.value.toString() ?? '8',
    ),
    '用力上限（可留空）': TextEditingController(
      text: widget.initial.effort?.maxValue?.toString() ?? '',
    ),
    '追加段次数（例如 5 或 10+5）': TextEditingController(
      text: widget.initial.extraReps.join('+'),
    ),
    '组内休息秒数': TextEditingController(
      text:
          '${widget.initial.pauseSeconds == 0 ? 5 : widget.initial.pauseSeconds}',
    ),
    '说明': TextEditingController(text: widget.initial.note),
  };
  late String _role = widget.initial.role,
      _load = widget.initial.loadKind,
      _unit = widget.initial.fixedUnit,
      _effort = widget.initial.effort?.kind ?? 'none';
  late bool _optional = widget.initial.optional;
  String? _error;
  @override
  void dispose() {
    for (final c in _fields.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    try {
      final extras = _fields['追加段次数（例如 5 或 10+5）']!.text.trim();
      final t = SetTarget(
        repsMin: int.parse(_fields['最少次数']!.text),
        repsMax: int.parse(_fields['最多次数']!.text),
        role: _role,
        loadKind: _load,
        loadValue: _load == 'none' ? null : double.parse(_fields['负荷数值']!.text),
        fixedUnit: _unit,
        effort: _effort == 'none'
            ? null
            : Effort(
                _effort,
                double.parse(_fields['用力程度']!.text),
                maxValue: _fields['用力上限（可留空）']!.text.trim().isEmpty
                    ? null
                    : double.parse(_fields['用力上限（可留空）']!.text),
              ),
        extraReps: extras.isEmpty
            ? []
            : extras.split(RegExp(r'[+，,\s]+')).map(int.parse).toList(),
        pauseSeconds: extras.isEmpty ? 0 : int.parse(_fields['组内休息秒数']!.text),
        optional: _optional,
        note: _fields['说明']!.text.trim(),
      );
      t.validate();
      Navigator.pop(context, t);
    } catch (e) {
      setState(
        () => _error = '请检查次数、范围和负荷：${e is FormatException ? e.message : e}',
      );
    }
  }

  Widget _dropdown(
    String label,
    String value,
    Map<String, String> choices,
    ValueChanged<String> changed,
  ) => DropdownButtonFormField<String>(
    initialValue: value,
    decoration: InputDecoration(labelText: label),
    items: [
      for (final e in choices.entries)
        DropdownMenuItem(value: e.key, child: Text(e.value)),
    ],
    onChanged: (v) {
      if (v != null) setState(() => changed(v));
    },
  );
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('设置一组目标'),
    content: SizedBox(
      width: 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _dropdown('组类别', _role, {
              'work': '正式组',
              'warmup': '热身组',
            }, (v) => _role = v),
            for (final name in ['最少次数', '最多次数'])
              TextField(
                controller: _fields[name],
                keyboardType: TextInputType.number,
                decoration: InputDecoration(labelText: name),
              ),
            _dropdown('负荷要求', _load, {
              'none': '未指定',
              'rm': 'RM',
              'percent': '%1RM',
              'fixed': '固定重量',
            }, (v) => _load = v),
            if (_load != 'none')
              TextField(
                controller: _fields['负荷数值'],
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: '负荷数值'),
              ),
            if (_load == 'fixed')
              _dropdown('器械单位', _unit, {
                'kg': 'kg',
                'lb': 'lb',
              }, (v) => _unit = v),
            _dropdown('目标用力程度', _effort, {
              'none': '未指定',
              'rpe': 'RPE',
              'rir': 'RIR',
            }, (v) => _effort = v),
            if (_effort != 'none')
              for (final name in ['用力程度', '用力上限（可留空）'])
                TextField(
                  controller: _fields[name],
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(labelText: name),
                ),
            for (final name in ['追加段次数（例如 5 或 10+5）', '组内休息秒数', '说明'])
              TextField(
                controller: _fields[name],
                decoration: InputDecoration(labelText: name),
              ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _optional,
              onChanged: (v) => setState(() => _optional = v ?? false),
              title: const Text('这组可选'),
            ),
            if (_error != null)
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _save, child: const Text('保存目标')),
    ],
  );
}
