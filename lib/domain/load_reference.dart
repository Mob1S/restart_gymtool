import 'dart:math' as math;

import 'metrics.dart';
import 'training_prescription.dart';
import 'weight_value.dart';

class LoadObservation {
  final String sessionId, setId;
  final int at, reps;
  final EquipmentWeight reading;
  final Effort? effort;
  final bool warmup;
  final List<int> pattern;
  final int pauseSeconds;
  final int segmentIndex;
  final int? firstReps;
  const LoadObservation({
    required this.sessionId,
    required this.setId,
    required this.at,
    required this.reps,
    required this.reading,
    this.effort,
    this.warmup = false,
    this.pattern = const [],
    this.pauseSeconds = 0,
    this.segmentIndex = 0,
    this.firstReps,
  });
  String get evidence =>
      '${DateTime.fromMillisecondsSinceEpoch(at).toLocal().toIso8601String().substring(0, 10)} · ${pattern.isEmpty ? '' : '第 ${segmentIndex + 1} 段 · '}${reading.label} × $reps${pattern.isEmpty ? '' : ' · 模式 ${firstReps ?? reps}+${pattern.join('+')}'}${effort == null ? '' : ' @ ${effort!.label}'}';
}

class LoadReference {
  final EquipmentWeight? reading;
  final String message, trend, token;
  final List<String> evidence;
  const LoadReference({
    this.reading,
    required this.message,
    this.trend = '记录较少',
    this.evidence = const [],
    this.token = '',
  });
  LoadReference withToken(String value) => LoadReference(
    reading: reading,
    message: message,
    trend: trend,
    evidence: evidence,
    token: value,
  );
}

double _median(List<double> values) {
  final a = [...values]..sort();
  return a.length.isOdd
      ? a[a.length ~/ 2]
      : (a[a.length ~/ 2 - 1] + a[a.length ~/ 2]) / 2;
}

bool _effortSupports(Effort? actual, Effort? target) {
  if (actual == null) return false;
  if (target == null) return actual.reserveLowerBound != null;
  final ar = actual.reserveLowerBound;
  if (ar == null) return false;
  if (target.kind == 'rpe') {
    return (10 - ar) <= (target.maxValue ?? target.value);
  }
  return ar >= target.value;
}

LoadReference suggestLoad({
  required List<LoadObservation> history,
  required SetTarget target,
  required WeightUnit unit,
  required DecimalReading step,
  required int now,
  String loadMeaning = 'external',
  int segmentIndex = 0,
}) {
  if (loadMeaning != 'external') {
    final recent =
        history
            .where(
              (h) => !h.warmup && h.at <= now && h.at >= now - 90 * 86400000,
            )
            .toList()
          ..sort((a, b) => b.at.compareTo(a.at));
    return LoadReference(
      message: '自重或助力动作：参考同模式历史记录，自行选择负重／辅助量',
      evidence: recent.take(3).map((h) => h.evidence).toList(),
    );
  }
  if (target.role == 'warmup') {
    return const LoadReference(message: '热身组：根据当天状态自行选择重量');
  }
  final available =
      history
          .where(
            (h) =>
                h.at <= now &&
                h.at >= now - 90 * 86400000 &&
                !h.warmup &&
                h.reading.kilograms > 0 &&
                h.reps > 0,
          )
          .toList()
        ..sort((a, b) => b.at.compareTo(a.at));
  final candidates = <(LoadObservation, double, bool)>[];
  int? targetCapacity;
  if (target.loadKind == 'rm') {
    targetCapacity = target.loadValue!.toInt();
  } else if (target.loadKind == 'percent') {
    targetCapacity = 1;
  } else {
    targetCapacity =
        target.repsMin +
        (target.effort?.reserveLowerBound ??
            (target.effort?.kind == 'rir' ? target.effort!.value.toInt() : 0));
  }
  for (final h in available) {
    final known = h.effort?.reserveLowerBound;
    double? value;
    if (target.isRestPause) {
      if (h.segmentIndex == segmentIndex &&
          h.pattern.join(',') == target.extraReps.join(',') &&
          h.pauseSeconds == target.pauseSeconds &&
          (h.firstReps ?? h.reps) >= target.repsMin &&
          (h.firstReps ?? h.reps) <= target.repsMax) {
        value = h.reading.kilograms;
      }
    } else if (h.pattern.isEmpty) {
      if (target.loadKind == 'fixed') {
        value = EquipmentWeight(
          DecimalReading.parse(target.loadValue!.toString()),
          WeightUnit.values.byName(target.fixedUnit),
        ).kilograms;
      } else if (target.loadKind == 'rm' &&
          targetCapacity > 10 &&
          h.reps == targetCapacity &&
          known == 0) {
        value = h.reading.kilograms;
      } else if (targetCapacity <= 10 && h.reps + (known ?? 0) <= 10) {
        final proxy = estimateOneRepMax(
          h.reading.kilograms,
          h.reps + (known ?? 0),
        );
        if (proxy != null) {
          value = target.loadKind == 'percent'
              ? proxy * target.loadValue! / 100
              : proxy / estimateOneRepMax(1, targetCapacity)!;
        }
      } else if (h.reps >= target.repsMin &&
          h.reps <= target.repsMax &&
          (h.effort == null ||
              target.effort == null ||
              _effortSupports(h.effort, target.effort))) {
        if (target.loadKind != 'rm' ||
            (h.reps == target.loadValue && known == 0)) {
          value = h.reading.kilograms;
        }
      }
    }
    if (value != null && value.isFinite && value > 0) {
      candidates.add((h, value, known != null));
    }
  }
  if (candidates.isEmpty) {
    return const LoadReference(message: '暂无相近次数与强度的个人记录；先手动记录几次，再提供参考');
  }
  final calibrated = candidates.where((c) => c.$3).toList();
  final uncalibrated = candidates.where((c) => !c.$3).toList();
  final cohort =
      calibrated.map((c) => c.$1.sessionId).toSet().length >= 3 ||
          uncalibrated.isEmpty
      ? calibrated
      : uncalibrated;
  final bySession = <(LoadObservation, double, bool)>[];
  final grouped = <String, List<(LoadObservation, double, bool)>>{};
  for (final c in cohort) {
    (grouped[c.$1.sessionId] ??= []).add(c);
  }
  for (final bucket in grouped.values) {
    bucket.sort((a, b) => b.$2.compareTo(a.$2));
    bySession.add(bucket.first);
  }
  bySession.sort((a, b) => b.$1.at.compareTo(a.$1.at));
  final points = bySession.take(8).toList();
  final evidence = points.map((c) => c.$1.evidence).toList();
  if (now - points.first.$1.at > 28 * 86400000) {
    return LoadReference(message: '久未训练：以下是历史表现，请重新评估当前重量', evidence: evidence);
  }
  var candidate = _median(points.take(3).map((c) => c.$2).toList());
  var trend = points.length < 3 ? '记录较少' : '近期稳定';
  var increase = false;
  if (points.length >= 6) {
    final older = _median(points.skip(3).take(3).map((c) => c.$2).toList());
    final ratio = candidate / older;
    trend = ratio > 1.03
        ? '近期上升'
        : ratio < 0.97
        ? '近期回落'
        : '近期稳定';
    increase =
        !target.isRestPause &&
        ratio > 1.03 &&
        points
            .take(2)
            .every(
              (c) =>
                  c.$1.reps >= target.repsMax &&
                  _effortSupports(c.$1.effort, target.effort),
            );
  }
  final kgStep = step.asDouble * (unit == WeightUnit.lb ? 0.45359237 : 1);
  if (increase) {
    candidate = math.min(candidate + kgStep, points.first.$2 + kgStep);
  }
  final native = candidate / (unit == WeightUnit.lb ? 0.45359237 : 1);
  final sameUnit = available.where((h) => h.reading.unit == unit);
  final anchor = sameUnit.isEmpty
      ? DecimalReading.parse('0')
      : sameUnit.first.reading.amount;
  final steps = ((native - anchor.asDouble) / step.asDouble + 1e-9).floor();
  EquipmentWeight reading;
  try {
    reading = EquipmentWeight(anchor.plusSteps(step, steps), unit);
  } on ArgumentError {
    return LoadReference(message: '估算重量低于当前器械可用档位，请手动选择', evidence: evidence);
  }
  if (reading.kilograms <= 0) {
    return LoadReference(message: '当前档位下没有适用的参考重量', evidence: evidence);
  }
  return LoadReference(
    reading: reading,
    message:
        '${target.isRestPause
            ? '同分段模式历史参考'
            : points.first.$3
            ? '结合实际用力程度估算'
            : '基于已完成表现的保守参考，未按极限能力校准'}${increase ? '；可尝试提高一个档位' : ''}',
    trend: trend,
    evidence: evidence,
  );
}
