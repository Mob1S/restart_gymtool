import 'package:flutter/material.dart';

import '../../state/active_session_controller.dart';
import '../../ui/theme.dart';
import '../../ui/tokens.dart';

/// 顶部横向动作条 + `＋`。
///
/// **`SafeArea` 已由外壳负责**，这里不重复加 —— 但它是横向滚动的，
/// 最后一个 chip 之后要留出尾距，否则看起来像被截断。
class ExerciseStrip extends StatelessWidget {
  final List<ActiveExercise> exercises;
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;

  const ExerciseStrip({
    super.key,
    required this.exercises,
    required this.currentIndex,
    required this.onSelect,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
        children: [
          for (var i = 0; i < exercises.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: _chip(context, exercises[i].exerciseName, i == currentIndex,
                  () => onSelect(i)),
            ),
          // 旧项目另一处坑：训练里一个动作都没有时是条死路 ——
          // 空态只写了一句「这次训练还没有动作」，没有任何添加入口。
          // 所以这个 ＋ 永远在，无论当前有没有动作。
          GestureDetector(
            onTap: onAdd,
            child: Container(
              width: 44,
              height: 36,
              decoration: BoxDecoration(
                color: c.surfacePressed,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                border: Border.all(color: c.border),
              ),
              child: Icon(Icons.add, size: 20, color: c.accent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String label, bool active, VoidCallback onTap) {
    final c = appColors(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? c.accent.withValues(alpha: 0.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          border: Border.all(color: active ? c.accent : c.border),
        ),
        child: Text(label, style: TextStyle(
          fontSize: AppFontSize.body,
          fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          color: active ? c.accent : c.textSecondary,
        )),
      ),
    );
  }
}
