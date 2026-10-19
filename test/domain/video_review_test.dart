import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/domain/video_review.dart';

void main() {
  test('manual boundaries use milliseconds and reject overlap', () {
    const rep = ReviewRep(100, 1100, 1400, 2400);
    expect(rep.upSeconds, 1);
    expect(rep.pauseSeconds, .3);
    expect(validReviewReps([rep], 0, 2500), isTrue);
    expect(validReviewReps([rep, rep], 0, 5000), isFalse);
    expect(
      validReviewReps([const ReviewRep(0, 200, 100, 300)], 0, 400),
      isFalse,
    );
  });
  test('complete cycles counted; incomplete final ascent excluded', () {
    final f = <ReviewFrame>[];
    for (var cycle = 0; cycle < 2; cycle++) {
      for (var i = 0; i < 20; i++) {
        f.add(
          ReviewFrame(
            (cycle * 20 + i) * 100,
            .5,
            .2 + (i <= 10 ? i : 20 - i) * .03,
          ),
        );
      }
    }
    f.add(const ReviewFrame(4000, .5, .2));
    expect(detectReviewReps(f).length, 2);
    expect(detectReviewReps(f.where((p) => p.t < 3500).toList()).length, 1);
  });
  test('a missing observation invalidates metrics without filling a gap', () {
    final frames = [
      for (var i = 0; i <= 10; i++)
        ReviewFrame(i * 100, i == 5 ? null : .5, i == 5 ? null : .2 + i * .02),
    ];
    final metrics = reviewMetrics(frames, [const ReviewRep(0, 400, 600, 1000)]);
    expect(metrics.single.valid, isFalse);
    expect(metrics.single.relativeAmplitude, isNull);
  });
  test('long timestamp gap is missing data, even with valid endpoints', () {
    final frames = [
      const ReviewFrame(0, .5, .2),
      const ReviewFrame(100, .5, .5),
      const ReviewFrame(1000, .5, .2),
    ];
    expect(
      reviewMetrics(frames, [const ReviewRep(0, 100, 100, 1000)]).single.valid,
      isFalse,
    );
  });
  test(
    'amplitude uses median of valid repetitions, one rep has no comparison',
    () {
      final frames = <ReviewFrame>[];
      for (var j = 0; j < 2; j++) {
        for (var i = 0; i <= 10; i++) {
          frames.add(
            ReviewFrame(
              j * 1100 + i * 100,
              .5,
              .2 + (i <= 5 ? i : 10 - i) * (j + 1) * .02,
            ),
          );
        }
      }
      final reps = [
        const ReviewRep(0, 500, 500, 1000),
        const ReviewRep(1100, 1600, 1600, 2100),
      ];
      expect(
        reviewMetrics(frames, reps)[0].relativeAmplitude,
        closeTo(66.6667, .001),
      );
      expect(
        reviewMetrics(frames, [reps.first]).single.relativeAmplitude,
        isNull,
      );
    },
  );
  test(
    'elbow angle uses image aspect ratio and suppresses invisible joints',
    () {
      final pose = List.generate(33, (_) => [0.0, 0.0, 0.0]);
      pose[11] = [0, .5, 1];
      pose[13] = [.5, .5, 1];
      pose[15] = [.5, 0, 1];
      expect(
        reviewElbowAngle(ReviewFrame(0, .5, .5, pose), 640, 360),
        closeTo(90, .001),
      );
      pose[13][2] = .1;
      expect(reviewElbowAngle(ReviewFrame(0, .5, .5, pose), 640, 360), isNull);
    },
  );
}
