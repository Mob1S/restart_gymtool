import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/workout_edit.dart';
import '../../domain/weight_value.dart';
import '../../domain/set_detail.dart';
import '../../domain/training_prescription.dart';
import '../../data/repositories/executor_access.dart';
import '../../data/repositories/workout_edit_repo.dart';
import '../../state/data_revision.dart';

import 'package:provider/provider.dart';

import 'effort_input.dart';
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

Future<void> showHistoricalSetEditor(
  BuildContext context,
  String sessionId,
  String setId,
  String name,
  int number,
) async {
  final exec = context.read<SqlExecutor>();
  final revision = context.read<DataRevision?>();
  try {
    final edit = await inspectHistoricalSet(exec, sessionId, setId);
    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _EditSetSheet(
        edit: edit,
        name: name,
        number: number,
        step: edit.original.equipmentWeight.unit == WeightUnit.kg ? 2.5 : 5,
        historicalSave: (reading, reps, detail) async {
          await updateHistoricalSet(exec, edit, reading, reps, detail);
          revision?.changed();
        },
      ),
    );
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

class _EditSetSheet extends StatefulWidget {
  final ActiveSessionController? controller;
  final Future<void> Function(EquipmentWeight, int, SetDetail?)? historicalSave;
  final CompletedSetEdit edit;
  final String name;
  final int number;
  final double step;
  const _EditSetSheet({
    this.controller,
    this.historicalSave,
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
    text: widget.edit.original.equipmentWeight.amount.text,
  );
  late final _reps = TextEditingController(
    text: '${widget.edit.original.reps}',
  );
  bool _saving = false;
  String? _error;
  late final _continuationWeights = [
    for (final s
        in widget.edit.original.detail?.continuations ?? <RecordedSegment>[])
      TextEditingController(text: s.reading.amount.text),
  ];
  late final _continuationReps = [
    for (final s
        in widget.edit.original.detail?.continuations ?? <RecordedSegment>[])
      TextEditingController(text: '${s.reps}'),
  ];
  late final _continuationPauses = [
    for (final s
        in widget.edit.original.detail?.continuations ?? <RecordedSegment>[])
      TextEditingController(text: '${s.pauseSeconds}'),
  ];
  late final _continuationEfforts = [
    for (final s
        in widget.edit.original.detail?.continuations ?? <RecordedSegment>[])
      s.effort,
  ];
  late Effort? _effort = widget.edit.original.detail?.effort;
  late String _role = widget.edit.original.detail?.role ?? 'unknown';
  @override
  void dispose() {
    _weight.dispose();
    _reps.dispose();
    for (final c in [
      ..._continuationWeights,
      ..._continuationReps,
      ..._continuationPauses,
    ]) {
      c.dispose();
    }
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
    EquipmentWeight reading;
    try {
      reading = EquipmentWeight(
        DecimalReading.parse(_weight.text),
        widget.edit.original.equipmentWeight.unit,
      );
    } on FormatException {
      setState(() {
        _saving = false;
        _error = '请输入有效重量';
      });
      return;
    }
    WorkoutWriteResult result;
    try {
      final original = widget.edit.original.detail;
      final detail = SetDetail(
        role: _role,
        effort: _effort,
        target: original?.target,
        targetIndex: original?.targetIndex,
        firstCompletedAt: original?.firstCompletedAt,
        endedEarly: original?.endedEarly ?? false,
        reference: original?.reference,
        continuations: [
          for (var i = 0; i < _continuationWeights.length; i++)
            RecordedSegment(
              reading: EquipmentWeight(
                DecimalReading.parse(_continuationWeights[i].text),
                original!.continuations[i].reading.unit,
              ),
              reps: int.parse(_continuationReps[i].text),
              pauseSeconds: int.parse(_continuationPauses[i].text),
              completedAt: original.continuations[i].completedAt,
              effort: _continuationEfforts[i],
            ),
        ],
      );
      SetDetail.decode(detail.encode());
      if (widget.historicalSave != null) {
        await widget.historicalSave!(reading, reps, detail);
        result = WorkoutWriteResult.saved;
      } else {
        result = await widget.controller!.editCompletedSet(
          widget.edit,
          reading.kilograms,
          reps,
          reading: reading,
          detail: detail,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '$e';
        });
      }
      return;
    }
    if (!mounted) return;
    if (result == WorkoutWriteResult.saved ||
        result == WorkoutWriteResult.savedNeedsReload) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _saving = false;
      _error = widget.controller?.writeMessage ?? '暂时无法保存，请重试';
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
                label: '重量 ${widget.edit.original.equipmentWeight.unit.name}',
                child: TextField(
                  key: const ValueKey('edit-set-weight'),
                  controller: _weight,
                  onChanged: (_) => setState(() {}),
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText:
                        '重量 ${widget.edit.original.equipmentWeight.unit.name}',
                  ),
                ),
              ),
              NumberStepper(
                value:
                    double.tryParse(_weight.text) ??
                    widget.edit.original.equipmentWeight.amount.asDouble,
                step: widget.step,
                max: math.max(
                  500,
                  widget.edit.original.equipmentWeight.amount.asDouble,
                ),
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
              EffortInput(
                value: _effort,
                enabled: !_saving,
                onChanged: (v) => setState(() => _effort = v),
              ),
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: const InputDecoration(labelText: '实际组类型'),
                items: const [
                  DropdownMenuItem(value: 'unknown', child: Text('未分类')),
                  DropdownMenuItem(value: 'warmup', child: Text('热身组')),
                  DropdownMenuItem(value: 'work', child: Text('正式组')),
                ],
                onChanged: _saving ? null : (v) => setState(() => _role = v!),
              ),
              if (widget.edit.original.detail?.target != null)
                Text('计划目标：${widget.edit.original.detail!.target!.label}'),
              for (var i = 0; i < _continuationWeights.length; i++) ...[
                const SizedBox(height: 16),
                Text('第 ${i + 2} 段实际记录'),
                TextField(
                  controller: _continuationWeights[i],
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText:
                        '重量 ${widget.edit.original.detail!.continuations[i].reading.unit.name}',
                  ),
                ),
                TextField(
                  controller: _continuationReps[i],
                  enabled: !_saving,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '本段实际次数'),
                ),
                TextField(
                  controller: _continuationPauses[i],
                  enabled: !_saving,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '实际停顿秒数'),
                ),
                EffortInput(
                  value: _continuationEfforts[i],
                  segment: true,
                  enabled: !_saving,
                  onChanged: (v) => setState(() => _continuationEfforts[i] = v),
                ),
              ],
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
