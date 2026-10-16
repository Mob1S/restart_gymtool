import 'package:flutter/material.dart';

import '../../domain/workout_edit.dart';
import '../../state/active_session_controller.dart';
import 'exercise_picker.dart';

Future<void> showReplaceExerciseSheet(
  BuildContext context,
  ActiveSessionController controller,
) async {
  final flush = await controller.flushPendingWeight();
  if (!context.mounted ||
      (flush != WorkoutWriteResult.saved &&
          flush != WorkoutWriteResult.unchanged)) {
    return;
  }
  final target = await showExercisePicker(context);
  if (target == null ||
      !context.mounted ||
      target.id == controller.currentExercise?.sessionExercise.exerciseId) {
    return;
  }
  try {
    final preview = await controller.previewReplacement(target.id);
    if (preview == null || !context.mounted) return;
    final reselect = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) =>
          _ReplaceSheet(controller: controller, preview: preview),
    );
    if (reselect == true && context.mounted) {
      await showReplaceExerciseSheet(context, controller);
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

class _ReplaceSheet extends StatefulWidget {
  final ActiveSessionController controller;
  final ExerciseReplacementPreview preview;
  const _ReplaceSheet({required this.controller, required this.preview});
  @override
  State<_ReplaceSheet> createState() => _ReplaceSheetState();
}

class _ReplaceSheetState extends State<_ReplaceSheet> {
  bool _busy = false, _stale = false;
  String? _error;
  Future<void> _save() async {
    setState(() => _busy = true);
    final result = await widget.controller.replaceExercise(widget.preview);
    if (!mounted) return;
    if (result == WorkoutWriteResult.saved ||
        result == WorkoutWriteResult.savedNeedsReload) {
      Navigator.pop(context);
      return;
    }
    setState(() {
      _busy = false;
      _stale = result == WorkoutWriteResult.conflict;
      _error = widget.controller.writeMessage ?? '替换失败，请重试';
    });
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.preview;
    return PopScope(
      canPop: !_busy,
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('替换当前动作', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 16),
              Text(
                p.completedSets == 0
                    ? '本次将 ${p.sourceName} 换为 ${p.targetName}，原计划保持不变。'
                    : '${p.sourceName}已记 ${p.completedSets} 组会保留，后续改练${p.targetName}，原计划保持不变。',
              ),
              const Text('仅影响本次训练'),
              if (_error != null) Text(_error!),
              const SizedBox(height: 16),
              Wrap(
                spacing: 16,
                children: [
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.pop(context),
                    child: const Text('取消'),
                  ),
                  if (_stale)
                    TextButton(
                      onPressed: () {
                        final parent = Navigator.of(context);
                        parent.pop(true);
                      },
                      child: const Text('重新选择'),
                    )
                  else
                    FilledButton(
                      onPressed: _busy ? null : _save,
                      child: Text(_busy ? '替换中…' : '替换为 ${p.targetName}'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
