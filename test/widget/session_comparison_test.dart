import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/domain/session_comparison.dart';
import 'package:gym_tracker/domain/session_summary.dart';
import 'package:gym_tracker/domain/set_detail.dart';
import 'package:gym_tracker/domain/training_prescription.dart';
import 'package:gym_tracker/domain/types.dart';
import 'package:gym_tracker/domain/weight_value.dart';
import 'package:gym_tracker/ui/theme.dart';
import 'package:gym_tracker/ui/tokens.dart';
import 'package:gym_tracker/ui/widgets/session_comparison_view.dart';

SessionExerciseRecord record(String id, List<List<SetEntry>> occurrences) =>
    SessionExerciseRecord(
      session: WorkoutSession(
        id: id,
        startedAt: DateTime(
          2026,
          10,
          id == 'previous' ? 24 : 27,
        ).millisecondsSinceEpoch,
        finishedAt: DateTime(2026, 10, 27, 12).millisecondsSinceEpoch,
      ),
      occurrences: [
        for (final sets in occurrences)
          ExerciseSummary(exerciseId: 'bench', exerciseName: '卧推', sets: sets),
      ],
    );

SetEntry set(
  String id, {
  double kg = 60,
  int reps = 8,
  SetDetail? detail,
  EquipmentWeight? reading,
}) => SetEntry(
  id: id,
  sessionExerciseId: 'occurrence-$id',
  position: 0,
  weight: kg,
  recordedWeight: reading,
  reps: reps,
  isCompleted: true,
  detail: detail,
);

Future<void> pumpComparison(
  WidgetTester tester,
  Widget child, {
  double scale = 1,
  AppColors colors = AppColors.dark,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: buildTheme(colors),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    ),
  );
}

void main() {
  testWidgets('shows raw records and volume change without a strength claim', (
    tester,
  ) async {
    await pumpComparison(
      tester,
      SessionComparisonView(
        comparisons: [
          ExerciseComparison(
            exerciseId: 'bench',
            exerciseName: '卧推',
            current: record('current', [
              [set('now')],
            ]),
            previous: record('previous', [
              [set('then', reps: 7)],
            ]),
          ),
        ],
      ),
    );
    expect(find.text('与上次同动作记录对比'), findsOneWidget);
    expect(find.textContaining('本次 · 2026年10月27日'), findsOneWidget);
    expect(find.textContaining('上次 · 2026年10月24日'), findsOneWidget);
    expect(find.textContaining('60 kg × 8 · 未分类 · 用力程度未记录'), findsOneWidget);
    expect(find.textContaining('60 kg × 7'), findsOneWidget);
    expect(find.text('训练量变化：1 组 → 1 组 · 容量增加 60 kg'), findsOneWidget);
    expect(find.textContaining('变强'), findsNothing);
    expect(find.textContaining('个人最好'), findsNothing);
  });

  testWidgets(
    'keeps units, role, effort and rest-pause occurrence boundaries',
    (tester) async {
      final pounds = EquipmentWeight(
        DecimalReading.parse('100'),
        WeightUnit.lb,
      );
      final detail = SetDetail(
        role: 'work',
        effort: const Effort('rpe', 8),
        endedEarly: true,
        continuations: [
          RecordedSegment(
            reading: pounds,
            reps: 4,
            completedAt: 2,
            pauseSeconds: 5,
            effort: const Effort('rir', 2),
          ),
        ],
      );
      await pumpComparison(
        tester,
        SessionComparisonView(
          comparisons: [
            ExerciseComparison(
              exerciseId: 'bench',
              exerciseName: '卧推',
              current: record('current', [
                [
                  set(
                    'warm',
                    kg: 20,
                    reps: 5,
                    detail: SetDetail(role: 'warmup'),
                  ),
                ],
                [
                  set(
                    'work',
                    kg: pounds.kilograms,
                    reading: pounds,
                    detail: detail,
                  ),
                ],
              ]),
            ),
          ],
        ),
      );
      expect(find.text('第 1 次出现'), findsOneWidget);
      expect(find.text('第 2 次出现'), findsOneWidget);
      expect(find.textContaining('20 kg × 5 · 热身'), findsOneWidget);
      expect(find.textContaining('100 lb × 8 · 正式 · RPE 8'), findsOneWidget);
      expect(find.text('休息 5 秒 → 100 lb × 4 · RIR 2'), findsOneWidget);
      expect(find.text('本组提前结束，仅统计已完成部分'), findsOneWidget);
      expect(find.text('首次记录，暂没有上次可对比'), findsOneWidget);
      expect(find.textContaining('2 组 · 容量'), findsOneWidget);
    },
  );

  testWidgets(
    'loading and retry are explicit, empty comparison takes no space',
    (tester) async {
      var retries = 0;
      await pumpComparison(tester, const SessionComparisonView(loading: true));
      expect(find.text('正在读取上次记录…'), findsOneWidget);
      await pumpComparison(
        tester,
        SessionComparisonView(error: '暂不可用', onRetry: () => retries++),
      );
      await tester.tap(find.text('重试对比'));
      expect(retries, 1);
      await pumpComparison(
        tester,
        const SessionComparisonView(comparisons: []),
      );
      expect(find.text('与上次同动作记录对比'), findsNothing);
    },
  );

  for (final colors in [AppColors.dark, AppColors.light]) {
    testWidgets(
      '320px large text comparison wraps in ${colors == AppColors.dark ? 'dark' : 'light'} theme',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(320, 560);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await pumpComparison(
          tester,
          SessionComparisonView(
            comparisons: [
              ExerciseComparison(
                exerciseId: 'bench',
                exerciseName: '较长的器械辅助训练动作名称',
                current: record('current', [
                  [set('now')],
                ]),
                previous: record('previous', [
                  [set('then', reps: 7)],
                ]),
              ),
            ],
          ),
          scale: 2,
          colors: colors,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
