import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/repositories/exercise_preferences_repo.dart';
import 'package:gym_tracker/features/workout/exercise_settings_sheet.dart';
import 'package:gym_tracker/features/workout/workout_value_input.dart';
import 'package:gym_tracker/domain/weight_value.dart';
import 'package:gym_tracker/domain/workout_edit.dart';
import 'package:gym_tracker/state/exercise_preferences_controller.dart';

import '../support/workout_fixture.dart';

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 14; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 40));
  }
}

class _SettingsHarness extends StatefulWidget {
  final WorkoutFixture fixture;
  final ExercisePreferencesController preferences;
  const _SettingsHarness({required this.fixture, required this.preferences});
  @override
  State<_SettingsHarness> createState() => _SettingsHarnessState();
}

class _SettingsHarnessState extends State<_SettingsHarness> {
  EquipmentWeight reading = EquipmentWeight.kg(40);
  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: Builder(
        builder: (context) {
          final prefs = widget.preferences.preferenceFor(
            widget.fixture.benchId,
          );
          return Column(
            children: [
              WorkoutValueInput(
                weight: reading,
                reps: 8,
                step: reading.unit == WeightUnit.kg
                    ? prefs.kgStep
                    : prefs.lbStep,
                showKgEquivalent: prefs.showKgEquivalent,
                onWeightChanged: (value) => setState(() => reading = value),
                onRepsChanged: (_) {},
              ),
              TextButton(
                child: const Text('打开幅度'),
                onPressed: () async {
                  final active = widget.fixture.controller;
                  await active.flushPendingWeight();
                  if (!context.mounted) return;
                  final result = await showExerciseSettingsSheet(
                    context,
                    widget.preferences,
                    widget.fixture.benchId,
                    '杠铃卧推',
                    sessionId: active.session!.id,
                    pendingSetId: active.currentExercise!.sets.last.id,
                    pendingReading: reading,
                  );
                  if (result == WorkoutWriteResult.saved) {
                    await active.resume();
                    if (mounted) {
                      setState(
                        () => reading =
                            active.currentExercise!.sets.last.equipmentWeight,
                      );
                    }
                  }
                },
              ),
            ],
          );
        },
      ),
    ),
  );
}

void main() {
  Future<(WorkoutFixture, ExercisePreferencesController)> prepare(
    WidgetTester tester,
  ) async {
    final f = (await tester.runAsync(workoutFixture))!;
    final prefs = ExercisePreferencesController(f.db);
    addTearDown(prefs.dispose);
    await tester.runAsync(() => prefs.load([f.benchId, f.rowId]));
    await tester.pumpWidget(_SettingsHarness(fixture: f, preferences: prefs));
    return (f, prefs);
  }

  Future<void> click(WidgetTester tester, String text) async {
    final finder = find.text(text).last;
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await _settle(tester);
  }

  testWidgets(
    'open and cancel do not write; explicit unit and step save retain native number',
    (tester) async {
      final (f, prefs) = await prepare(tester);
      await click(tester, '打开幅度');
      await click(tester, 'lb');
      await click(tester, '10 lb');
      await click(tester, '同时显示换算后的 kg');
      await click(tester, '取消');
      expect(find.text('40'), findsOneWidget);
      expect(prefs.preferenceFor(f.benchId).weightUnit, WeightUnit.kg);
      expect(prefs.preferenceFor(f.benchId).kgStep.text, '2.5');
      await tester.runAsync(() async {
        final rows = await f.db.all<Map<String, Object?>>(
          'SELECT * FROM set_entry WHERE is_completed=0',
        );
        expect(rows.single['source_unit'], 'kg');
        expect(rows.single['source_weight'], '20');
        expect(await f.db.all('SELECT * FROM exercise_preference'), isEmpty);
      });
      await click(tester, '打开幅度');
      await click(tester, 'lb');
      await click(tester, '10 lb');
      await click(tester, '同时显示换算后的 kg');
      await click(tester, '保存');
      expect(find.text('40'), findsOneWidget);
      expect(find.text('lb · 上下滑动'), findsOneWidget);
      expect(prefs.preferenceFor(f.benchId).lbStep.text, '10');
      expect(prefs.preferenceFor(f.rowId).weightUnit, WeightUnit.kg);
      final start = tester.getCenter(
        find.byKey(const ValueKey('weight-adjuster')),
      );
      final pointer = await tester.startGesture(start);
      await pointer.moveBy(const Offset(0, -16));
      await pointer.up();
      await tester.pump();
      expect(find.text('50'), findsOneWidget);
      expect(find.text('≈ 22.68 kg'), findsOneWidget);
      await tester.runAsync(() async {
        final rows = await f.db.all<Map<String, Object?>>(
          'SELECT * FROM set_entry WHERE is_completed=0',
        );
        expect(rows.single['source_unit'], 'lb');
        expect(rows.single['source_weight'], '40');
      });
    },
  );

  testWidgets(
    'custom invalid value stays local; each unit remembers its own confirmed step',
    (tester) async {
      final (f, prefs) = await prepare(tester);
      await click(tester, '打开幅度');
      await tester.enterText(
        find.byKey(const ValueKey('custom-weight-step')),
        '0',
      );
      await click(tester, '保存');
      expect(find.text('自定义幅度必须为正的有限数'), findsOneWidget);
      expect(prefs.preferenceFor(f.benchId).kgStep.text, '2.5');
      await tester.enterText(
        find.byKey(const ValueKey('custom-weight-step')),
        'NaN',
      );
      await click(tester, '保存');
      expect(find.text('自定义幅度必须为正的有限数'), findsOneWidget);
      await tester.enterText(
        find.byKey(const ValueKey('custom-weight-step')),
        '0.1',
      );
      await click(tester, 'lb');
      await click(tester, 'kg');
      expect(find.text('当前 0.1 kg'), findsOneWidget);
      await click(tester, '保存');
      expect(prefs.preferenceFor(f.benchId).kgStep.text, '0.1');
      await click(tester, '打开幅度');
      await click(tester, 'lb');
      await click(tester, '2.5 lb');
      await click(tester, '保存');
      expect(prefs.preferenceFor(f.benchId).kgStep.text, '0.1');
      expect(prefs.preferenceFor(f.benchId).lbStep.text, '2.5');
      await click(tester, '打开幅度');
      await click(tester, 'kg');
      expect(find.text('当前 0.1 kg'), findsOneWidget);
      await click(tester, '取消');
      expect(prefs.preferenceFor(f.benchId).weightUnit, WeightUnit.lb);
      final reloaded = await tester.runAsync(
        () => readExercisePreferences(f.db, [f.benchId, f.rowId]),
      );
      expect(reloaded![f.benchId]!.lbStep.text, '2.5');
      expect(reloaded[f.rowId]!.lbStep.text, '5');
    },
  );
}
