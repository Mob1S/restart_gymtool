import 'package:flutter/material.dart';

import '../../domain/local_date.dart';
import '../../ui/theme.dart';
import '../../ui/tokens.dart';

/// A month calendar that only selects dates; it never changes workout state.
class TrainingCalendar extends StatelessWidget {
  final DateTime displayedMonth;
  final Set<String> completedDates;
  final ValueChanged<LocalDate> onDateSelected;
  final ValueChanged<DateTime> onMonthChanged;
  final DateTime? today;
  final bool compact;

  const TrainingCalendar({
    super.key,
    required this.displayedMonth,
    required this.completedDates,
    required this.onDateSelected,
    required this.onMonthChanged,
    this.today,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = appColors(context);
    final currentDate = LocalDate.fromDateTime(today ?? DateTime.now());
    final first = DateTime(displayedMonth.year, displayedMonth.month);
    final leading = (first.weekday + 6) % 7;
    final count = DateTime(first.year, first.month + 1, 0).day;
    final rows = ((leading + count) / 7).ceil();
    final isCurrentMonth =
        first.year == currentDate.year && first.month == currentDate.month;

    return Material(
      type: MaterialType.transparency,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (compact && !isCurrentMonth)
                IconButton(
                  tooltip: '回到本月',
                  constraints: const BoxConstraints.tightFor(
                    width: 36,
                    height: 36,
                  ),
                  padding: EdgeInsets.zero,
                  onPressed: () => onMonthChanged(
                    DateTime(currentDate.year, currentDate.month),
                  ),
                  icon: const Icon(Icons.today_outlined, size: 18),
                ),
              IconButton(
                constraints: compact
                    ? const BoxConstraints.tightFor(width: 36, height: 36)
                    : null,
                padding: compact ? EdgeInsets.zero : const EdgeInsets.all(8),
                tooltip: '上个月',
                onPressed: () =>
                    onMonthChanged(DateTime(first.year, first.month - 1)),
                icon: const Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Text(
                  '${first.year}年${first.month}月',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: AppFontSize.body,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                    fontFeatures: tabularNums,
                  ),
                ),
              ),
              IconButton(
                constraints: compact
                    ? const BoxConstraints.tightFor(width: 36, height: 36)
                    : null,
                padding: compact ? EdgeInsets.zero : const EdgeInsets.all(8),
                tooltip: '下个月',
                onPressed: () =>
                    onMonthChanged(DateTime(first.year, first.month + 1)),
                icon: const Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          if (!isCurrentMonth && !compact)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => onMonthChanged(
                  DateTime(currentDate.year, currentDate.month),
                ),
                child: const Text('回到本月'),
              ),
            ),
          Row(
            children: [
              for (var index = 0; index < 7; index++)
                Expanded(
                  child: Padding(
                    key: ValueKey('calendar-weekday-$index'),
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.xs,
                    ),
                    child: Text(
                      const ['一', '二', '三', '四', '五', '六', '日'][index],
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: AppFontSize.label,
                        color: colors.textTertiary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          for (var row = 0; row < rows; row++)
            Row(
              key: ValueKey('calendar-row-$row'),
              children: [
                for (var column = 0; column < 7; column++)
                  Expanded(
                    child: _cell(
                      context,
                      first,
                      row * 7 + column,
                      leading,
                      count,
                      currentDate,
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _cell(
    BuildContext context,
    DateTime first,
    int index,
    int leading,
    int count,
    LocalDate currentDate,
  ) {
    final day = index - leading + 1;
    if (day < 1 || day > count) {
      return SizedBox(key: ValueKey('calendar-empty-$index'));
    }
    final date = LocalDate(first.year, first.month, day);
    final isToday = date == currentDate;
    final hasTraining = completedDates.contains(date.key);
    final colors = appColors(context);
    final label = StringBuffer('${date.year}年${date.month}月${date.day}日');
    if (isToday) label.write('，今天');
    if (hasTraining) label.write('，有已完成训练');

    return Semantics(
      key: ValueKey('calendar-day-${date.key}'),
      button: true,
      label: label.toString(),
      excludeSemantics: true,
      onTap: () => onDateSelected(date),
      child: SizedBox(
        height: compact ? 28 : null,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          onTap: () => onDateSelected(date),
          child: DecoratedBox(
            key: isToday ? ValueKey('calendar-today-${date.key}') : null,
            decoration: BoxDecoration(
              color: isToday ? colors.accent.withValues(alpha: 0.1) : null,
              border: isToday ? Border.all(color: colors.accent) : null,
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: Stack(
              alignment: Alignment.center,
              children: [
                Padding(
                  padding: EdgeInsets.only(
                    top: compact ? 0 : AppSpacing.xs,
                    bottom: compact ? 3 : AppSpacing.sm,
                  ),
                  child: Center(
                    child: Text(
                      '$day',
                      style: TextStyle(
                        fontSize: AppFontSize.caption,
                        fontWeight: isToday ? FontWeight.w700 : FontWeight.w500,
                        color: isToday ? colors.accent : colors.textPrimary,
                        fontFeatures: tabularNums,
                      ),
                    ),
                  ),
                ),
                if (hasTraining)
                  Positioned(
                    bottom: AppSpacing.xs / 2,
                    child: Container(
                      key: ValueKey('calendar-completed-${date.key}'),
                      width: AppSpacing.xs,
                      height: AppSpacing.xs,
                      decoration: BoxDecoration(
                        color: colors.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
