import 'package:pinyin/pinyin.dart';

import '../../domain/types.dart';
import '../db/sql_executor.dart';
import '../ids.dart';
import 'seed.dart';

/// `exercise` 表的原始行。布尔在库里是 0/1，转换见 [toExercise]。
///
/// **字段用 camelCase，列名（map 的键）用 snake_case** —— 两者的对应关系由
/// [ExerciseRow.fromMap] 一处显式写出。
///
/// 这里曾有另一种写法：字段也用 snake_case 去镜像列名，再靠
/// `// ignore_for_file: non_constant_identifier_names` 压住 lint。
/// **已改掉**，理由有两条：一是 Dart 的标识符规范就是 camelCase，
/// 在新代码库里靠 ignore 绕过它是味道；二是那点「一眼可查」的收益本来就
/// 由 `fromMap` 提供了，改成 camelCase 并没有丢掉任何信息。
class ExerciseRow {
  final String id;
  final String name;
  final String? muscleGroup;
  final String? equipment;
  final int isCustom;
  final int isArchived;
  final int createdAt;

  const ExerciseRow({
    required this.id,
    required this.name,
    this.muscleGroup,
    this.equipment,
    required this.isCustom,
    required this.isArchived,
    required this.createdAt,
  });

  factory ExerciseRow.fromMap(Map<String, Object?> m) => ExerciseRow(
    id: m['id'] as String,
    name: m['name'] as String,
    muscleGroup: m['muscle_group'] as String?,
    equipment: m['equipment'] as String?,
    isCustom: m['is_custom'] as int,
    isArchived: m['is_archived'] as int,
    createdAt: m['created_at'] as int,
  );
}

/// 行 → 实体。把 0/1 还原成布尔。
Exercise toExercise(ExerciseRow row) => Exercise(
  id: row.id,
  name: row.name,
  muscleGroup: row.muscleGroup,
  equipment: row.equipment,
  isCustom: row.isCustom == 1,
  isArchived: row.isArchived == 1,
  createdAt: row.createdAt,
);

/// SELECT 的列清单。抽出来是为了让「列」与「映射」永远对得上。
const String exerciseColumns =
    'id, name, muscle_group, equipment, is_custom, is_archived, created_at';

/// 肌群的展示顺序。不在这个表里的肌群一律排到最后。
const List<String> muscleGroupOrder = ['胸', '背', '腿', '肩', '手臂', '核心'];

/// 不在 [muscleGroupOrder] 里的（含 null）**一律排到最后**，而不是排到最前。
int muscleGroupRank(String? group) {
  final index = muscleGroupOrder.indexOf(group ?? '');
  return index == -1 ? muscleGroupOrder.length : index;
}

/// 中文动作名的拼音键，用于排序。
///
/// 中文用户预期的「按字母排」是拼音序；SQLite 与 Dart 的默认比较都是
/// UTF-8 码点序，对中文等于随机顺序。
///
/// `separator: ''` 去掉音节分隔（我们要的是整串比较），
/// `defPinyin: '#'` 让不认识的字符集中排到最后而不是抛错。
String pinyinKey(String name) =>
    PinyinHelper.getPinyinE(name, separator: '', defPinyin: '#');

/// 按肌群、再按动作名排序。
///
/// **名称必须在这里用拼音序排，不能交给 SQLite。**
/// SQLite 的 `COLLATE NOCASE` 只做 ASCII 大小写折叠，对中文退化为 UTF-8
/// 码点比较，排出来是「保加利亚分腿蹲、前蹲、坐姿提踵、深蹲、硬拉…」
/// 这种对人来说毫无规律的顺序。**Dart 的 `String.compareTo` 同样是码点序，
/// 也不能用。**
int compareExercises(Exercise a, Exercise b) {
  final rankDiff =
      muscleGroupRank(a.muscleGroup) - muscleGroupRank(b.muscleGroup);
  if (rankDiff != 0) return rankDiff;
  final byPinyin = pinyinKey(a.name).compareTo(pinyinKey(b.name));
  if (byPinyin != 0) return byPinyin;
  // 拼音相同时退回码点序，保证排序是**确定的**（不依赖输入顺序）
  return a.name.compareTo(b.name);
}

/// 列出全部**未归档**的动作，已按肌群 + 拼音排好序。
///
/// 排序在 Dart 里做而不是 SQL 里，原因见 [compareExercises]。
Future<List<Exercise>> listExercises(
  SqlExecutor exec, {
  bool includeArchived = false,
}) async {
  final rows = await exec.all<Map<String, Object?>>(
    'SELECT $exerciseColumns FROM exercise${includeArchived ? '' : ' WHERE is_archived = 0'}',
  );
  final list = rows.map((m) => toExercise(ExerciseRow.fromMap(m))).toList();
  list.sort(compareExercises);
  return list;
}

/// 按 id 取一个动作。
///
/// **id 不存在时返回 null。** 注意**已归档的动作也能取到** ——
/// 历史记录里引用着它，取不到就会显示成「未知动作」。
Future<Exercise?> getExercise(SqlExecutor exec, String id) async {
  final row = await exec.first<Map<String, Object?>>(
    'SELECT $exerciseColumns FROM exercise WHERE id = ?',
    [id],
  );
  return row == null ? null : toExercise(ExerciseRow.fromMap(row));
}

/// 新建一个用户自建动作（`isCustom` 一律为 true，预置动作只能由播种写入）。
///
/// 不做重名检查：动作库里本来就有「卧推 / 上斜卧推 / 窄距卧推」这类同名前缀，
/// 判断重名比让用户自己看更烦人。
Future<Exercise> createCustomExercise(
  SqlExecutor exec, {
  required String name,
  String? muscleGroup,
  String? equipment,
}) async {
  final exercise = Exercise(
    id: newId(),
    name: name,
    muscleGroup: muscleGroup,
    equipment: equipment,
    isCustom: true,
    isArchived: false,
    createdAt: DateTime.now().millisecondsSinceEpoch,
  );

  await exec.run(
    '''INSERT INTO exercise (id, name, muscle_group, equipment, is_custom, is_archived, created_at)
       VALUES (?, ?, ?, ?, 1, 0, ?)''',
    [
      exercise.id,
      exercise.name,
      exercise.muscleGroup,
      exercise.equipment,
      exercise.createdAt,
    ],
  );

  return exercise;
}

/// 只在动作表为空时写入预置动作。
///
/// 判断依据是「表里一个动作都没有」，而不是「表里没有预置动作」——
/// 用户如果自己先建了动作，就不该再塞一堆预置动作进去。
Future<void> seedExercisesIfEmpty(SqlExecutor exec) async {
  await exec.transaction((tx) async {
    final initialized = await tx.first<Map<String, Object?>>(
      "SELECT value FROM app_meta WHERE key = 'seed_initialized'",
    );
    if (initialized?['value'] == '1') return;
    final row = await tx.first<Map<String, Object?>>(
      'SELECT COUNT(*) AS count FROM exercise',
    );
    final count = (row?['count'] as int?) ?? 0;
    if (count == 0) {
      final now = DateTime.now().millisecondsSinceEpoch;
      for (final item in seedExercises) {
        await tx.run(
          '''INSERT INTO exercise (id, name, muscle_group, equipment, is_custom, is_archived, created_at)
         VALUES (?, ?, ?, ?, 0, 0, ?)''',
          [newId(), item.name, item.muscleGroup, item.equipment, now],
        );
      }
    }
    await tx.run(
      "INSERT INTO app_meta (key,value) VALUES ('seed_initialized','1') ON CONFLICT(key) DO UPDATE SET value=excluded.value",
    );
  });
}
