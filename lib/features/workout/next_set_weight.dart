import 'package:flutter/material.dart';

import '../../domain/types.dart';
import '../../domain/workout_edit.dart';
import '../../domain/weight_value.dart';
import '../../state/active_session_controller.dart';
import 'workout_value_input.dart';

class NextSetWeight extends StatefulWidget {
  final ActiveSessionController controller;
  final SetEntry pending;
  final double step;
  final DecimalReading? readingStep;
  final bool showKgEquivalent;
  final ValueChanged<bool>? onGestureActiveChanged;
  const NextSetWeight({
    super.key,
    required this.controller,
    required this.pending,
    this.step = 2.5,
    this.readingStep,
    this.showKgEquivalent = false,
    this.onGestureActiveChanged,
  });
  @override
  State<NextSetWeight> createState() => _NextSetWeightState();
}

class _NextSetWeightState extends State<NextSetWeight> {
  EquipmentWeight? _draft;
  bool _dragging = false;
  @override
  void didUpdateWidget(NextSetWeight oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging &&
        oldWidget.pending.equipmentWeight.label !=
            widget.pending.equipmentWeight.label) {
      _draft = null;
    }
  }

  void _stage(EquipmentWeight weight) =>
      widget.controller.stagePendingReading(widget.pending.id, weight);
  Future<void> _save() async {
    final result = await widget.controller.flushPendingWeight();
    if (result == WorkoutWriteResult.failed && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final weight =
          _draft ??
          c.stagedReading(widget.pending.id) ??
          widget.pending.equipmentWeight;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('下一组重量'),
          WorkoutValueInput(
            weight: weight,
            reps: widget.pending.reps,
            step:
                widget.readingStep ??
                DecimalReading.parse(widget.step.toString()),
            enabled: !c.writing || c.savingWeight,
            showKgEquivalent: widget.showKgEquivalent,
            showReps: false,
            onRepsChanged: (_) {},
            onWeightChanged: (value) {
              if (!mounted) return;
              setState(() => _draft = value);
              if (!_dragging) {
                _stage(value);
                _save();
              }
            },
            onGestureActiveChanged: (active) {
              if (!mounted) return;
              setState(() => _dragging = active);
              widget.onGestureActiveChanged?.call(active);
              if (!active && _draft != null) {
                _stage(_draft!);
                _save();
              }
            },
          ),
          if (c.hasPendingWeight || c.writing)
            TextButton(
              onPressed: c.writing ? null : _save,
              child: Text(c.writeMessage == null ? '保存中…' : '重量未保存，重试'),
            ),
        ],
      );
    },
  );
}
