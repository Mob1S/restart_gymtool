import 'weight_value.dart';

/// 动作库里的一个动作。
///
/// 预置动作与用户自建动作共用这一张表，只有 [isCustom] 区分 —— 备份导出时
/// 两者都要带上，换设备后自建动作才不会丢。
class Exercise {
  final String id;
  final String name;

  /// 肌群（胸/背/腿/肩/手臂/核心）；不在这个枚举里的排到最后
  final String? muscleGroup;
  final String? equipment;

  /// true = 用户自建；false = 预置
  final bool isCustom;

  /// 归档的动作不在动作列表里出现，但历史记录仍引用得到它
  final bool isArchived;
  final int createdAt;

  const Exercise({
    required this.id,
    required this.name,
    this.muscleGroup,
    this.equipment,
    required this.isCustom,
    required this.isArchived,
    required this.createdAt,
  });
}

/// 一次训练。[finishedAt] 为 null 即「正在进行中」。
class WorkoutSession {
  final String id;
  final String? name;
  final int startedAt;

  /// 结束时间；null 表示这场还没结束
  final int? finishedAt;
  final String? note;

  /// 开训来源训练日。父计划按 [planId] 分组，轮换由实际完成日推算。
  final String? templateId;
  final String? planId;
  final String? planNameSnapshot;
  final String? dayNameSnapshot;
  final String origin;

  const WorkoutSession({
    required this.id,
    this.name,
    required this.startedAt,
    this.finishedAt,
    this.note,
    this.templateId,
    this.planId,
    this.planNameSnapshot,
    this.dayNameSnapshot,
    this.origin = 'legacy',
  });

  WorkoutSession copyWith({int? finishedAt}) => WorkoutSession(
    id: id,
    name: name,
    startedAt: startedAt,
    finishedAt: finishedAt ?? this.finishedAt,
    note: note,
    templateId: templateId,
    planId: planId,
    planNameSnapshot: planNameSnapshot,
    dayNameSnapshot: dayNameSnapshot,
    origin: origin,
  );
}

/// 一次训练里的一个动作（练了什么 + 排第几）。
/// **组挂在它下面**，不是挂在动作上。
class SessionExercise {
  final String id;

  /// 属于哪一场训练。注意组记录引用的是本表的 id，不是 [exerciseId]
  final String sessionId;

  /// 指向动作库里的动作
  final String exerciseId;

  /// 在这一场里的顺序，从 0 开始；界面按它排列
  final int position;
  final String? note;

  const SessionExercise({
    required this.id,
    required this.sessionId,
    required this.exerciseId,
    required this.position,
    this.note,
  });
}

/// 一组记录。**记录的原子单位**：完成即落盘的那一条就是它。
///
/// 记录界面会为「下一组」预先建一条 `isCompleted: false` 的占位 —— 界面靠
/// 找这条占位来确定当前该记哪一组，所以它必须存在。
class SetEntry {
  final String id;

  /// 指向 [SessionExercise.id]（**不是** `exerciseId`）——
  /// 两者都是字符串 id，写错了编译器不报错，但会一组都读不出来
  final String sessionExerciseId;

  /// 在这个动作里的第几组，从 0 开始
  final int position;

  /// 重量（kg）
  final double weight;
  final EquipmentWeight? recordedWeight;
  EquipmentWeight get equipmentWeight =>
      recordedWeight ?? EquipmentWeight.kg(weight);
  final int reps;
  final bool isCompleted;

  /// 本组做完后休息了多久（秒）。null 表示还没结束那次休息，或这是最后一组
  final int? restSeconds;

  /// 休息开始的时间戳。非 null 表示正在休息中
  final int? restStartedAt;
  final int? completedAt;

  const SetEntry({
    required this.id,
    required this.sessionExerciseId,
    required this.position,
    required this.weight,
    this.recordedWeight,
    required this.reps,
    required this.isCompleted,
    this.restSeconds,
    this.restStartedAt,
    this.completedAt,
  });
}

/// 算容量负荷 / 1RM 所需的**最小**组形状。
///
/// 单独定义是为了让 [metrics] 不依赖完整的 [SetEntry] —— 折算曲线时手里
/// 只有「重量 + 次数」几个数，不必为了算容量伪造一个完整记录。
class SetLike {
  /// 重量（kg）
  final double weight;
  final int reps;

  /// 未完成的组不计入容量负荷
  final bool isCompleted;

  const SetLike({
    required this.weight,
    required this.reps,
    required this.isCompleted,
  });
}
