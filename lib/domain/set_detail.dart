import 'dart:convert';

import 'prescription_codec.dart';
import 'training_prescription.dart';
import 'weight_value.dart';

class RecordedSegment {
  final EquipmentWeight reading;
  final int reps, completedAt, pauseSeconds;
  final Effort? effort;
  const RecordedSegment({
    required this.reading,
    required this.reps,
    required this.completedAt,
    this.pauseSeconds = 0,
    this.effort,
  });
  Map<String, Object?> toJson() => {
    'weight': reading.amount.text,
    'unit': reading.unit.name,
    'reps': reps,
    'completedAt': completedAt,
    'pauseSeconds': pauseSeconds,
    'effort': effort?.toJson(),
  };
  factory RecordedSegment.fromJson(Object? input) {
    final m = checkedObject(input, {
      'weight',
      'unit',
      'reps',
      'completedAt',
      'pauseSeconds',
      'effort',
    });
    final unit = checkedText(m['unit']);
    if (!{'kg', 'lb'}.contains(unit)) throw const FormatException('分段重量单位无效');
    return RecordedSegment(
      reading: EquipmentWeight(
        DecimalReading.parse(checkedText(m['weight'])),
        WeightUnit.values.byName(unit),
      ),
      reps: checkedInt(m['reps']),
      completedAt: checkedInt(m['completedAt']),
      pauseSeconds: checkedInt(m['pauseSeconds']),
      effort: m['effort'] == null ? null : Effort.fromJson(m['effort']),
    );
  }
}

class SetDetail {
  final String role;
  final Effort? effort;
  final SetTarget? target;
  final int? targetIndex,
      firstCompletedAt,
      intraRestStartedAt,
      segmentStartedAt;
  final List<RecordedSegment> continuations;
  final bool endedEarly;
  final String? reference;
  final EquipmentWeight? pendingReading;
  SetDetail({
    this.role = 'unknown',
    this.effort,
    this.target,
    this.targetIndex,
    this.firstCompletedAt,
    this.intraRestStartedAt,
    this.segmentStartedAt,
    List<RecordedSegment> continuations = const [],
    this.endedEarly = false,
    this.reference,
    this.pendingReading,
  }) : continuations = List.unmodifiable(continuations);
  bool get isRestPause =>
      target?.isRestPause == true || continuations.isNotEmpty;
  int get currentSegment =>
      !isRestPause || firstCompletedAt == null ? 0 : continuations.length + 1;
  double get extraVolume =>
      continuations.fold(0, (n, s) => n + s.reading.kilograms * s.reps);
  String get segmentLabel => continuations
      .map(
        (s) =>
            '休息 ${s.pauseSeconds} 秒 → ${s.reading.label} × ${s.reps}${s.effort == null ? '' : ' @ ${s.effort!.label}'}',
      )
      .join(' + ');
  Map<String, Object?> toJson() => {
    'version': 1,
    'role': role,
    'effort': effort?.toJson(),
    'target': target?.toJson(),
    'targetIndex': targetIndex,
    'firstCompletedAt': firstCompletedAt,
    'intraRestStartedAt': intraRestStartedAt,
    'segmentStartedAt': segmentStartedAt,
    'continuations': continuations.map((s) => s.toJson()).toList(),
    'endedEarly': endedEarly,
    'reference': reference,
    'pendingWeight': pendingReading?.amount.text,
    'pendingUnit': pendingReading?.unit.name,
  };
  String encode() => jsonEncode(toJson());
  SetDetail copyWith({
    Effort? effort,
    bool clearEffort = false,
    int? firstCompletedAt,
    int? intraRestStartedAt,
    bool clearRest = false,
    int? segmentStartedAt,
    bool clearSegmentStart = false,
    List<RecordedSegment>? continuations,
    bool? endedEarly,
    String? reference,
    EquipmentWeight? pendingReading,
    bool clearPending = false,
  }) => SetDetail(
    role: role,
    effort: clearEffort ? null : effort ?? this.effort,
    target: target,
    targetIndex: targetIndex,
    firstCompletedAt: firstCompletedAt ?? this.firstCompletedAt,
    intraRestStartedAt: clearRest
        ? null
        : intraRestStartedAt ?? this.intraRestStartedAt,
    segmentStartedAt: clearSegmentStart
        ? null
        : segmentStartedAt ?? this.segmentStartedAt,
    continuations: continuations ?? this.continuations,
    endedEarly: endedEarly ?? this.endedEarly,
    reference: reference ?? this.reference,
    pendingReading: clearPending ? null : pendingReading ?? this.pendingReading,
  );
  factory SetDetail.decode(String value) =>
      SetDetail.fromJson(decodeTrainingJson(value));
  factory SetDetail.fromJson(Object? input) {
    final m = checkedObject(input, {
      'version',
      'role',
      'effort',
      'target',
      'targetIndex',
      'firstCompletedAt',
      'intraRestStartedAt',
      'segmentStartedAt',
      'continuations',
      'endedEarly',
      'reference',
      'pendingWeight',
      'pendingUnit',
    });
    if (m['version'] != 1 ||
        !{'unknown', 'work', 'warmup'}.contains(m['role'])) {
      throw const FormatException('实际组详情无效');
    }
    if ((m['pendingWeight'] == null) != (m['pendingUnit'] == null) ||
        (m['pendingUnit'] != null &&
            !{'kg', 'lb'}.contains(m['pendingUnit']))) {
      throw const FormatException('待记分段重量无效');
    }
    final d = SetDetail(
      role: checkedText(m['role']),
      effort: m['effort'] == null ? null : Effort.fromJson(m['effort']),
      target: m['target'] == null ? null : SetTarget.fromJson(m['target']),
      targetIndex: m['targetIndex'] == null
          ? null
          : checkedInt(m['targetIndex']),
      firstCompletedAt: m['firstCompletedAt'] == null
          ? null
          : checkedInt(m['firstCompletedAt']),
      intraRestStartedAt: m['intraRestStartedAt'] == null
          ? null
          : checkedInt(m['intraRestStartedAt']),
      segmentStartedAt: m['segmentStartedAt'] == null
          ? null
          : checkedInt(m['segmentStartedAt']),
      continuations: checkedList(
        m['continuations'],
        max: 10,
      ).map(RecordedSegment.fromJson).toList(),
      endedEarly: checkedBool(m['endedEarly']),
      reference: m['reference'] == null ? null : checkedText(m['reference']),
      pendingReading: m['pendingWeight'] == null
          ? null
          : EquipmentWeight(
              DecimalReading.parse(checkedText(m['pendingWeight'])),
              WeightUnit.values.byName(m['pendingUnit'] as String),
            ),
    );
    if (d.continuations.isNotEmpty && d.firstCompletedAt == null) {
      throw const FormatException('后续段缺少首段完成时间');
    }
    if ((d.firstCompletedAt != null ||
            d.pendingReading != null ||
            d.intraRestStartedAt != null ||
            d.endedEarly) &&
        d.target?.isRestPause != true) {
      throw const FormatException('组内记录缺少分段目标');
    }
    if (d.firstCompletedAt == null &&
        (d.intraRestStartedAt != null ||
            d.pendingReading != null ||
            d.endedEarly)) {
      throw const FormatException('组内状态缺少已完成首段');
    }
    if (d.target != null &&
        d.continuations.length > d.target!.extraReps.length) {
      throw const FormatException('分段超出计划组结构');
    }
    if (d.endedEarly &&
        (d.pendingReading != null ||
            d.intraRestStartedAt != null ||
            d.segmentStartedAt != null)) {
      throw const FormatException('已结束组不能保留待记段');
    }
    if (d.segmentStartedAt != null &&
        (d.firstCompletedAt == null ||
            d.intraRestStartedAt != null ||
            d.segmentStartedAt! <
                (d.continuations.lastOrNull?.completedAt ??
                    d.firstCompletedAt!))) {
      throw const FormatException('分段开始状态无效');
    }
    var previous = d.firstCompletedAt ?? 0;
    for (final segment in d.continuations) {
      if (segment.completedAt < previous) {
        throw const FormatException('分段完成时间顺序无效');
      }
      previous = segment.completedAt;
    }
    if (d.intraRestStartedAt != null && d.intraRestStartedAt! < previous) {
      throw const FormatException('组内休息早于已完成段');
    }
    if (d.effort?.maxValue != null ||
        d.continuations.any((s) => s.effort?.maxValue != null)) {
      throw const FormatException('实际用力程度不能是目标范围');
    }
    return d;
  }
}
