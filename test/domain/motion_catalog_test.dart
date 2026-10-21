import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/domain/motion_catalog.dart';
import 'package:gym_tracker/domain/motion_observations.dart';
import 'package:gym_tracker/domain/video_review.dart';

void main() {
  test(
    'four profiles have stable independent cycles and view capabilities',
    () {
      expect(MotionCatalog.profiles.map((p) => p.id).toSet().length, 4);
      for (final p in MotionCatalog.profiles) {
        expect(p.version, greaterThan(0));
        expect(p.phases.length, greaterThanOrEqualTo(4));
        expect(p.trajectoryTargets, isNotEmpty);
        expect(p.candidateObservations, isNotEmpty);
        for (final view in MotionView.values) {
          expect(p.viewAdvice[view], isNotEmpty);
          expect(p.views[view], isNotNull);
        }
      }
      expect(MotionCatalog.byId(null).id, MotionCatalog.bench);
      expect(MotionCatalog.byId('future_action').name, '未知动作');
      expect(
        MotionCatalog.byId('future_action').capability(MotionView.side),
        MotionCapability.unavailable,
      );
      expect(MotionCatalog.byId(MotionCatalog.pullUp).hasBarbell, isFalse);
    },
  );

  test(
    'pose path preserves missing spans and never manufactures a bar location',
    () {
      ReviewFrame frame(int t, double confidence) {
        final pose = List.generate(33, (_) => [.5, .5, .9]);
        pose[23] = [.4, .7, confidence];
        pose[24] = [.6, .7, confidence];
        return ReviewFrame(t, null, null, pose);
      }

      final path = poseMotionPath([
        frame(0, .9),
        frame(33, .2),
      ], MotionCatalog.squat);
      expect(path.first.x, .5);
      expect(path.first.y, .7);
      expect(path.last.valid, isFalse);
      expect(path.last.missingReason, 'pose_not_visible');
      expect(
        detectMotionReps([frame(0, .9), frame(33, .2)], MotionCatalog.squat),
        isEmpty,
      );
    },
  );

  test('pose-only candidates require a complete visible return', () {
    List<ReviewFrame> sequence(
      String id, {
      bool missingMiddle = false,
      bool partial = false,
    }) {
      final cycle = id == MotionCatalog.squat
          ? [.5, .56, .62, .68, .74, .8, .74, .68, .62, .56, .5]
          : [.8, .74, .68, .62, .56, .5, .56, .62, .68, .74, .8];
      final points = partial ? cycle.take(4).toList() : cycle;
      return [
        for (var i = 0; i < points.length; i++)
          ReviewFrame(i * 100, null, null, [
            for (var joint = 0; joint < 33; joint++)
              [.5, points[i], missingMiddle && i == 5 ? .1 : .95],
          ]),
      ];
    }

    for (final id in [
      MotionCatalog.squat,
      MotionCatalog.deadlift,
      MotionCatalog.pullUp,
    ]) {
      expect(detectMotionReps(sequence(id), id), hasLength(1));
      expect(detectMotionReps(sequence(id, partial: true), id), isEmpty);
      expect(detectMotionReps(sequence(id, missingMiddle: true), id), isEmpty);
    }
  });
}
