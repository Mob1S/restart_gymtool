import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/sql_executor.dart';
import 'package:gym_tracker/data/repositories/exercise_repo.dart';
import 'package:gym_tracker/data/repositories/session_repo.dart';
import 'package:gym_tracker/data/repositories/set_repo.dart';
import 'package:gym_tracker/domain/session_comparison.dart';
import 'package:gym_tracker/domain/session_summary.dart';
import 'package:gym_tracker/domain/types.dart';
import 'package:gym_tracker/features/history/session_detail_page.dart';
import 'package:gym_tracker/features/workout/summary_page.dart';
import 'package:gym_tracker/state/data_revision.dart';
import 'package:gym_tracker/state/summary_feedback_loader.dart';
import 'package:gym_tracker/ui/theme.dart';
import 'package:gym_tracker/ui/tokens.dart';
import 'package:provider/provider.dart';

SessionSummary summary(String id) => SessionSummary(
  session: WorkoutSession(id: id, startedAt: 100, finishedAt: 200),
  exercises: const [],
  durationSeconds: 0,
  totalSets: 0,
  volumeLoad: 0,
);

ExerciseComparison comparison(String id) => ExerciseComparison(
  exerciseId: id,
  exerciseName: id,
  current: SessionExerciseRecord(
    session: summary(id).session,
    occurrences: const [],
  ),
);

class _UnusedExecutor implements SqlExecutor {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Unexpected SQL');
}

class _Harness extends StatefulWidget {
  final List<Completer<SessionSummary?>> summaries;
  final List<Completer<List<ExerciseComparison>>> comparisons;
  const _Harness({
    super.key,
    required this.summaries,
    required this.comparisons,
  });
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness>
    with SummaryFeedbackLoader<_Harness> {
  Future<void> reload([String id = 'current']) =>
      loadSummaryFeedback(_UnusedExecutor(), id);
  @override
  Future<SessionSummary?> readFeedbackSummary(SqlExecutor exec, String id) =>
      widget.summaries.removeAt(0).future;
  @override
  Future<List<ExerciseComparison>> readFeedbackComparisons(
    SqlExecutor exec,
    SessionSummary value,
  ) => widget.comparisons.removeAt(0).future;
  @override
  Widget build(BuildContext context) => Text(
    [
      feedbackSummary?.session.id ?? 'empty',
      ...?feedbackComparisons?.map((e) => e.exerciseId),
      comparisonError ?? '',
      feedbackError ?? '',
    ].join('|'),
    textDirection: TextDirection.ltr,
  );
}

void main() {
  testWidgets(
    'failed refresh keeps the current summary and exposes a retry state',
    (tester) async {
      final initial = Completer<SessionSummary?>();
      final refresh = Completer<SessionSummary?>();
      final compared = Completer<List<ExerciseComparison>>();
      final key = GlobalKey<_HarnessState>();
      await tester.pumpWidget(
        _Harness(
          key: key,
          summaries: [initial, refresh],
          comparisons: [compared],
        ),
      );
      final loaded = key.currentState!.reload();
      initial.complete(summary('current'));
      await tester.pump();
      compared.complete([]);
      await loaded;
      final reloaded = key.currentState!.reload();
      refresh.completeError(StateError('database unavailable'));
      await reloaded;
      await tester.pump();
      expect(find.text('current||训练记录载入失败，请重试'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'switching session hides the old record before the new read finishes',
    (tester) async {
      final initial = Completer<SessionSummary?>();
      final next = Completer<SessionSummary?>();
      final compared = Completer<List<ExerciseComparison>>();
      final nextCompared = Completer<List<ExerciseComparison>>();
      final key = GlobalKey<_HarnessState>();
      await tester.pumpWidget(
        _Harness(
          key: key,
          summaries: [initial, next],
          comparisons: [compared, nextCompared],
        ),
      );
      final loaded = key.currentState!.reload();
      initial.complete(summary('current'));
      await tester.pump();
      compared.complete([]);
      await loaded;
      final changed = key.currentState!.reload('another');
      await tester.pump();
      expect(find.text('empty||'), findsOneWidget);
      next.complete(summary('another'));
      await tester.pump();
      nextCompared.complete([]);
      await changed;
      await tester.pump();
      expect(find.text('another||'), findsOneWidget);
    },
  );

  testWidgets('older comparison cannot overwrite a newer revision', (
    tester,
  ) async {
    final first = Completer<SessionSummary?>(),
        second = Completer<SessionSummary?>();
    final firstComparison = Completer<List<ExerciseComparison>>();
    final secondComparison = Completer<List<ExerciseComparison>>();
    final key = GlobalKey<_HarnessState>();
    await tester.pumpWidget(
      _Harness(
        key: key,
        summaries: [first, second],
        comparisons: [firstComparison, secondComparison],
      ),
    );
    final before = key.currentState!.reload();
    first.complete(summary('old-summary'));
    await tester.pump();
    final after = key.currentState!.reload();
    second.complete(summary('new-summary'));
    await tester.pump();
    secondComparison.complete([comparison('new-comparison')]);
    await tester.pump();
    firstComparison.complete([comparison('old-comparison')]);
    await Future.wait([before, after]);
    await tester.pump();
    expect(find.text('new-summary|new-comparison||'), findsOneWidget);
  });

  testWidgets(
    'comparison failure preserves summary and a retry replaces the error',
    (tester) async {
      final first = Completer<SessionSummary?>(),
          second = Completer<SessionSummary?>();
      final failed = Completer<List<ExerciseComparison>>();
      final retry = Completer<List<ExerciseComparison>>();
      final key = GlobalKey<_HarnessState>();
      await tester.pumpWidget(
        _Harness(
          key: key,
          summaries: [first, second],
          comparisons: [failed, retry],
        ),
      );
      final load = key.currentState!.reload();
      first.complete(summary('kept'));
      await tester.pump();
      failed.completeError(StateError('read failed'));
      await load;
      await tester.pump();
      expect(find.textContaining('kept|上次记录对比暂不可用'), findsOneWidget);
      final retried = key.currentState!.reload();
      second.complete(summary('kept'));
      await tester.pump();
      retry.complete([comparison('retry-result')]);
      await retried;
      await tester.pump();
      expect(find.text('kept|retry-result||'), findsOneWidget);
    },
  );

  testWidgets('older summary and results after disposal are ignored', (
    tester,
  ) async {
    final first = Completer<SessionSummary?>(),
        second = Completer<SessionSummary?>();
    final cmp = Completer<List<ExerciseComparison>>();
    final key = GlobalKey<_HarnessState>();
    await tester.pumpWidget(
      _Harness(key: key, summaries: [first, second], comparisons: [cmp]),
    );
    final old = key.currentState!.reload();
    final latest = key.currentState!.reload();
    second.complete(summary('latest'));
    await tester.pump();
    cmp.complete([comparison('latest-result')]);
    await latest;
    await tester.pumpWidget(const SizedBox.shrink());
    first.complete(summary('obsolete'));
    await old;
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  Future<void> settleReal(WidgetTester tester) async {
    for (var i = 0; i < 18; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
    }
  }

  for (final isHistory in [false, true]) {
    testWidgets(
      '${isHistory ? 'history' : 'summary'} comparison reloads when a baseline is corrected',
      (tester) async {
        late FfiExecutor db;
        late String currentId, previousSetId;
        await tester.runAsync(() async {
          db = await FfiExecutor.openMigrated();
          final exercise = await createCustomExercise(db, name: '对比卧推');
          final start = DateTime(2026, 10, 24, 10).millisecondsSinceEpoch;
          for (var i = 0; i < 2; i++) {
            final s = await createSession(db, name: '对比训练');
            final e = await addExerciseToSession(db, s.id, exercise.id);
            final st = await addSet(db, e.id, 60, i == 0 ? 7 : 8);
            await completeSet(db, st.id, start + i * 86400000);
            await db.run(
              'UPDATE session SET started_at=?, finished_at=? WHERE id=?',
              [start + i * 86400000, start + i * 86400000 + 60000, s.id],
            );
            if (i == 0) previousSetId = st.id;
            if (i == 1) currentId = s.id;
          }
        });
        addTearDown(db.close);
        final revision = DataRevision();
        addTearDown(revision.dispose);
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              Provider<SqlExecutor>.value(value: db),
              ChangeNotifierProvider<DataRevision>.value(value: revision),
            ],
            child: MaterialApp(
              theme: buildTheme(AppColors.dark),
              home: isHistory
                  ? SessionDetailPage(sessionId: currentId)
                  : SummaryPage(sessionId: currentId),
            ),
          ),
        );
        await settleReal(tester);
        expect(find.text('训练量变化：1 组 → 1 组 · 容量增加 60 kg'), findsOneWidget);
        await tester.runAsync(
          () => db.run('UPDATE set_entry SET reps=? WHERE id=?', [
            6,
            previousSetId,
          ]),
        );
        revision.changed();
        await settleReal(tester);
        expect(find.text('训练量变化：1 组 → 1 组 · 容量增加 120 kg'), findsOneWidget);
        expect(find.textContaining('60 kg × 6'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
