import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/workout_edit.dart';
import '../../state/active_session_controller.dart';
import 'number_stepper.dart';

Future<void> showEditSetSheet(
  BuildContext context,
  ActiveSessionController controller,
  CompletedSetEdit edit,
  String name,
  int number,
  double step,
) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (context) => _EditSetSheet(
    controller: controller,
    edit: edit,
    name: name,
    number: number,
    step: step,
  ),
);

class _EditSetSheet extends StatefulWidget {
  final ActiveSessionController controller;
  final CompletedSetEdit edit;
  final String name;
  final int number;
  final double step;
  const _EditSetSheet({
    required this.controller,
    required this.edit,
    required this.name,
    required this.number,
    required this.step,
  });
  @override
  State<_EditSetSheet> createState() => _EditSetSheetState();
}

class _EditSetSheetState extends State<_EditSetSheet> {
  late final _weight = TextEditingController(
    text: widget.edit.original.weight.toString(),
  );
  late final _reps = TextEditingController(
    text: '${widget.edit.original.reps}',
  );
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _weight.dispose();
    _reps.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final weight = double.tryParse(_weight.text);
    final reps = int.tryParse(_reps.text);
    if (weight == null ||
        !weight.isFinite ||
        weight < 0 ||
        reps == null ||
        reps < 0) {
      setState(() => _error = '请输入非负重量和整数次数');
      return;
    }
    setState(() => _saving = true);
    final result = await widget.controller.editCompletedSet(
      widget.edit,
      weight,
      reps,
    );
    if (!mounted) return;
    if (result == WorkoutWriteResult.saved ||
        result == WorkoutWriteResult.savedNeedsReload) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _saving = false;
      _error = widget.controller.writeMessage ?? '暂时无法保存，请重试';
    });
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_saving,
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        20,
        20,
        MediaQuery.viewInsetsOf(context).bottom + 20,
      ),
      child: SingleChildScrollView(
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '修改第 ${widget.number} 组',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(widget.name),
              const SizedBox(height: 16),
              Semantics(
                label: '重量 kg',
                child: TextField(
                  key: const ValueKey('edit-set-weight'),
                  controller: _weight,
                  onChanged: (_) => setState(() {}),
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: '重量 kg'),
                ),
              ),
              NumberStepper(
                value:
                    double.tryParse(_weight.text) ??
                    widget.edit.original.weight,
                step: widget.step,
                max: math.max(500, widget.edit.original.weight),
                onChanged: (v) {
                  if (!_saving) {
                    setState(() => _weight.text = v.toString());
                  }
                },
              ),
              Semantics(
                label: '实际次数',
                child: TextField(
                  key: const ValueKey('edit-set-reps'),
                  controller: _reps,
                  enabled: !_saving,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '实际次数'),
                ),
              ),
              if (_error != null) Text(_error!),
              const SizedBox(height: 16),
              Wrap(
                spacing: 16,
                children: [
                  TextButton(
                    onPressed: _saving ? null : () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    key: const ValueKey('save-set-edit'),
                    onPressed: _saving ? null : _save,
                    child: Text(_saving ? '保存中…' : '保存'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
