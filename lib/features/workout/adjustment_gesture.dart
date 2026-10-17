import 'package:flutter/painting.dart';

enum AdjustmentTarget { weight, reps }

/// A single pointer owns the starting region until release or cancellation.
class AdjustmentGesture {
  int? _pointer;
  AdjustmentTarget? _target;
  Offset _origin = Offset.zero;

  AdjustmentTarget? get activeTarget => _target;

  bool begin(int pointer, AdjustmentTarget target, Offset origin) {
    if (_pointer != null) return false;
    _pointer = pointer;
    _target = target;
    _origin = origin;
    return true;
  }

  int ticks(int pointer, Offset position) {
    if (_pointer != pointer || _target == null) return 0;
    final delta = _target == AdjustmentTarget.weight
        ? _origin.dy - position.dy
        : position.dx - _origin.dx;
    return (delta / (_target == AdjustmentTarget.weight ? 16 : 24)).truncate();
  }

  bool owns(int pointer) => _pointer == pointer;

  bool end(int pointer) {
    if (!owns(pointer)) return false;
    cancel();
    return true;
  }

  void cancel() {
    _pointer = null;
    _target = null;
  }
}
