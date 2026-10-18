import 'dart:convert';

import 'prescription_codec.dart';

class Effort {
  final String kind, bound;
  final double value;
  final double? maxValue;
  const Effort(this.kind, this.value, {this.maxValue, this.bound = 'exact'});
  void validate() {
    if (!{'rpe', 'rir'}.contains(kind) ||
        !{'exact', 'below', 'above'}.contains(bound) ||
        !value.isFinite ||
        value < 0 ||
        value > 10 ||
        (maxValue != null &&
            (!maxValue!.isFinite || maxValue! < value || maxValue! > 10))) {
      throw const FormatException('RPE/RIR 无效');
    }
    if (kind == 'rpe' &&
        (value < 6 ||
            value * 2 % 1 != 0 ||
            (maxValue != null && maxValue! * 2 % 1 != 0) ||
            bound == 'above' ||
            (bound == 'below' && value != 6))) {
      throw const FormatException('RPE 应为 6–10 的半级或低于 6');
    }
    if (kind == 'rir' &&
        (value % 1 != 0 ||
            (maxValue != null && maxValue! % 1 != 0) ||
            bound == 'below' ||
            (bound == 'above' && value != 10))) {
      throw const FormatException('RIR 应为整数');
    }
    if (bound != 'exact' && maxValue != null) {
      throw const FormatException('开放边界不能同时指定范围');
    }
  }

  int? get reserveLowerBound {
    if (bound != 'exact' || maxValue != null) return null;
    return kind == 'rpe' && value >= 7
        ? (10 - value).floor()
        : kind == 'rir' && value <= 3
        ? value.toInt()
        : null;
  }

  String get label =>
      '${kind.toUpperCase()} ${bound == 'below'
          ? '<'
          : bound == 'above'
          ? '>'
          : ''}${_n(value)}${maxValue == null ? '' : '–${_n(maxValue!)}'}';
  String get explanation {
    if (kind == 'rir') {
      return '大约还能完成 ${bound == 'above' ? '超过 ' : ''}${_n(value)} 次';
    }
    if (bound == 'below' || value <= 6) return '较轻松，通常还有至少 4 次余力';
    final remaining = 10 - value;
    return remaining % 1 == 0
        ? '大约还能完成 ${_n(remaining)} 次'
        : '大约还有 ${remaining.floor()}–${remaining.ceil()} 次余力';
  }

  Map<String, Object?> toJson() => {
    'kind': kind,
    'value': value,
    'maxValue': maxValue,
    'bound': bound,
  };
  factory Effort.fromJson(Object? input) {
    final m = checkedObject(input, {'kind', 'value', 'maxValue', 'bound'});
    if (m['value'] is! num ||
        (m['maxValue'] != null && m['maxValue'] is! num)) {
      throw const FormatException('强度数值无效');
    }
    final e = Effort(
      checkedText(m['kind'], empty: false),
      (m['value'] as num).toDouble(),
      maxValue: (m['maxValue'] as num?)?.toDouble(),
      bound: checkedText(m['bound'], empty: false),
    );
    e.validate();
    return e;
  }
}

String _n(num value) =>
    value % 1 == 0 ? value.toInt().toString() : value.toString();

class SetTarget {
  final int repsMin, repsMax, pauseSeconds;
  final String role, loadKind, fixedUnit, note;
  final double? loadValue;
  final Effort? effort;
  final bool optional;
  final List<int> extraReps;
  SetTarget({
    required this.repsMin,
    required this.repsMax,
    this.role = 'work',
    this.effort,
    this.loadKind = 'none',
    this.loadValue,
    this.fixedUnit = 'kg',
    this.note = '',
    this.optional = false,
    List<int> extraReps = const [],
    this.pauseSeconds = 0,
  }) : extraReps = List.unmodifiable(extraReps);
  List<int> get segmentReps => [repsMin, ...extraReps];
  bool get isRestPause => extraReps.isNotEmpty;
  void validate() {
    checkedInt(repsMin, min: 1, max: 10000);
    checkedInt(repsMax, min: repsMin, max: 10000);
    if (!{'work', 'warmup'}.contains(role) ||
        !{'none', 'rm', 'percent', 'fixed'}.contains(loadKind) ||
        !{'kg', 'lb'}.contains(fixedUnit)) {
      throw const FormatException('组目标类型无效');
    }
    if (extraReps.length > 10 ||
        pauseSeconds < 0 ||
        pauseSeconds > 3600 ||
        (extraReps.isNotEmpty && pauseSeconds < 1)) {
      throw const FormatException('组内停顿无效');
    }
    for (final n in extraReps) {
      checkedInt(n, min: 1, max: 10000);
    }
    if (loadKind != 'none' &&
        (loadValue == null ||
            !loadValue!.isFinite ||
            loadValue! <= 0 ||
            (loadKind == 'rm' && (loadValue! % 1 != 0 || loadValue! > 100)) ||
            (loadKind == 'percent' && loadValue! > 100))) {
      throw const FormatException('目标负荷无效');
    }
    if (loadKind == 'none' && loadValue != null) {
      throw const FormatException('未指定负荷时不能填写数值');
    }
    checkedText(note);
    effort?.validate();
  }

  String get label {
    final reps = repsMin == repsMax ? '$repsMin' : '$repsMin–$repsMax';
    final parts = <String>[
      if (role == 'warmup') '热身',
      '$reps REP',
      for (final n in extraReps) '休息 $pauseSeconds 秒 + $n REP',
      if (effort != null) '@ ${effort!.label}',
      if (loadKind == 'rm') '${_n(loadValue!)}RM',
      if (loadKind == 'percent') '${_n(loadValue!)}% 1RM',
      if (loadKind == 'fixed') '${_n(loadValue!)} $fixedUnit',
      if (optional) '可选',
    ];
    return parts.join(' · ');
  }

  Map<String, Object?> toJson() => {
    'repsMin': repsMin,
    'repsMax': repsMax,
    'role': role,
    'effort': effort?.toJson(),
    'loadKind': loadKind,
    'loadValue': loadValue,
    'fixedUnit': fixedUnit,
    'note': note,
    'optional': optional,
    'extraReps': extraReps,
    'pauseSeconds': pauseSeconds,
  };
  factory SetTarget.fromJson(Object? input) {
    final m = checkedObject(input, {
      'repsMin',
      'repsMax',
      'role',
      'effort',
      'loadKind',
      'loadValue',
      'fixedUnit',
      'note',
      'optional',
      'extraReps',
      'pauseSeconds',
    });
    if (m['loadValue'] != null && m['loadValue'] is! num) {
      throw const FormatException('负荷数值无效');
    }
    final t = SetTarget(
      repsMin: checkedInt(m['repsMin']),
      repsMax: checkedInt(m['repsMax']),
      role: checkedText(m['role']),
      effort: m['effort'] == null ? null : Effort.fromJson(m['effort']),
      loadKind: checkedText(m['loadKind']),
      loadValue: (m['loadValue'] as num?)?.toDouble(),
      fixedUnit: checkedText(m['fixedUnit']),
      note: checkedText(m['note']),
      optional: checkedBool(m['optional']),
      extraReps: checkedList(
        m['extraReps'],
        max: 10,
      ).map((v) => checkedInt(v)).toList(),
      pauseSeconds: checkedInt(m['pauseSeconds']),
    );
    t.validate();
    return t;
  }
}

class ProgramStage {
  final String id, name;
  final Map<String, List<SetTarget>> targets;
  ProgramStage({
    required this.id,
    required this.name,
    required Map<String, List<SetTarget>> targets,
  }) : targets = Map.unmodifiable(
         targets.map((k, v) => MapEntry(k, List<SetTarget>.unmodifiable(v))),
       );
  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'targets': targets.map(
      (k, v) => MapEntry(k, v.map((t) => t.toJson()).toList()),
    ),
  };
  factory ProgramStage.fromJson(Object? input) {
    final m = checkedObject(input, {'id', 'name', 'targets'});
    if (m['targets'] is! Map) throw const FormatException('阶段目标无效');
    final targets = <String, List<SetTarget>>{};
    for (final entry in (m['targets'] as Map).entries) {
      final id = checkedText(entry.key, empty: false);
      targets[id] = checkedList(
        entry.value,
        max: 1000,
      ).map(SetTarget.fromJson).toList();
    }
    return ProgramStage(
      id: checkedText(m['id'], empty: false),
      name: checkedText(m['name'], empty: false),
      targets: targets,
    );
  }
}

class TrainingProgram {
  final String currentStageId, sourceTitle, sourceUrl, notes, templateKey;
  final List<ProgramStage> stages;
  TrainingProgram({
    required List<ProgramStage> stages,
    required this.currentStageId,
    this.sourceTitle = '',
    this.sourceUrl = '',
    this.notes = '',
    this.templateKey = '',
  }) : stages = List.unmodifiable(stages);
  ProgramStage get current => stages.firstWhere((s) => s.id == currentStageId);
  int get recordCount => stages.fold(
    0,
    (n, s) =>
        n +
        1 +
        s.targets.values.fold<int>(
          0,
          (v, ts) => v + ts.fold<int>(0, (k, t) => k + 1 + t.extraReps.length),
        ),
  );
  TrainingProgram select(String id) => TrainingProgram(
    stages: stages,
    currentStageId: id,
    sourceTitle: sourceTitle,
    sourceUrl: sourceUrl,
    notes: notes,
    templateKey: templateKey,
  );
  TrainingProgram prune(Set<String> ids) => TrainingProgram(
    stages: [
      for (final s in stages)
        ProgramStage(
          id: s.id,
          name: s.name,
          targets: {
            for (final e in s.targets.entries)
              if (ids.contains(e.key)) e.key: e.value,
          },
        ),
    ],
    currentStageId: currentStageId,
    sourceTitle: sourceTitle,
    sourceUrl: sourceUrl,
    notes: notes,
    templateKey: templateKey,
  );
  Map<String, Object?> toJson() => {
    'version': 1,
    'currentStageId': currentStageId,
    'sourceTitle': sourceTitle,
    'sourceUrl': sourceUrl,
    'notes': notes,
    'templateKey': templateKey,
    'stages': stages.map((s) => s.toJson()).toList(),
  };
  String encode() => jsonEncode(toJson());
  factory TrainingProgram.decode(String text) =>
      TrainingProgram.fromJson(decodeTrainingJson(text));
  factory TrainingProgram.fromJson(Object? input) {
    final m = checkedObject(input, {
      'version',
      'currentStageId',
      'sourceTitle',
      'sourceUrl',
      'notes',
      'templateKey',
      'stages',
    });
    if (m['version'] != 1) throw const FormatException('计划处方版本不受支持');
    final p = TrainingProgram(
      stages: checkedList(
        m['stages'],
        max: 1000,
      ).map(ProgramStage.fromJson).toList(),
      currentStageId: checkedText(m['currentStageId'], empty: false),
      sourceTitle: checkedText(m['sourceTitle']),
      sourceUrl: checkedText(m['sourceUrl']),
      notes: checkedText(m['notes']),
      templateKey: checkedText(m['templateKey']),
    );
    final ids = p.stages.map((s) => s.id).toSet();
    if (ids.length != p.stages.length ||
        !ids.contains(p.currentStageId) ||
        p.recordCount > 100000) {
      throw const FormatException('阶段或目标数量无效');
    }
    return p;
  }
}

class SessionPrescription {
  final String stageId, stageName, planName, dayName;
  final List<SetTarget> targets;
  SessionPrescription({
    required this.stageId,
    required this.stageName,
    required this.planName,
    required this.dayName,
    required List<SetTarget> targets,
  }) : targets = List.unmodifiable(targets);
  Map<String, Object?> toJson() => {
    'version': 1,
    'stageId': stageId,
    'stageName': stageName,
    'planName': planName,
    'dayName': dayName,
    'targets': targets.map((t) => t.toJson()).toList(),
  };
  String encode() => jsonEncode(toJson());
  factory SessionPrescription.decode(String text) {
    final m = checkedObject(decodeTrainingJson(text), {
      'version',
      'stageId',
      'stageName',
      'planName',
      'dayName',
      'targets',
    });
    if (m['version'] != 1) throw const FormatException('训练目标快照版本无效');
    return SessionPrescription(
      stageId: checkedText(m['stageId'], empty: false),
      stageName: checkedText(m['stageName'], empty: false),
      planName: checkedText(m['planName']),
      dayName: checkedText(m['dayName']),
      targets: checkedList(
        m['targets'],
        max: 1000,
      ).map(SetTarget.fromJson).toList(),
    );
  }
}
