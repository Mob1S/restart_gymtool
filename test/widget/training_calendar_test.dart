import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/domain/local_date.dart';
import 'package:gym_tracker/features/workout/training_calendar.dart';
import 'package:gym_tracker/ui/theme.dart';
import 'package:gym_tracker/ui/tokens.dart';

void main() {
  Future<void> pumpCalendar(
    WidgetTester tester, {
    required DateTime month,
    Set<String> completedDates = const {},
    ValueChanged<LocalDate>? onDateSelected,
    ValueChanged<DateTime>? onMonthChanged,
    TextScaler textScaler = TextScaler.noScaling,
  }) => tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(AppColors.light),
      home: Scaffold(
        body: MediaQuery(
          data: MediaQueryData(textScaler: textScaler),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.screenH,
              ),
              child: TrainingCalendar(
                displayedMonth: month,
                completedDates: completedDates,
                onDateSelected: onDateSelected ?? (_) {},
                onMonthChanged: onMonthChanged ?? (_) {},
                today: DateTime(2026, 10, 17),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  for (final example in [
    (year: 2021, month: 2, days: 28, rows: 4, leading: 0),
    (year: 2024, month: 2, days: 29, rows: 5, leading: 3),
    (year: 2026, month: 4, days: 30, rows: 5, leading: 2),
    (year: 2026, month: 10, days: 31, rows: 5, leading: 3),
    (year: 2026, month: 8, days: 31, rows: 6, leading: 5),
  ]) {
    testWidgets(
      '${example.year}-${example.month} has Monday-first dynamic rows',
      (tester) async {
        await pumpCalendar(
          tester,
          month: DateTime(example.year, example.month),
        );
        expect(find.byType(TrainingCalendar), findsOneWidget);
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey<String> &&
                (widget.key! as ValueKey<String>).value.startsWith(
                  'calendar-row-',
                ),
          ),
          findsNWidgets(example.rows),
        );
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget.key is ValueKey<String> &&
                (widget.key! as ValueKey<String>).value.startsWith(
                  'calendar-day-',
                ),
          ),
          findsNWidgets(example.days),
        );
        final firstKey = LocalDate(example.year, example.month, 1).key;
        final firstRect = tester.getRect(
          find.byKey(ValueKey('calendar-day-$firstKey')),
        );
        final mondayRect = tester.getRect(
          find.byKey(const ValueKey('calendar-weekday-0')),
        );
        final tuesdayRect = tester.getRect(
          find.byKey(const ValueKey('calendar-weekday-1')),
        );
        final columnWidth = tuesdayRect.left - mondayRect.left;
        expect(
          firstRect.left - mondayRect.left,
          closeTo(example.leading * columnWidth, 0.01),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'month arrows normalize across years and return to current month',
    (tester) async {
      final changes = <DateTime>[];
      await pumpCalendar(
        tester,
        month: DateTime(2026, 12, 20, 17),
        onMonthChanged: changes.add,
      );
      await tester.tap(find.byTooltip('下个月'));
      expect(changes.last, DateTime(2027, 1));
      await tester.tap(find.text('回到本月'));
      expect(changes.last, DateTime(2026, 10));
      await pumpCalendar(
        tester,
        month: DateTime(2026, 1),
        onMonthChanged: changes.add,
      );
      await tester.tap(find.byTooltip('上个月'));
      expect(changes.last, DateTime(2025, 12));
    },
  );

  testWidgets('selecting a day emits its date and empty cells do not select', (
    tester,
  ) async {
    final selections = <LocalDate>[];
    await pumpCalendar(
      tester,
      month: DateTime(2026, 10),
      onDateSelected: selections.add,
    );
    await tester.tap(find.byKey(const ValueKey('calendar-day-2026-10-16')));
    expect(selections, [LocalDate(2026, 10, 16)]);
    await tester.tapAt(
      tester.getCenter(find.byKey(const ValueKey('calendar-empty-0'))) +
          const Offset(0, AppSpacing.sm),
    );
    expect(selections, hasLength(1));
    expect(find.text('回到本月'), findsNothing);
  });

  testWidgets(
    'today and completed records have visible and accessible markers',
    (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpCalendar(
        tester,
        month: DateTime(2026, 10),
        completedDates: {'2026-10-16', '2026-10-17', '2026-09-01'},
      );
      expect(
        find.byKey(const ValueKey('calendar-today-2026-10-17')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('calendar-completed-2026-10-16')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('calendar-completed-2026-10-17')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('calendar-completed-2026-09-01')),
        findsNothing,
      );
      expect(find.bySemanticsLabel('2026年10月16日，有已完成训练'), findsOneWidget);
      expect(find.bySemanticsLabel('2026年10月17日，今天，有已完成训练'), findsOneWidget);
      expect(
        tester.getSemantics(
          find.byKey(const ValueKey('calendar-day-2026-10-16')),
        ),
        matchesSemantics(
          label: '2026年10月16日，有已完成训练',
          isButton: true,
          hasTapAction: true,
        ),
      );
      semantics.dispose();
    },
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      '320dp six-row calendar stays inside viewport at text scale $scale',
      (tester) async {
        tester.view.physicalSize = const Size(320, 480);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await pumpCalendar(
          tester,
          month: DateTime(2026, 8),
          textScaler: TextScaler.linear(scale),
        );
        expect(tester.takeException(), isNull);
        for (var day = 1; day <= 31; day++) {
          final key = LocalDate(2026, 8, day).key;
          final rect = tester.getRect(
            find.byKey(ValueKey('calendar-day-$key')),
          );
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(320));
        }
        await tester.ensureVisible(
          find.byKey(const ValueKey('calendar-day-2026-08-31')),
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
