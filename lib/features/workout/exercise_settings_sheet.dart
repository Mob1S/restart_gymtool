import 'package:flutter/material.dart';

import '../../domain/exercise_preferences.dart';
import '../../domain/weight_value.dart';
import '../../domain/workout_edit.dart';
import '../../state/exercise_preferences_controller.dart';

Future<WorkoutWriteResult?> showExerciseSettingsSheet(
  BuildContext context,
  ExercisePreferencesController controller,
  String id,
  String name, {
  String? sessionId,
  String? pendingSetId,
  EquipmentWeight? pendingReading,
}) async {
  await controller.load([id]);
  if (!context.mounted) return null;
  return showModalBottomSheet<WorkoutWriteResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _SettingsSheet(
      controller: controller,
      preference: controller.preferenceFor(id),
      name: name,
      sessionId: sessionId,
      pendingSetId: pendingSetId,
      pendingReading: pendingReading,
    ),
  );
}

class _SettingsSheet extends StatefulWidget {
  final ExercisePreferencesController controller;
  final ExercisePreference preference;
  final String name;
  final String? sessionId, pendingSetId;
  final EquipmentWeight? pendingReading;
  const _SettingsSheet({
    required this.controller,
    required this.preference,
    required this.name,
    this.sessionId,
    this.pendingSetId,
    this.pendingReading,
  });
  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late WeightUnit _unit =
      widget.pendingReading?.unit ?? widget.preference.weightUnit;
  late DecimalReading _kgStep = widget.preference.kgStep;
  late DecimalReading _lbStep = widget.preference.lbStep;
  late bool _showKg = widget.preference.showKgEquivalent;
  late bool _favorite = widget.preference.isFavorite;
  final _custom = TextEditingController();
  bool _customSelected = false;
  late final _note = TextEditingController(
    text: widget.preference.equipmentNote,
  );
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _note.dispose();
    _custom.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_customSelected) {
      try {
        final step = DecimalReading.parse(_custom.text);
        if (!step.asDouble.isFinite || step.asDouble <= 0) {
          throw const FormatException('自定义幅度必须为正的有限数');
        }
        if (_unit == WeightUnit.kg) {
          _kgStep = step;
        } else {
          _lbStep = step;
        }
      } on FormatException {
        setState(() => _error = '自定义幅度必须为正的有限数');
        return;
      }
    }
    setState(() => _busy = true);
    final result = await widget.controller.save(
      widget.preference.exerciseId,
      expectedToken: widget.preference.token,
      weightUnit: _unit,
      kgStep: _kgStep,
      lbStep: _lbStep,
      showKgEquivalent: _showKg,
      isFavorite: _favorite,
      sessionId: widget.sessionId,
      pendingSetId: widget.pendingSetId,
      pendingReading: widget.pendingReading?.withUnit(_unit),
      equipmentNote: _note.text,
    );
    if (!mounted) return;
    if (result == WorkoutWriteResult.saved) {
      Navigator.pop(context, result);
      return;
    }
    setState(() => _busy = false);
    setState(() => _error = widget.controller.message ?? '偏好未保存，请重试');
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('动作设置', style: Theme.of(context).textTheme.titleLarge),
              Text(widget.name),
              const SizedBox(height: 16),
              const Text('器械单位'),
              Wrap(
                spacing: 8,
                children: [
                  for (final unit in WeightUnit.values)
                    ChoiceChip(
                      label: Text(unit.name),
                      selected: unit == _unit,
                      onSelected: _busy
                          ? null
                          : (_) => setState(() {
                              _unit = unit;
                              _customSelected = false;
                              _custom.clear();
                              _error = null;
                            }),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              const Text('调重幅度'),
              Wrap(
                spacing: 8,
                children: [
                  for (final step
                      in (_unit == WeightUnit.kg
                          ? ['0.5', '1', '1.25', '2.5', '5', '10']
                          : ['1', '2.5', '5', '10', '20']))
                    ChoiceChip(
                      label: Text('$step ${_unit.name}'),
                      selected:
                          !_customSelected &&
                          step ==
                              (_unit == WeightUnit.kg
                                  ? _kgStep.text
                                  : _lbStep.text),
                      onSelected: _busy
                          ? null
                          : (_) => setState(() {
                              if (_unit == WeightUnit.kg) {
                                _kgStep = DecimalReading.parse(step);
                              } else {
                                _lbStep = DecimalReading.parse(step);
                              }
                              _customSelected = false;
                              _error = null;
                            }),
                    ),
                ],
              ),
              TextField(
                key: const ValueKey('custom-weight-step'),
                controller: _custom,
                enabled: !_busy,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: '自定义幅度（${_unit.name}）',
                  helperText:
                      '当前 ${(_unit == WeightUnit.kg ? _kgStep : _lbStep).text} ${_unit.name}',
                ),
                onChanged: (_) => setState(() {
                  _customSelected = true;
                  _error = null;
                  try {
                    final step = DecimalReading.parse(_custom.text);
                    if (step.asDouble > 0 && step.asDouble.isFinite) {
                      if (_unit == WeightUnit.kg) {
                        _kgStep = step;
                      } else {
                        _lbStep = step;
                      }
                    }
                  } on FormatException {
                    // Invalid text stays local and is reported on confirm.
                  }
                }),
              ),
              if (_unit == WeightUnit.lb)
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('同时显示换算后的 kg'),
                  value: _showKg,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _showKg = value!),
                ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('收藏动作'),
                value: _favorite,
                onChanged: _busy
                    ? null
                    : (value) => setState(() => _favorite = value!),
              ),
              const SizedBox(height: 16),
              Semantics(
                label: '器械备忘',
                child: TextField(
                  controller: _note,
                  enabled: !_busy,
                  minLines: 2,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    labelText: '器械备忘',
                    helperText: '最多 500 个字符；保留内部换行',
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Text('${_note.text.trim().runes.length} / 500'),
              if (_error != null) Text(_error!),
              Wrap(
                spacing: 16,
                children: [
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  FilledButton(
                    onPressed: _busy ? null : _save,
                    child: Text(_busy ? '保存中…' : '保存'),
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

class EquipmentNote extends StatelessWidget {
  final String note;
  const EquipmentNote({super.key, required this.note});
  @override
  Widget build(BuildContext context) => note.isEmpty
      ? const SizedBox.shrink()
      : TextButton(
          onPressed: () => showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('器械备忘'),
              scrollable: true,
              content: Text(note),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('关闭'),
                ),
              ],
            ),
          ),
          child: Text(
            note,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
        );
}
