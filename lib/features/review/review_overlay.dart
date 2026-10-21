import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/video_review.dart';

class ReviewOverlay extends CustomPainter {
  final List<ReviewFrame> frames;
  final List<ReviewRep> reps;
  final int time;
  final bool trajectory, skeleton, compare;
  final List<Map<String, dynamic>> anchors;
  const ReviewOverlay({
    required this.frames,
    required this.reps,
    required this.time,
    required this.trajectory,
    required this.skeleton,
    required this.compare,
    required this.anchors,
  });
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    Offset position(ReviewFrame p) =>
        Offset(p.x! * size.width, p.y! * size.height);
    if (trajectory) {
      if (compare && reps.isNotEmpty) {
        for (var i = 0; i < reps.length; i++) {
          final part = frames
              .where((f) => f.t >= reps[i].startMs && f.t <= reps[i].endMs)
              .toList();
          final first = part.where((f) => f.valid).firstOrNull;
          if (first == null) continue;
          final offset =
              Offset(size.width * .5, size.height * .2) - position(first);
          paint.color = Colors.primaries[i % Colors.primaries.length];
          for (var j = 1; j < part.length; j++) {
            if (part[j].valid &&
                part[j - 1].valid &&
                part[j].segment == part[j - 1].segment &&
                part[j].t - part[j - 1].t <= 250) {
              canvas.drawLine(
                position(part[j - 1]) + offset,
                position(part[j]) + offset,
                paint,
              );
            }
          }
        }
      } else {
        for (var i = 1; i < frames.length; i++) {
          final a = frames[i - 1], b = frames[i];
          if (b.t > time ||
              !a.valid ||
              !b.valid ||
              b.t - a.t > 250 ||
              b.segment != a.segment) {
            continue;
          }
          paint.color = b.y! >= a.y! ? Colors.orangeAccent : Colors.cyanAccent;
          canvas.drawLine(position(a), position(b), paint);
        }
      }
    }
    ReviewFrame? nearest;
    for (final f in frames) {
      if (nearest == null || (f.t - time).abs() < (nearest.t - time).abs()) {
        nearest = f;
      }
    }
    if (skeleton && nearest != null && (nearest.t - time).abs() <= 100) {
      final pose = nearest.pose;
      paint.color = Colors.lightGreenAccent;
      for (final edge in [
        [11, 13],
        [13, 15],
        [12, 14],
        [14, 16],
        [11, 12],
        [11, 23],
        [12, 24],
        [23, 24],
      ]) {
        if (pose.length <= edge[1] ||
            pose[edge[0]][2] < .7 ||
            pose[edge[1]][2] < .7) {
          continue;
        }
        Offset point(int i) =>
            Offset(pose[i][0] * size.width, pose[i][1] * size.height);
        canvas.drawLine(point(edge[0]), point(edge[1]), paint);
        canvas.drawCircle(point(edge[0]), 3, paint);
        canvas.drawCircle(point(edge[1]), 3, paint);
      }
    }
    if (nearest != null && nearest.valid && (nearest.t - time).abs() <= 100) {
      paint.color = Colors.yellowAccent;
      canvas.drawCircle(position(nearest), 5, paint);
      final anchor = anchors.where((a) => (a['t'] as num) <= time).lastOrNull;
      if (anchor != null) {
        canvas.drawCircle(
          position(nearest),
          (anchor['radius'] as num).toDouble() *
              math.min(size.width, size.height),
          paint,
        );
      }
    }
    for (final anchor in anchors) {
      if (((anchor['t'] as num).toInt() - time).abs() > 100) continue;
      final center = Offset(
        (anchor['x'] as num).toDouble() * size.width,
        (anchor['y'] as num).toDouble() * size.height,
      );
      paint.color = Colors.yellowAccent;
      canvas.drawCircle(
        center,
        (anchor['radius'] as num).toDouble() *
            math.min(size.width, size.height),
        paint,
      );
      canvas.drawLine(
        center - const Offset(8, 0),
        center + const Offset(8, 0),
        paint,
      );
      canvas.drawLine(
        center - const Offset(0, 8),
        center + const Offset(0, 8),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant ReviewOverlay oldDelegate) => true;
}
