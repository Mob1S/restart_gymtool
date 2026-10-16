import 'dart:convert';

class ImportedSet {
  final double weight;
  final int reps;
  const ImportedSet({required this.weight, required this.reps});
}

class ImportedExercise {
  final String name;
  final List<ImportedSet> sets;
  ImportedExercise({required this.name, required List<ImportedSet> sets})
    : sets = List.unmodifiable(sets);
}

class ImportedWorkout {
  final int sourceRow;
  final int startedAt;
  final int finishedAt;
  final String? name;
  final String? note;
  final List<ImportedExercise> exercises;
  ImportedWorkout({
    required this.sourceRow,
    required this.startedAt,
    required this.finishedAt,
    this.name,
    this.note,
    required List<ImportedExercise> exercises,
  }) : exercises = List.unmodifiable(exercises);
}

class ImportResult {
  final List<String> sessionIds;
  final int sets;
  final int usedExercises;
  final int createdExercises;
  int get sessions => sessionIds.length;
  ImportResult({
    required List<String> sessionIds,
    required this.sets,
    required this.usedExercises,
    required this.createdExercises,
  }) : sessionIds = List.unmodifiable(sessionIds);
}

class ImportValidationException implements Exception {
  final String message;
  const ImportValidationException(this.message);
  @override
  String toString() => message;
}

String halfWidth(String input) => String.fromCharCodes(
  input.runes.map(
    (r) => r == 0x3000 ? 0x20 : (r >= 0xff01 && r <= 0xff5e ? r - 0xfee0 : r),
  ),
);

String normalizeExerciseName(String input) =>
    halfWidth(input).replaceAll(RegExp(r'\s+'), '').toLowerCase();

String normalizeWorkoutName(String input) =>
    halfWidth(input).trim().replaceAll(RegExp(r'\s+'), ' ');

void validateImportedWorkouts(List<ImportedWorkout> workouts) {
  Never fail(String message) => throw ImportValidationException(message);
  if (workouts.isEmpty) fail('请选择至少一场训练');
  var count = workouts.length;
  for (final w in workouts) {
    if (w.startedAt < 0 ||
        w.finishedAt > 8640000000000000 ||
        w.finishedAt < w.startedAt) {
      fail('第 ${w.sourceRow} 行：训练起止时间无效');
    }
    if (w.exercises.isEmpty) fail('训练至少需要一个动作');
    count += w.exercises.length;
    for (final e in w.exercises) {
      if (normalizeExerciseName(e.name).isEmpty) fail('动作名称不能为空');
      if (e.sets.isEmpty) fail('每个动作至少需要一组');
      count += e.sets.length;
      if (count > 100000) fail('导入记录超过 100,000 条');
      for (final s in e.sets) {
        if (!s.weight.isFinite || s.weight < 0 || s.reps <= 0) {
          fail('重量须为非负有限数，次数须为正整数');
        }
      }
    }
  }
}

String workoutFingerprint(ImportedWorkout w) => jsonEncode([
  w.startedAt,
  w.finishedAt,
  normalizeWorkoutName(w.name ?? ''),
  for (final e in w.exercises)
    [
      normalizeExerciseName(e.name),
      for (final s in e.sets) [s.weight, s.reps],
    ],
]);
