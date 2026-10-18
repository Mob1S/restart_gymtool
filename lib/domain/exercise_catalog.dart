import 'types.dart';

class CatalogExercise {
  final String name, muscleGroup, equipment, loadMeaning;
  final List<String> aliases;
  const CatalogExercise(
    this.name,
    this.muscleGroup,
    this.equipment, {
    this.aliases = const [],
    this.loadMeaning = 'external',
  });
  String get key => '$name|$equipment';
  bool identifies(Exercise e) =>
      e.equipment == equipment && (e.name == name || aliases.contains(e.name));
}

const addedCatalogExercises = <CatalogExercise>[
  CatalogExercise('哑铃上斜卧推', '胸', '哑铃', aliases: ['上斜哑铃卧推']),
  CatalogExercise(
    '哑铃 Y 字侧平举',
    '肩',
    '哑铃',
    aliases: ['Y字侧平举', 'Y 字侧平举', '哑铃Y字侧平举'],
  ),
  CatalogExercise(
    '绳索 Y 字侧平举',
    '肩',
    '绳索',
    aliases: ['Y字侧平举', 'Y 字侧平举', '钢线Y字侧平举'],
  ),
  CatalogExercise('单臂绳索下拉', '背', '绳索', aliases: ['单手钢线下拉', '单臂钢线下拉', '单手绳索下拉']),
  CatalogExercise('对握高位下拉', '背', '器械', aliases: ['对握下拉', '中立握高位下拉']),
  CatalogExercise('单臂器械划船', '背', '器械', aliases: ['单手器械划船']),
  CatalogExercise('坐姿绳索开肘划船', '背', '绳索', aliases: ['坐姿开肘划船', '开肘划船']),
  CatalogExercise('杠铃海豹划船', '背', '杠铃', aliases: ['海豹划船']),
  CatalogExercise('哑铃海豹划船', '背', '哑铃', aliases: ['海豹划船']),
  CatalogExercise('绳索弯举', '手臂', '绳索', aliases: ['钢线弯举']),
  CatalogExercise('坐姿绳索弯举', '手臂', '绳索', aliases: ['坐姿钢线弯举']),
  CatalogExercise('哑铃单腿硬拉', '腿', '哑铃', aliases: ['单腿硬拉', '单腿罗马尼亚硬拉']),
  CatalogExercise('高脚杯深蹲', '腿', '哑铃', aliases: ['酒杯深蹲', 'Goblet Squat']),
  CatalogExercise('哑铃罗马尼亚硬拉', '腿', '哑铃', aliases: ['哑铃RDL']),
  CatalogExercise('杠铃箭步蹲', '腿', '杠铃', aliases: ['杠铃弓步蹲']),
  CatalogExercise('坐姿上斜哑铃弯举', '手臂', '哑铃', aliases: ['上斜哑铃弯举']),
  CatalogExercise(
    '器械辅助双杠臂屈伸',
    '胸',
    '器械',
    aliases: ['辅助双杠臂屈伸', '助力双杠臂屈伸'],
    loadMeaning: 'assistance',
  ),
  CatalogExercise(
    '器械辅助引体向上',
    '背',
    '器械',
    aliases: ['辅助引体向上', '助力引体向上'],
    loadMeaning: 'assistance',
  ),
  CatalogExercise('腿举机提踵', '腿', '器械', aliases: ['倒蹬提踵', 'Calf Press']),
];
const baseExerciseAliases = <String, List<String>>{
  '卧推|杠铃': ['杠铃平板卧推', '平板卧推', '杠铃卧推', 'Bench Press'],
  '前蹲|杠铃': ['颈前深蹲', '杠铃前蹲', 'Front Squat'],
  '上斜卧推|杠铃': ['杠铃上斜卧推'],
  '保加利亚分腿蹲|哑铃': ['保加利亚深蹲', '保加利亚蹲'],
  '站姿推举|杠铃': ['站姿杠铃推举', '杠铃肩推', 'OHP', 'Overhead Press'],
  '仰卧臂屈伸|杠铃': ['仰卧杠铃臂屈伸', 'Skullcrusher'],
  '罗马尼亚硬拉|杠铃': ['杠铃罗马尼亚硬拉', 'RDL'],
};
String _searchKey(String text) =>
    text.toLowerCase().replaceAll(RegExp(r'[\s·（）()]'), '');
bool matchesExerciseQuery(Exercise e, String query) {
  final q = _searchKey(query.trim());
  if (q.isEmpty) return true;
  final names = [
    e.name,
    e.equipment ?? '',
    ...?baseExerciseAliases['${e.name}|${e.equipment}'],
    for (final item in addedCatalogExercises)
      if (item.identifies(e)) ...[item.name, ...item.aliases],
  ];
  return names.any((n) => _searchKey(n).contains(q));
}
