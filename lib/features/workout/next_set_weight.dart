import 'package:flutter/material.dart';

import '../../domain/types.dart';
import '../../domain/workout_edit.dart';
import '../../state/active_session_controller.dart';
import 'drag_number.dart';
import 'number_stepper.dart';

class NextSetWeight extends StatefulWidget {
  final ActiveSessionController controller;
  final SetEntry pending;
  final double step;
  const NextSetWeight({
    super.key,
    required this.controller,
    required this.pending,
    this.step = 2.5,
  });
  @override
  State<NextSetWeight> createState() => _NextSetWeightState();
}

class _NextSetWeightState extends State<NextSetWeight> {
  void _stage(double weight) =>
      widget.controller.stagePendingWeight(widget.pending.id, weight);
  Future<void> _save() async {
    final result = await widget.controller.flushPendingWeight();
    if (result == WorkoutWriteResult.failed && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final weight = c.stagedWeight(widget.pending.id) ?? widget.pending.weight;
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('下一组重量'),
          DragNumber(
            value: weight,
            step: widget.step,
            onChanged: _stage,
            onChangeEnd: _save,
          ),
          NumberStepper(
            value: weight,
            step: widget.step,
            onChanged: (v) {
              _stage(v);
              _save();
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
