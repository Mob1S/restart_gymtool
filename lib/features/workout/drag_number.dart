import 'package:flutter/material.dart';

import '../../ui/theme.dart';
import '../../ui/tokens.dart';

/// 可拖动调值的大数字。
///
/// 规格 §6.2：**拖动与步进器并存，不是二选一。**
/// 拖动管大跨度（20 → 60），步进器管微调 —— 旧项目真机使用后确认二者互补。
///
/// 纯拖动会被汗手坑：**手上有汗、屏幕可能湿，想调 2.5kg 却滑过头**，
/// 所以它是「快速粗调」，精调交给步进器。
class DragNumber extends StatefulWidget {
  final double value;
  final double step;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final String unit;

  /// 拖动灵敏度：每多少逻辑像素走一档。旧项目实测 12dp/档手感合适。
  final double pixelsPerStep;

  const DragNumber({
    super.key,
    required this.value,
    required this.onChanged,
    this.step = 2.5,
    this.min = 0,
    this.max = 500,
    this.unit = 'kg',
    this.pixelsPerStep = 12,
  });

  @override
  State<DragNumber> createState() => _DragNumberState();
}

class _DragNumberState extends State<DragNumber> {
  late double _accumulated;

  @override
  void initState() {
    super.initState();
    _accumulated = 0;
  }

  void _onDragStart(DragStartDetails _) => _accumulated = 0;

  void _onDragUpdate(DragUpdateDetails d) {
    // 向上拖 = 加重，所以取负
    _accumulated += -d.delta.dy;
    final steps = (_accumulated / widget.pixelsPerStep).truncate();
    if (steps == 0) return;
    _accumulated -= steps * widget.pixelsPerStep;

    final next = (widget.value + steps * widget.step)
        .clamp(widget.min, widget.max);
    if (next != widget.value) widget.onChanged(_round(next));
  }

  double _round(double v) => (v / widget.step).round() * widget.step;

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    return GestureDetector(
      onVerticalDragStart: _onDragStart,
      onVerticalDragUpdate: _onDragUpdate,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            // 整数不显示小数点，22.5 显示一位 —— tabularFigures 保证不抖
            widget.value == widget.value.roundToDouble()
                ? widget.value.toInt().toString()
                : widget.value.toStringAsFixed(1),
            style: TextStyle(
              fontSize: AppFontSize.display,
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
              fontFeatures: tabularNums,
              height: 1.0,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(widget.unit, style: TextStyle(
            fontSize: AppFontSize.label,
            letterSpacing: AppTracking.unit,
            color: c.textTertiary,
          )),
        ],
      ),
    );
  }
}
