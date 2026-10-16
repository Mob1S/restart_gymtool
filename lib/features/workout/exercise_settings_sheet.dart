import 'package:flutter/material.dart';

import '../../domain/exercise_preferences.dart';
import '../../domain/format.dart';
import '../../domain/workout_edit.dart';
import '../../state/exercise_preferences_controller.dart';

Future<void> showExerciseSettingsSheet(
  BuildContext context,
  ExercisePreferencesController controller,
  String id,
  String name,
) async {
  await controller.load([id]);
  if (!context.mounted) return;
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _SettingsSheet(
      controller: controller,
      preference: controller.preferenceFor(id),
      name: name,
    ),
  );
}

class _SettingsSheet extends StatefulWidget {
  final ExercisePreferencesController controller;
  final ExercisePreference preference;
  final String name;
  const _SettingsSheet({
    required this.controller,
    required this.preference,
    required this.name,
  });
  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late int _step = widget.preference.weightStepMilli;
  late final _note = TextEditingController(
    text: widget.preference.equipmentNote,
  );
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final result = await widget.controller.save(
      widget.preference.exerciseId,
      expectedToken: widget.preference.token,
      weightStepMilli: _step,
      equipmentNote: _note.text,
    );
    if (!mounted) return;
    if (result == WorkoutWriteResult.saved) {
      Navigator.pop(context);
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
              const Text('调重幅度'),
              Wrap(
                spacing: 8,
                children: [
                  for (final step in weightStepOptions)
                    ChoiceChip(
                      label: Text('${formatWeightKg(step / 1000)} kg'),
                      selected: step == _step,
                      onSelected: _busy
                          ? null
                          : (_) => setState(() => _step = step),
                    ),
                ],
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
