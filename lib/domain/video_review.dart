import 'dart:math' as math;

class ReviewFrame {
  final int t;
  final double? x, y;
  final List<List<double>> pose;
  final int segment;
  final String? missingReason;
  const ReviewFrame(
    this.t,
    this.x,
    this.y, [
    this.pose = const [],
    this.segment = 0,
    this.missingReason,
  ]);
  bool get valid =>
      x != null &&
      y != null &&
      x!.isFinite &&
      y!.isFinite &&
      x! >= 0 &&
      x! <= 1 &&
      y! >= 0 &&
      y! <= 1;
  factory ReviewFrame.fromJson(Map<String, dynamic> json) => ReviewFrame(
    (json['t'] as num).toInt(),
    (json['x'] as num?)?.toDouble(),
    (json['y'] as num?)?.toDouble(),
    [
      for (final p in json['pose'] as List? ?? [])
        [
          (p['x'] as num).toDouble(),
          (p['y'] as num).toDouble(),
          (p['v'] as num).toDouble(),
        ],
    ],
    (json['segment'] as num?)?.toInt() ?? 0,
    json['missingReason'] as String?,
  );
  Map<String, dynamic> toJson() => {
    't': t,
    'x': x,
    'y': y,
    'segment': segment,
    'missingReason': missingReason,
    'pose': [
      for (final p in pose) {'x': p[0], 'y': p[1], 'v': p[2]},
    ],
  };
}

class ReviewRep {
  final int startMs, bottomStartMs, bottomEndMs, endMs;
  const ReviewRep(
    this.startMs,
    this.bottomStartMs,
    this.bottomEndMs,
    this.endMs,
  );
  double get downSeconds => (bottomStartMs - startMs) / 1000;
  double get pauseSeconds => (bottomEndMs - bottomStartMs) / 1000;
  double get upSeconds => (endMs - bottomEndMs) / 1000;
  List<int> toJson() => [startMs, bottomStartMs, bottomEndMs, endMs];
  factory ReviewRep.fromJson(List<dynamic> values) => ReviewRep(
    (values[0] as num).toInt(),
    (values[1] as num).toInt(),
    (values[2] as num).toInt(),
    (values[3] as num).toInt(),
  );
}

bool validReviewReps(List<ReviewRep> reps, int start, int end) {
  var previous = start;
  for (final r in reps) {
    if (r.startMs < previous ||
        r.startMs >= r.bottomStartMs ||
        r.bottomStartMs > r.bottomEndMs ||
        r.bottomEndMs >= r.endMs ||
        r.endMs > end) {
      return false;
    }
    previous = r.endMs;
  }
  return true;
}

/// Conservative hysteresis on image y (down is positive), restarting after a gap.
/// Candidates remain user-correctable; unracking/racking is excluded by the chosen clip.
List<ReviewRep> detectReviewReps(List<ReviewFrame> frames) {
  final result = <ReviewRep>[];
  final good = frames.where((f) => f.valid).toList();
  if (good.length < 5) return result;
  final range =
      good.map((f) => f.y!).reduce(math.max) -
      good.map((f) => f.y!).reduce(math.min);
  final threshold = math.max(.015, range * .22);
  ReviewFrame? top, bottom, end;
  var rising = false;
  int? last;
  int? segment;
  for (final f in frames) {
    if (!f.valid ||
        (last != null &&
            (f.t - last > 250 || f.t <= last || f.segment != segment))) {
      top = bottom = end = null;
      rising = false;
    }
    last = f.t;
    segment = f.segment;
    if (!f.valid) continue;
    top ??= f;
    if (bottom == null) {
      if (f.y! < top.y!) top = f;
      if (f.y! - top.y! >= threshold) bottom = f;
    } else if (!rising) {
      if (f.y! > bottom.y!) bottom = f;
      if (bottom.y! - f.y! >= threshold) {
        rising = true;
        end = f;
      }
    } else {
      if (f.y! < end!.y!) end = f;
      if (f.y! - end.y! >= threshold) {
        if (bottom.y! - end.y! >= threshold &&
            end.t - top.t >= 400 &&
            end.y! <= top.y! + threshold * .5) {
          result.add(_repWithPause(frames, top, bottom, end));
        }
        top = end;
        bottom = f;
        end = null;
        rising = false;
      }
    }
  }
  if (rising &&
      top != null &&
      bottom != null &&
      end != null &&
      end.t - top.t >= 400 &&
      // A partial last ascent must not count as a complete repetition.
      end.y! <= top.y! + threshold * .5) {
    result.add(_repWithPause(frames, top, bottom, end));
  }
  return result;
}

ReviewRep _repWithPause(
  List<ReviewFrame> frames,
  ReviewFrame top,
  ReviewFrame bottom,
  ReviewFrame end,
) {
  final tolerance = math.max(.002, (bottom.y! - top.y!) * .03);
  final candidates = frames
      .where(
        (f) =>
            f.t >= top.t &&
            f.t <= end.t &&
            f.valid &&
            bottom.y! - f.y! <= tolerance,
      )
      .toList();
  var a = bottom.t, b = bottom.t;
  // Only the contiguous bottom neighborhood, not distant observations at similar height.
  final index = candidates.indexWhere((f) => f.t == bottom.t);
  if (index >= 0) {
    for (var i = index - 1; i >= 0 && a - candidates[i].t <= 150; i--) {
      a = candidates[i].t;
    }
    for (
      var i = index + 1;
      i < candidates.length && candidates[i].t - b <= 150;
      i++
    ) {
      b = candidates[i].t;
    }
  }
  if (b - a < 200) {
    a = bottom.t;
    b = bottom.t;
  }
  return ReviewRep(top.t, a, b, end.t);
}

class ReviewMetric {
  final bool valid;
  final double? relativeAmplitude;
  const ReviewMetric(this.valid, this.relativeAmplitude);
}

List<ReviewMetric> reviewMetrics(
  List<ReviewFrame> frames,
  List<ReviewRep> reps,
) {
  final spans = <double?>[];
  for (final rep in reps) {
    final part = frames
        .where((f) => f.t >= rep.startMs && f.t <= rep.endMs)
        .toList();
    var valid =
        part.length >= 3 &&
        part.first.t - rep.startMs <= 150 &&
        rep.endMs - part.last.t <= 150;
    for (var i = 0; i < part.length; i++) {
      if (!part[i].valid ||
          (i > 0 &&
              (part[i].t - part[i - 1].t > 250 ||
                  part[i].segment != part[i - 1].segment))) {
        valid = false;
      }
    }
    spans.add(
      valid
          ? part.map((f) => f.y!).reduce(math.max) -
                part.map((f) => f.y!).reduce(math.min)
          : null,
    );
  }
  final sorted = spans.whereType<double>().where((n) => n > .001).toList()
    ..sort();
  double? median;
  if (sorted.length > 1) {
    final mid = sorted.length ~/ 2;
    median = sorted.length.isOdd
        ? sorted[mid]
        : (sorted[mid - 1] + sorted[mid]) / 2;
  }
  return [
    for (final span in spans)
      ReviewMetric(
        span != null,
        span != null && median != null ? span / median * 100 : null,
      ),
  ];
}

double? reviewElbowAngle(ReviewFrame frame, double width, double height) {
  double? angle(List<int> ids) {
    if (frame.pose.length < 17 || ids.any((i) => frame.pose[i][2] < .7)) {
      return null;
    }
    final p = [
      for (final i in ids)
        [frame.pose[i][0] * width, frame.pose[i][1] * height],
    ];
    final ax = p[0][0] - p[1][0], ay = p[0][1] - p[1][1];
    final bx = p[2][0] - p[1][0], by = p[2][1] - p[1][1];
    final length = math.sqrt((ax * ax + ay * ay) * (bx * bx + by * by));
    return length < 1e-8
        ? null
        : math.acos(((ax * bx + ay * by) / length).clamp(-1, 1)) *
              180 /
              math.pi;
  }

  // If both sides are visible, use the side with higher minimum confidence.
  if (frame.pose.length < 17) return null;
  final left = [11, 13, 15].map((i) => frame.pose[i][2]).reduce(math.min);
  final right = [12, 14, 16].map((i) => frame.pose[i][2]).reduce(math.min);
  return angle(left >= right ? [11, 13, 15] : [12, 14, 16]);
}
