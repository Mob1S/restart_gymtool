/// 预置动作的模板。
class SeedExercise {
  final String name;
  final String muscleGroup;
  final String equipment;

  const SeedExercise(this.name, this.muscleGroup, this.equipment);
}

/// 预置动作表，按肌群分组书写，顺序与界面上的展示顺序一致。
///
/// 只在**全新数据库**（`exercise` 表一行都没有）时写入一次。
/// 改动它不会影响已有用户的库 —— 他们已经播过种了。
const List<SeedExercise> seedExercises = [
  // 腿（12）
  SeedExercise('深蹲', '腿', '杠铃'),
  SeedExercise('前蹲', '腿', '杠铃'),
  SeedExercise('硬拉', '腿', '杠铃'),
  SeedExercise('罗马尼亚硬拉', '腿', '杠铃'),
  SeedExercise('腿举', '腿', '器械'),
  SeedExercise('腿屈伸', '腿', '器械'),
  SeedExercise('腿弯举', '腿', '器械'),
  SeedExercise('保加利亚分腿蹲', '腿', '哑铃'),
  SeedExercise('箭步蹲', '腿', '哑铃'),
  SeedExercise('站姿提踵', '腿', '器械'),
  SeedExercise('坐姿提踵', '腿', '器械'),
  SeedExercise('臀推', '腿', '杠铃'),

  // 胸（9）
  SeedExercise('卧推', '胸', '杠铃'),
  SeedExercise('上斜卧推', '胸', '杠铃'),
  SeedExercise('下斜卧推', '胸', '杠铃'),
  SeedExercise('哑铃卧推', '胸', '哑铃'),
  SeedExercise('哑铃飞鸟', '胸', '哑铃'),
  SeedExercise('绳索夹胸', '胸', '绳索'),
  SeedExercise('双杠臂屈伸', '胸', '自重'),
  SeedExercise('俯卧撑', '胸', '自重'),
  SeedExercise('器械推胸', '胸', '器械'),

  // 背（9）
  SeedExercise('引体向上', '背', '自重'),
  SeedExercise('高位下拉', '背', '器械'),
  SeedExercise('杠铃划船', '背', '杠铃'),
  SeedExercise('哑铃单臂划船', '背', '哑铃'),
  SeedExercise('坐姿绳索划船', '背', '绳索'),
  SeedExercise('T 杠划船', '背', '杠铃'),
  SeedExercise('直臂下压', '背', '绳索'),
  SeedExercise('面拉', '背', '绳索'),
  SeedExercise('山羊挺身', '背', '自重'),

  // 肩（7）
  SeedExercise('站姿推举', '肩', '杠铃'),
  SeedExercise('坐姿哑铃推举', '肩', '哑铃'),
  SeedExercise('侧平举', '肩', '哑铃'),
  SeedExercise('前平举', '肩', '哑铃'),
  SeedExercise('俯身飞鸟', '肩', '哑铃'),
  SeedExercise('反向蝴蝶机', '肩', '器械'),
  SeedExercise('耸肩', '肩', '杠铃'),

  // 手臂（9）
  SeedExercise('杠铃弯举', '手臂', '杠铃'),
  SeedExercise('哑铃弯举', '手臂', '哑铃'),
  SeedExercise('锤式弯举', '手臂', '哑铃'),
  SeedExercise('牧师凳弯举', '手臂', '器械'),
  SeedExercise('绳索下压', '手臂', '绳索'),
  SeedExercise('仰卧臂屈伸', '手臂', '杠铃'),
  SeedExercise('过顶臂屈伸', '手臂', '哑铃'),
  SeedExercise('窄距卧推', '手臂', '杠铃'),
  SeedExercise('腕弯举', '手臂', '哑铃'),

  // 核心（6）
  SeedExercise('卷腹', '核心', '自重'),
  SeedExercise('悬垂举腿', '核心', '自重'),
  SeedExercise('平板支撑', '核心', '自重'),
  SeedExercise('俄罗斯转体', '核心', '哑铃'),
  SeedExercise('绳索卷腹', '核心', '绳索'),
  SeedExercise('健腹轮', '核心', '自重'),
];
