import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/domain/weight_value.dart';
import 'package:gym_tracker/features/workout/workout_value_input.dart';

class _Harness extends StatefulWidget {
  final EquipmentWeight? initialWeight;
  final int initialReps;
  const _Harness({super.key, this.initialWeight, this.initialReps = 8});
  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  late EquipmentWeight weight = widget.initialWeight ?? EquipmentWeight.kg(40);
  late int reps = widget.initialReps;
  bool active = false;
  final scroll = ScrollController();
  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        controller: scroll,
        child: Column(
          children: [
            WorkoutValueInput(
              weight: weight,
              reps: reps,
              step: DecimalReading.parse('2.5'),
              onWeightChanged: (value) {
                if (mounted) setState(() => weight = value);
              },
              onRepsChanged: (value) {
                if (mounted) setState(() => reps = value);
              },
              onGestureActiveChanged: (value) {
                if (mounted) setState(() => active = value);
              },
            ),
            const SizedBox(height: 1200),
          ],
        ),
      ),
    ),
  );
}

void main() {
  final weightFinder = find.byKey(const ValueKey('weight-adjuster'));
  final repsFinder = find.byKey(const ValueKey('reps-adjuster'));

  testWidgets(
    'diagonal region locks, second pointer ignored, no page scroll and cancel restores',
    (tester) async {
      final key = GlobalKey<_HarnessState>();
      await tester.pumpWidget(_Harness(key: key));
      final start = tester.getCenter(weightFinder);
      final pointer = await tester.startGesture(start, pointer: 1);
      await tester.pump();
      expect(key.currentState!.active, isTrue);
      await pointer.moveBy(const Offset(72, -48));
      await tester.pump();
      expect(key.currentState!.weight.label, '47.5 kg');
      expect(key.currentState!.reps, 8);
      expect(key.currentState!.scroll.offset, 0);
      final second = await tester.startGesture(
        tester.getCenter(repsFinder),
        pointer: 2,
      );
      await second.moveBy(const Offset(96, 0));
      await second.up();
      await tester.pump();
      expect(key.currentState!.reps, 8);
      expect(key.currentState!.active, isTrue);
      // Pointer stays owned by weight even after physically crossing to reps.
      await pointer.moveTo(tester.getCenter(repsFinder) + const Offset(100, 0));
      await tester.pump();
      expect(key.currentState!.reps, 8);
      await pointer.cancel();
      await tester.pump();
      expect(key.currentState!.weight.label, '40 kg');
      expect(key.currentState!.active, isFalse);
    },
  );

  testWidgets(
    'horizontal reps, exact thresholds, return to origin and release has no inertia',
    (tester) async {
      final key = GlobalKey<_HarnessState>();
      await tester.pumpWidget(_Harness(key: key));
      final start = tester.getCenter(repsFinder);
      final pointer = await tester.startGesture(start);
      await pointer.moveBy(const Offset(23, -60));
      await tester.pump();
      expect(key.currentState!.reps, 8);
      await pointer.moveTo(start + const Offset(72, -60));
      await tester.pump();
      expect(key.currentState!.reps, 11);
      expect(key.currentState!.weight.label, '40 kg');
      await pointer.moveTo(start);
      await tester.pump();
      expect(key.currentState!.reps, 8);
      await pointer.moveBy(const Offset(-48, 30));
      await pointer.up();
      await tester.pump(const Duration(seconds: 2));
      expect(key.currentState!.reps, 6);
      expect(key.currentState!.active, isFalse);
      final weightStart = tester.getCenter(weightFinder);
      final weightPointer = await tester.startGesture(weightStart);
      await weightPointer.moveBy(const Offset(100, -15));
      await tester.pump();
      expect(key.currentState!.weight.label, '40 kg');
      await weightPointer.moveTo(weightStart + const Offset(100, -16));
      await weightPointer.up();
      await tester.pump();
      expect(key.currentState!.weight.label, '42.5 kg');
    },
  );

  testWidgets(
    'boundaries reverse from fixed baseline and preserve imported outliers',
    (tester) async {
      final key = GlobalKey<_HarnessState>();
      await tester.pumpWidget(
        _Harness(
          key: key,
          initialWeight: EquipmentWeight.kg(501),
          initialReps: 110,
        ),
      );
      final start = tester.getCenter(weightFinder);
      final pointer = await tester.startGesture(start);
      await pointer.moveBy(const Offset(0, -64));
      await tester.pump();
      expect(key.currentState!.weight.label, '501 kg');
      await pointer.moveTo(start + const Offset(0, 16));
      await tester.pump();
      expect(key.currentState!.weight.label, '498.5 kg');
      await pointer.cancel();
      await tester.pump();
      expect(key.currentState!.weight.label, '501 kg');
      final repStart = tester.getCenter(repsFinder);
      final repPointer = await tester.startGesture(repStart);
      await repPointer.moveBy(const Offset(100, 0));
      await tester.pump();
      expect(key.currentState!.reps, 110);
      await repPointer.moveTo(repStart + const Offset(-24, 0));
      await repPointer.up();
      await tester.pump();
      expect(key.currentState!.reps, 109);
    },
  );

  testWidgets(
    'lifecycle cancellation restores origin and keyboard and semantics remain usable',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final key = GlobalKey<_HarnessState>();
      await tester.pumpWidget(_Harness(key: key));
      final pointer = await tester.startGesture(tester.getCenter(weightFinder));
      await pointer.moveBy(const Offset(0, -32));
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(key.currentState!.weight.label, '40 kg');
      expect(key.currentState!.active, isFalse);
      await pointer.cancel();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      Focus.of(tester.element(find.text('40'))).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      expect(key.currentState!.weight.label, '42.5 kg');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(key.currentState!.reps, 8);
      final node = tester.getSemantics(find.bySemanticsLabel('次数'));
      node.owner!.performAction(node.id, SemanticsAction.increase);
      await tester.pump();
      expect(key.currentState!.reps, 9);
      semantics.dispose();
    },
  );
}
