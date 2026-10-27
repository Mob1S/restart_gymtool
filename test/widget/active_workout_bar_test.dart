import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/state/active_session_controller.dart';
import 'package:gym_tracker/ui/theme.dart';
import 'package:gym_tracker/ui/tokens.dart';
import 'package:gym_tracker/ui/widgets/active_workout_bar.dart';

import '../support/workout_fixture.dart';

class _BusyController extends ActiveSessionController {
  bool busy = false;
  _BusyController(super.exec);
  @override
  bool get writing => busy || super.writing;
  void block() {
    busy = true;
    notifyListeners();
  }
}

Widget _bar(
  ActiveSessionController controller, {
  required VoidCallback onResume,
}) => AnimatedBuilder(
  animation: controller,
  builder: (_, _) => ActiveWorkoutBar(
    name: controller.session == null
        ? null
        : controller.session!.name ?? '本次训练',
    completedSets: controller.exercises
        .expand((e) => e.sets)
        .where((s) => s.isCompleted)
        .length,
    loading: controller.loading,
    enabled: !controller.writing,
    error: controller.resumeError,
    onRetry: () => controller.ensureResumed(),
    onResume: onResume,
  ),
);
void main() {
  testWidgets(
    'completed parent count ignores pending sets and tap is reachable',
    (tester) async {
      final f = (await tester.runAsync(workoutFixture))!;
      await tester.runAsync(() => f.controller.completeCurrentSet(60, 8));
      var resumed = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(AppColors.dark),
          home: Scaffold(
            bottomNavigationBar: _bar(f.controller, onResume: () => resumed++),
          ),
        ),
      );
      expect(find.text('已完成 1 组'), findsOneWidget);
      final target = find.byKey(const ValueKey('active-workout-resume'));
      expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
      final semantics = tester.ensureSemantics();
      expect(
        tester
            .getSemantics(find.bySemanticsLabel(RegExp('继续训练，')))
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
      await tester.tap(target);
      expect(resumed, 1);
      semantics.dispose();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('ending removes the bar without reserving space', (tester) async {
    final f = (await tester.runAsync(workoutFixture))!;
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(AppColors.light),
        home: Scaffold(
          bottomNavigationBar: _bar(f.controller, onResume: () {}),
        ),
      ),
    );
    await tester.runAsync(f.controller.endWorkout);
    await tester.pump();
    expect(find.byKey(const ValueKey('active-workout-resume')), findsNothing);
    expect(tester.getSize(find.byType(ActiveWorkoutBar)).height, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('320px with 2x text keeps the resume action and count visible', (
    tester,
  ) async {
    final f = (await tester.runAsync(workoutFixture))!;
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(AppColors.dark),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(2)),
          child: child!,
        ),
        home: Scaffold(
          bottomNavigationBar: _bar(f.controller, onResume: () {}),
        ),
      ),
    );
    expect(find.text('已完成 0 组'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'busy workout removes the screen-reader tap action and is disabled',
    (tester) async {
      final f = (await tester.runAsync(workoutFixture))!;
      final active = _BusyController(f.db)
        ..session = f.controller.session
        ..exercises = f.controller.exercises;
      addTearDown(active.dispose);
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(AppColors.dark),
          home: Scaffold(bottomNavigationBar: _bar(active, onResume: () {})),
        ),
      );
      active.block();
      await tester.pump();
      final data = tester
          .getSemantics(find.bySemanticsLabel(RegExp('继续训练，')))
          .getSemanticsData();
      expect(data.hasAction(SemanticsAction.tap), isFalse);
      expect(data.flagsCollection.isEnabled, Tristate.isFalse);
      semantics.dispose();
      await tester.pumpWidget(const SizedBox());
    },
  );
}
