import 'motion_catalog.dart';
import 'video_review.dart';

/// A pose-only candidate path. Never labels a human landmark as a barbell.
List<ReviewFrame> poseMotionPath(List<ReviewFrame> frames, String motionId) {
  final ids = switch (motionId) {
    MotionCatalog.squat => [23, 24], // hips
    MotionCatalog.deadlift => [11, 12], // shoulders
    MotionCatalog.pullUp => [11, 12], // shoulders
    _ => <int>[],
  };
  if (ids.isEmpty) return const [];
  final invert = motionId != MotionCatalog.squat;
  return [for (final frame in frames) _posePoint(frame, ids, invert)];
}

List<ReviewFrame> poseDisplayPath(List<ReviewFrame> frames, String motionId) {
  final path = poseMotionPath(frames, motionId);
  if (motionId == MotionCatalog.squat) return path;
  return [
    for (final frame in path)
      ReviewFrame(
        frame.t,
        frame.x,
        frame.y == null ? null : 1 - frame.y!,
        frame.pose,
        frame.segment,
        frame.missingReason,
      ),
  ];
}

ReviewFrame _posePoint(ReviewFrame frame, List<int> ids, bool invert) {
  if (frame.pose.length <= ids.last ||
      ids.any((i) => frame.pose[i].length < 3 || frame.pose[i][2] < .7)) {
    return ReviewFrame(
      frame.t,
      null,
      null,
      frame.pose,
      frame.segment,
      'pose_not_visible',
    );
  }
  final x = (frame.pose[ids.first][0] + frame.pose[ids.last][0]) / 2;
  final y = (frame.pose[ids.first][1] + frame.pose[ids.last][1]) / 2;
  return ReviewFrame(frame.t, x, invert ? 1 - y : y, frame.pose, frame.segment);
}

/// Experimental candidates only. Manual review remains required.
List<ReviewRep> detectMotionReps(List<ReviewFrame> frames, String motionId) {
  if (motionId == MotionCatalog.bench) return detectReviewReps(frames);
  return detectReviewReps(poseMotionPath(frames, motionId));
}
