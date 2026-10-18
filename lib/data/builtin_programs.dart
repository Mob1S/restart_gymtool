import '../domain/training_prescription.dart';

class BuiltinExercise {
  final String name, equipment;
  final List<List<SetTarget>> progression;
  BuiltinExercise(this.name, this.equipment, this.progression);
  String get key => '$name|$equipment';
  List<SetTarget> at(int stage) =>
      progression[stage < progression.length ? stage : progression.length - 1];
}

class BuiltinDay {
  final String name;
  final List<BuiltinExercise> exercises;
  const BuiltinDay(this.name, this.exercises);
  bool get rest => exercises.isEmpty;
}

class BuiltinProgram {
  final String key, name, sourceUrl, sourceTitle, notes;
  final List<BuiltinDay> days;
  final List<String> stages;
  BuiltinProgram({
    required this.key,
    required this.name,
    required this.sourceUrl,
    required this.sourceTitle,
    required this.notes,
    required this.days,
    this.stages = const ['基础阶段'],
  });
}

List<SetTarget> _sets(
  int count,
  int reps, {
  int? maxReps,
  int? maxSets,
  Effort? effort,
  List<int> extra = const [],
  String note = '',
}) => [
  for (var i = 0; i < (maxSets ?? count); i++)
    SetTarget(
      repsMin: reps,
      repsMax: maxReps ?? reps,
      effort: effort,
      optional: i >= count,
      extraReps: extra,
      pauseSeconds: extra.isEmpty ? 0 : 5,
      note: note,
    ),
];
BuiltinExercise _e(
  String name,
  String equipment,
  int sets,
  int reps, {
  int? maxReps,
  int? maxSets,
  Effort? effort,
  List<int> extra = const [],
  String note = '',
}) => BuiltinExercise(name, equipment, [
  _sets(
    sets,
    reps,
    maxReps: maxReps,
    maxSets: maxSets,
    effort: effort,
    extra: extra,
    note: note,
  ),
]);
List<BuiltinProgram> get builtinPrograms {
  const r8 = Effort('rpe', 8),
      r9 = Effort('rpe', 9),
      fail = Effort('rpe', 10),
      phul = Effort('rir', 1, maxValue: 10);
  final a = BuiltinDay('A · 全身', [
    _e('深蹲', '杠铃', 5, 5),
    _e('卧推', '杠铃', 5, 5),
    _e('杠铃划船', '杠铃', 5, 5),
  ]);
  final b = BuiltinDay('B · 全身', [
    _e('深蹲', '杠铃', 5, 5),
    _e('站姿推举', '杠铃', 5, 5),
    _e('硬拉', '杠铃', 1, 5),
  ]);
  const rest = BuiltinDay('休息', []);
  final benchReps = [
    [15, 12, 10, 8],
    [15, 12, 8, 8],
    [15, 8, 8, 8],
    [15, 8, 8, 8, 8],
    [15, 8, 8, 8, 8],
    [15, 6, 6],
    [15, 6, 6, 6],
    [15, 6, 6, 6, 6],
    [15, 5, 5],
    [15, 5, 5, 5],
    [15, 5, 5, 5, 5],
  ];
  final skullReps = [
    [15, 15, 15, 15],
    [15, 15, 15, 12],
    [15, 15, 12, 12],
    [15, 12, 12, 12],
    [12, 12, 12, 12],
    [12, 12, 12, 12],
    [12, 12, 12, 12],
  ];
  final push = BuiltinDay('推 · 胸肩三头', [
    BuiltinExercise('卧推', '杠铃', [
      for (final rs in benchReps)
        [
          for (var i = 0; i < rs.length; i++)
            SetTarget(
              repsMin: rs[i],
              repsMax: rs[i],
              role: i == 0 ? 'warmup' : 'work',
              effort: r8,
            ),
        ],
    ]),
    BuiltinExercise('哑铃上斜卧推', '哑铃', [
      _sets(4, 12, effort: r8),
      [..._sets(3, 12, effort: r8), ..._sets(1, 12, effort: r9)],
      [
        ..._sets(2, 12, effort: r8),
        ..._sets(2, 12, effort: const Effort('rpe', 9, maxValue: 9.5)),
      ],
    ]),
    _e('双杠臂屈伸', '自重', 4, 12, note: '可做到力竭，可在动作匹配中选择辅助器械版本'),
    BuiltinExercise('仰卧臂屈伸', '杠铃', [
      for (var w = 0; w < skullReps.length; w++)
        [
          for (var i = 0; i < 4; i++)
            SetTarget(
              repsMin: skullReps[w][i],
              repsMax: skullReps[w][i],
              effort: w >= 5 && i == 3 ? r9 : r8,
            ),
        ],
    ]),
    _e(
      '绳索 Y 字侧平举',
      '绳索',
      3,
      10,
      extra: [10],
      note: '10 次后休息 5 秒，再做 10 次，可做到力竭',
    ),
  ]);
  final pull = BuiltinDay('拉 · 背肩后二头', [
    BuiltinExercise('单臂绳索下拉', '绳索', [
      [
        ..._sets(2, 12, effort: r8),
        ..._sets(2, 10, effort: fail, extra: [5]),
      ],
    ]),
    _e('对握高位下拉', '器械', 4, 8, maxReps: 12, effort: r8),
    BuiltinExercise('单臂器械划船', '器械', [
      [
        ..._sets(2, 12, effort: r8),
        ..._sets(2, 10, effort: fail, extra: [5]),
      ],
    ]),
    _e('坐姿绳索开肘划船', '绳索', 4, 12, maxReps: 15, effort: r8),
    _e('绳索弯举', '绳索', 3, 12, effort: r8),
  ]);
  final legs = BuiltinDay('腿 · 股四腘绳臀', [
    _e('哑铃单腿硬拉', '哑铃', 4, 12, effort: r8),
    _e('保加利亚分腿蹲', '哑铃', 4, 10, effort: r8),
    _e('高脚杯深蹲', '哑铃', 3, 15, effort: r8),
    _e('罗马尼亚硬拉', '杠铃', 3, 12, effort: r8),
    _e('山羊挺身', '自重', 3, 8, effort: r8),
  ]);
  return [
    BuiltinProgram(
      key: 'kaitan-reference-v1',
      name: '凯谭三分化 · 整理参考版',
      sourceUrl: 'https://www.bilibili.com/video/BV1FcdZBNEm3/',
      sourceTitle: '凯圣王 × 谭成义原始系列及用户提供的整理表',
      notes: '参考整理版，可编辑。阶段由你推进，可延长当前阶段。卧推首组为热身；上斜第三周按4组整理为前2组RPE8、后2组RPE9–9.5；Y字侧平举采用3组10+10，中间休息5秒。腿日采用原作者简介的高脚杯深蹲，颈前深蹲是另一动作。拉日按基础表；较短进阶结束后保持末项。默认推拉腿休为应用起始安排。Y字侧平举默认绳索，可改哑铃版本；开肘划船可改海豹划船。单侧动作按每侧次数记录。以上整理约定不标作原作者定稿。',
      days: [push, pull, legs, rest],
      stages: [for (var i = 1; i <= 11; i++) '第 $i 周'],
    ),
    BuiltinProgram(
      key: 'stronglifts-5x5-v1',
      name: 'StrongLifts 5×5',
      sourceUrl: 'https://stronglifts.com/stronglifts-5x5/workout-program/',
      sourceTitle: 'StrongLifts 官方训练计划',
      notes:
          '两周六练，A/B交替。训练之间休息；14天周期不绑定开始星期。逐步加重是原计划思路，应用不会自动替你改重量。漏练的训练日继续等待完成。',
      days: [a, rest, b, rest, a, rest, rest, b, rest, a, rest, b, rest, rest],
    ),
    BuiltinProgram(
      key: 'phul-v1',
      name: 'PHUL · 上下肢四日',
      sourceUrl: 'https://www.muscleandstrength.com/workouts/phul-workout',
      sourceTitle: 'Brandon Campbell · Power Hypertrophy Upper Lower',
      notes: '原文面向中级训练者。保留组数/次数范围，额外组可选；至少保留1次余力。所有实际重量仍需自行选择或点击采用参考。',
      days: [
        BuiltinDay('上肢力量', [
          _e('卧推', '杠铃', 3, 3, maxSets: 4, maxReps: 5, effort: phul),
          _e('哑铃上斜卧推', '哑铃', 3, 6, maxSets: 4, maxReps: 10, effort: phul),
          _e('杠铃划船', '杠铃', 3, 3, maxSets: 4, maxReps: 5, effort: phul),
          _e('高位下拉', '器械', 3, 6, maxSets: 4, maxReps: 10, effort: phul),
          _e('站姿推举', '杠铃', 2, 5, maxSets: 3, maxReps: 8, effort: phul),
          _e('杠铃弯举', '杠铃', 2, 6, maxSets: 3, maxReps: 10, effort: phul),
          _e('仰卧臂屈伸', '杠铃', 2, 6, maxSets: 3, maxReps: 10, effort: phul),
        ]),
        BuiltinDay('下肢力量', [
          _e('深蹲', '杠铃', 3, 3, maxSets: 4, maxReps: 5, effort: phul),
          _e('硬拉', '杠铃', 3, 3, maxSets: 4, maxReps: 5, effort: phul),
          _e('腿举', '器械', 3, 10, maxSets: 5, maxReps: 15, effort: phul),
          _e('腿弯举', '器械', 3, 6, maxSets: 4, maxReps: 10, effort: phul),
          _e('站姿提踵', '器械', 4, 6, maxReps: 10, effort: phul),
        ]),
        rest,
        BuiltinDay('上肢增肌', [
          _e('上斜卧推', '杠铃', 3, 8, maxSets: 4, maxReps: 12, effort: phul),
          _e('哑铃飞鸟', '哑铃', 3, 8, maxSets: 4, maxReps: 12, effort: phul),
          _e('坐姿绳索划船', '绳索', 3, 8, maxSets: 4, maxReps: 12, effort: phul),
          _e('哑铃单臂划船', '哑铃', 3, 8, maxSets: 4, maxReps: 12, effort: phul),
          _e('侧平举', '哑铃', 3, 8, maxSets: 4, maxReps: 12, effort: phul),
          _e('坐姿上斜哑铃弯举', '哑铃', 3, 8, maxSets: 4, maxReps: 12, effort: phul),
          _e('绳索下压', '绳索', 3, 8, maxSets: 4, maxReps: 12, effort: phul),
        ]),
        BuiltinDay('下肢增肌', [
          _e('前蹲', '杠铃', 3, 8, maxSets: 4, maxReps: 12, effort: phul),
          _e('杠铃箭步蹲', '杠铃', 3, 8, maxSets: 4, maxReps: 12, effort: phul),
          _e('腿屈伸', '器械', 3, 10, maxSets: 4, maxReps: 15, effort: phul),
          _e('腿弯举', '器械', 3, 10, maxSets: 4, maxReps: 15, effort: phul),
          _e('坐姿提踵', '器械', 3, 8, maxSets: 4, maxReps: 12, effort: phul),
          _e('腿举机提踵', '器械', 3, 8, maxSets: 4, maxReps: 12, effort: phul),
        ]),
        rest,
        rest,
      ],
    ),
  ];
}
