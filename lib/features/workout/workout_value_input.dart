import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/weight_value.dart';
import '../../ui/theme.dart';
import '../../ui/tokens.dart';
import 'adjustment_gesture.dart';

/// Controlled native-unit input. Every move is relative to the pointer-down
/// value; diagonal movement and crossing into the other region never retarget.
class WorkoutValueInput extends StatefulWidget {
  final EquipmentWeight weight;
  final int reps;
  final DecimalReading step;
  final ValueChanged<EquipmentWeight> onWeightChanged;
  final ValueChanged<int> onRepsChanged;
  final ValueChanged<bool>? onGestureActiveChanged;
  final bool enabled;
  final bool showKgEquivalent;
  final bool showReps;

  const WorkoutValueInput({
    super.key,
    required this.weight,
    required this.reps,
    required this.step,
    required this.onWeightChanged,
    required this.onRepsChanged,
    this.onGestureActiveChanged,
    this.enabled = true,
    this.showKgEquivalent = false,
    this.showReps = true,
  });

  @override
  State<WorkoutValueInput> createState() => _WorkoutValueInputState();
}

class _WorkoutValueInputState extends State<WorkoutValueInput>
    with WidgetsBindingObserver {
  final _gesture = AdjustmentGesture();
  EquipmentWeight? _startWeight;
  int? _startReps;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _cancel();
  }

  @override
  void didUpdateWidget(WorkoutValueInput oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.enabled && !widget.enabled) _cancel();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_gesture.activeTarget != null) {
      final target = _gesture.activeTarget!;
      final startWeight = _startWeight!;
      final startReps = _startReps!;
      final oldWidget = widget;
      // The owner may be being removed too; its callbacks check mounted.
      scheduleMicrotask(() {
        if (target == AdjustmentTarget.weight) {
          oldWidget.onWeightChanged(startWeight);
        } else {
          oldWidget.onRepsChanged(startReps);
        }
        oldWidget.onGestureActiveChanged?.call(false);
      });
    }
    _gesture.cancel();
    super.dispose();
  }

  void _begin(PointerDownEvent event, AdjustmentTarget target) {
    if (!widget.enabled ||
        !_gesture.begin(event.pointer, target, event.position)) {
      return;
    }
    _startWeight = widget.weight;
    _startReps = widget.reps;
    setState(() {});
    widget.onGestureActiveChanged?.call(true);
  }

  EquipmentWeight _adjustWeight(EquipmentWeight start, int ticks) {
    if (ticks == 0) return start;
    final maxAmount = math.max(
      start.amount.asDouble,
      start.unit == WeightUnit.kg ? 500 : 500 / 0.45359237,
    );
    EquipmentWeight next;
    try {
      next = start.plusSteps(widget.step, ticks);
    } on ArgumentError {
      next = EquipmentWeight(
        DecimalReading.parse(ticks < 0 ? '0' : maxAmount.toString()),
        start.unit,
      );
    }
    if (next.amount.asDouble > maxAmount) {
      return EquipmentWeight(
        DecimalReading.parse(maxAmount.toString()),
        start.unit,
      );
    }
    return next;
  }

  void _move(PointerMoveEvent event) {
    if (!_gesture.owns(event.pointer)) return;
    final ticks = _gesture.ticks(event.pointer, event.position);
    if (_gesture.activeTarget == AdjustmentTarget.weight) {
      widget.onWeightChanged(_adjustWeight(_startWeight!, ticks));
    } else {
      widget.onRepsChanged(
        (_startReps! + ticks).clamp(0, math.max(100, _startReps!)),
      );
    }
  }

  void _end(PointerUpEvent event) {
    if (!_gesture.end(event.pointer)) return;
    setState(() {});
    widget.onGestureActiveChanged?.call(false);
  }

  void _cancel() {
    final target = _gesture.activeTarget;
    if (target == null) return;
    _gesture.cancel();
    if (target == AdjustmentTarget.weight) {
      widget.onWeightChanged(_startWeight!);
    } else {
      widget.onRepsChanged(_startReps!);
    }
    if (mounted) setState(() {});
    widget.onGestureActiveChanged?.call(false);
  }

  void _increment(AdjustmentTarget target, int count) {
    if (!widget.enabled || _gesture.activeTarget != null) return;
    if (target == AdjustmentTarget.weight) {
      widget.onWeightChanged(_adjustWeight(widget.weight, count));
    } else {
      widget.onRepsChanged(
        (widget.reps + count).clamp(0, math.max(100, widget.reps)),
      );
    }
  }

  Widget _region(AdjustmentTarget target, Widget child) {
    final isWeight = target == AdjustmentTarget.weight;
    final active = _gesture.activeTarget;
    final colors = appColors(context);
    return Semantics(
      excludeSemantics: true,
      label: isWeight ? '重量' : '次数',
      value: isWeight ? widget.weight.label : '${widget.reps}',
      increasedValue: isWeight
          ? _adjustWeight(widget.weight, 1).label
          : '${(widget.reps + 1).clamp(0, math.max(100, widget.reps))}',
      decreasedValue: isWeight
          ? _adjustWeight(widget.weight, -1).label
          : '${(widget.reps - 1).clamp(0, math.max(100, widget.reps))}',
      slider: true,
      enabled: widget.enabled,
      onIncrease: widget.enabled ? () => _increment(target, 1) : null,
      onDecrease: widget.enabled ? () => _increment(target, -1) : null,
      child: Focus(
        onKeyEvent: (node, event) {
          if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
            return KeyEventResult.ignored;
          }
          final increase = isWeight
              ? LogicalKeyboardKey.arrowUp
              : LogicalKeyboardKey.arrowRight;
          final decrease = isWeight
              ? LogicalKeyboardKey.arrowDown
              : LogicalKeyboardKey.arrowLeft;
          if (event.logicalKey != increase && event.logicalKey != decrease) {
            return KeyEventResult.ignored;
          }
          _increment(target, event.logicalKey == increase ? 1 : -1);
          return KeyEventResult.handled;
        },
        child: Listener(
          key: ValueKey(isWeight ? 'weight-adjuster' : 'reps-adjuster'),
          behavior: HitTestBehavior.opaque,
          onPointerDown: (event) => _begin(event, target),
          onPointerMove: _move,
          onPointerUp: _end,
          onPointerCancel: (event) {
            if (_gesture.owns(event.pointer)) _cancel();
          },
          child: RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: {
              EagerGestureRecognizer:
                  GestureRecognizerFactoryWithHandlers<EagerGestureRecognizer>(
                    EagerGestureRecognizer.new,
                    (_) {},
                  ),
            },
            child: Opacity(
              opacity: active != null && active != target ? 0.45 : 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: active == target
                      ? colors.accent.withValues(alpha: 0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(padding: const EdgeInsets.all(12), child: child),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _region(
          AdjustmentTarget.weight,
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                child: Text(
                  widget.weight.amount.text,
                  style: TextStyle(
                    fontSize: 64,
                    fontWeight: FontWeight.w700,
                    color: _gesture.activeTarget == AdjustmentTarget.weight
                        ? colors.accent
                        : colors.textPrimary,
                    fontFeatures: tabularNums,
                  ),
                ),
              ),
              Text(
                '${widget.weight.unit.name} · 上下滑动',
                style: TextStyle(color: colors.textTertiary),
              ),
            ],
          ),
        ),
        if (widget.showKgEquivalent && widget.weight.unit == WeightUnit.lb)
          Text(widget.weight.kgReference),
        if (widget.showReps)
          _region(
            AdjustmentTarget.reps,
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('次数  '),
                Text(
                  '${widget.reps}',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w600,
                    color: _gesture.activeTarget == AdjustmentTarget.reps
                        ? colors.accent
                        : colors.textPrimary,
                  ),
                ),
                const Flexible(child: Text('  左右滑动')),
              ],
            ),
          ),
      ],
    );
  }
}
