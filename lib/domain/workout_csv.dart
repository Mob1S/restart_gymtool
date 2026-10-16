import 'dart:convert';

import 'csv_records.dart';
import 'import_records.dart';

enum CsvSource { strong, hevy, xunji, unknown }

enum WeightUnit { kg, lb }

class CsvIssue {
  final int line;
  final String reason;
  const CsvIssue(this.line, this.reason);
}

class WorkoutImportStats {
  final List<int> sourceRows;
  final int poundsConverted;
  final bool durationUnknown;
  WorkoutImportStats(List<int> rows, this.poundsConverted, this.durationUnknown)
    : sourceRows = List.unmodifiable(rows);
}

class CsvParseResult {
  final CsvSource source;
  final List<String> columns;
  final List<ImportedWorkout> workouts;
  final List<CsvIssue> skipped;
  final List<WorkoutImportStats> statsByWorkout;
  int get poundsConverted =>
      statsByWorkout.fold(0, (n, s) => n + s.poundsConverted);
  int get unknownDurationCount =>
      statsByWorkout.where((s) => s.durationUnknown).length;
  CsvParseResult({
    required this.source,
    List<String> columns = const [],
    required List<ImportedWorkout> workouts,
    List<CsvIssue> skipped = const [],
    required List<WorkoutImportStats> statsByWorkout,
  }) : columns = List.unmodifiable(columns),
       workouts = List.unmodifiable(workouts),
       skipped = List.unmodifiable(skipped),
       statsByWorkout = List.unmodifiable(statsByWorkout);
}

class _Group {
  final int start;
  final String name;
  final List<int> rows = [];
  final Set<int> ends = {};
  final Map<String, (String, List<ImportedSet>)> exercises = {};
  int pounds = 0;
  _Group(this.start, this.name);
}

/// Parse only explicitly supported formats; DateTime's overflow normalization
/// is checked before accepting a date, including ISO timestamps with offsets.
int parseImportDate(String input) {
  final value = input.trim();
  final iso = RegExp(
    r'^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2})(?:\.(\d{1,3}))?)?(Z|[+-]\d{2}:?\d{2})$',
  ).firstMatch(value);
  int check(
    int y,
    int m,
    int d,
    int h,
    int min,
    int sec, {
    bool utc = false,
    int ms = 0,
  }) {
    final date = utc
        ? DateTime.utc(y, m, d, h, min, sec, ms)
        : DateTime(y, m, d, h, min, sec, ms);
    if (date.year != y ||
        date.month != m ||
        date.day != d ||
        date.hour != h ||
        date.minute != min ||
        date.second != sec) {
      throw const ImportValidationException('日期或时间无效');
    }
    return date.millisecondsSinceEpoch;
  }

  if (iso != null) {
    final v = [for (var i = 1; i <= 6; i++) int.parse(iso[i] ?? '0')];
    var time = check(
      v[0],
      v[1],
      v[2],
      v[3],
      v[4],
      v[5],
      utc: true,
      ms: int.parse((iso[7] ?? '0').padRight(3, '0')),
    );
    final z = iso[8]!;
    if (z != 'Z') {
      final digits = z.substring(1).replaceAll(':', '');
      final h = int.parse(digits.substring(0, 2));
      final m = int.parse(digits.substring(2));
      if (h > 23 || m > 59) throw const ImportValidationException('时区偏移无效');
      time -= (z[0] == '+' ? 1 : -1) * (h * 60 + m) * 60000;
    }
    if (time < 0) throw const ImportValidationException('日期早于 1970 年');
    return time;
  }
  final match = RegExp(
    r'^(\d{4}[-/]\d{1,2}[-/]\d{1,2}|\d{1,2}/\d{1,2}/\d{4})(?:[ T](\d{1,2}):(\d{2})(?::(\d{2}))?\s*(AM|PM)?)?$',
    caseSensitive: false,
  ).firstMatch(value);
  if (match == null) throw const ImportValidationException('不支持的日期格式');
  final parts = match[1]!.split(RegExp('[-/]')).map(int.parse).toList();
  final yearFirst = match[1]!.split(RegExp('[-/]')).first.length == 4;
  var hour = int.parse(match[2] ?? '12');
  final ampm = match[5]?.toUpperCase();
  if (ampm != null) {
    if (hour < 1 || hour > 12) {
      throw const ImportValidationException('AM / PM 小时无效');
    }
    hour = hour % 12 + (ampm == 'PM' ? 12 : 0);
  }
  final time = check(
    yearFirst ? parts[0] : parts[2],
    yearFirst ? parts[1] : parts[0],
    yearFirst ? parts[2] : parts[1],
    hour,
    int.parse(match[3] ?? '0'),
    int.parse(match[4] ?? '0'),
  );
  if (time < 0) throw const ImportValidationException('日期早于 1970 年');
  return time;
}

CsvParseResult parseWorkoutCsv(
  String text, {
  WeightUnit defaultUnit = WeightUnit.kg,
}) {
  if (utf8.encode(text).length > 20 * 1024 * 1024) {
    throw const ImportValidationException('CSV 超过 20 MiB');
  }
  final rows = scanCsv(text.replaceFirst(RegExp('^\uFEFF'), ''));
  final nonempty = rows
      .where((r) => r.fields.any((f) => f.trim().isNotEmpty))
      .toList();
  if (nonempty.isEmpty) throw const ImportValidationException('CSV 文件为空');
  final header = nonempty.first.fields.map(normalizeExerciseName).toList();
  const layouts = {
    CsvSource.strong: [
      'Date',
      'Exercise Name',
      'Weight',
      'Reps',
      'Workout Name',
      '',
    ],
    CsvSource.hevy: [
      'start_time',
      'exercise_title',
      'weight_kg',
      'reps',
      'title',
      'end_time',
    ],
    CsvSource.xunji: ['日期', '动作名称', '重量(kg)', '次数', '训练名称', ''],
  };
  final candidates = layouts.entries
      .where(
        (e) => e.value
            .take(4)
            .every((h) => header.contains(normalizeExerciseName(h))),
      )
      .toList();
  if (candidates.length != 1) {
    throw const ImportValidationException(
      '无法识别唯一来源，请使用 Strong、Hevy 或训记约定的 CSV 表头',
    );
  }
  final source = candidates.single.key;
  final layout = candidates.single.value;
  for (final h in layout.where((h) => h.isNotEmpty)) {
    if (header.where((v) => v == normalizeExerciseName(h)).length > 1) {
      throw const ImportValidationException('CSV 有重复列');
    }
  }
  final indices = layout
      .map((h) => h.isEmpty ? -1 : header.indexOf(normalizeExerciseName(h)))
      .toList();
  final groups = <String, _Group>{};
  final skipped = <CsvIssue>[];
  for (final row in nonempty.skip(1)) {
    if (row.fields.map(normalizeExerciseName).join('\u0000') ==
        header.join('\u0000')) {
      continue;
    }
    try {
      if (row.fields.length != header.length) {
        throw const ImportValidationException('列数与表头不一致');
      }
      String field(int i) => indices[i] < 0
          ? ''
          : (indices[i] < row.fields.length
                ? row.fields[indices[i]].trim()
                : '');
      final start = parseImportDate(field(0));
      final end = field(5).isEmpty ? null : parseImportDate(field(5));
      if (end != null && end < start) {
        throw const ImportValidationException('结束早于开始');
      }
      final name = field(1);
      if (normalizeExerciseName(name).isEmpty) {
        throw const ImportValidationException('动作名称为空');
      }
      final weightText = halfWidth(field(2)).trim().toLowerCase();
      var pounds = false;
      double weight;
      if (weightText.isEmpty || weightText == 'bw') {
        weight = 0;
      } else {
        final m = RegExp(r'^([+]?(?:\d+(?:\.\d*)?|\.\d+))\s*(kg|lbs?|公斤)?$')
            .firstMatch(weightText);
        if (m == null) throw const ImportValidationException('重量无效');
        pounds =
            m[2]?.startsWith('lb') ??
            (source == CsvSource.strong && defaultUnit == WeightUnit.lb);
        if (source != CsvSource.strong && m[2]?.startsWith('lb') == true) {
          throw const ImportValidationException('磅单位与公斤表头冲突');
        }
        weight = double.parse(m[1]!) * (pounds ? 0.45359237 : 1);
        if (!weight.isFinite) throw const ImportValidationException('重量不是有限数');
      }
      final repsText = halfWidth(field(3));
      if (!RegExp(r'^\d+\s*(?:次)?$').hasMatch(repsText)) {
        throw const ImportValidationException('次数须为正整数');
      }
      final reps = int.tryParse(repsText.replaceAll(RegExp(r'\s*次$'), ''));
      if (reps == null || reps <= 0) {
        throw const ImportValidationException('次数须为正整数');
      }
      final workoutName = normalizeWorkoutName(field(4));
      final key = jsonEncode([source.name, start, workoutName]);
      final group = groups.putIfAbsent(key, () => _Group(start, workoutName));
      group.rows.add(row.line);
      if (end != null) group.ends.add(end);
      if (pounds) group.pounds++;
      final e = group.exercises.putIfAbsent(
        normalizeExerciseName(name),
        () => (name, <ImportedSet>[]),
      );
      e.$2.add(ImportedSet(weight: weight, reps: reps));
    } on ImportValidationException catch (e) {
      skipped.add(CsvIssue(row.line, e.message));
    }
  }
  final ordered = groups.values.toList()
    ..sort((a, b) {
      final c = a.start.compareTo(b.start);
      return c != 0 ? c : a.rows.first.compareTo(b.rows.first);
    });
  final workouts = <ImportedWorkout>[];
  final stats = <WorkoutImportStats>[];
  for (final g in ordered) {
    if (g.ends.length > 1) {
      skipped.addAll(g.rows.map((r) => CsvIssue(r, '同场训练的结束时间冲突')));
      continue;
    }
    final unknown = g.ends.isEmpty;
    workouts.add(
      ImportedWorkout(
        sourceRow: g.rows.first,
        startedAt: g.start,
        finishedAt: unknown ? g.start : g.ends.single,
        name: g.name.isEmpty ? null : g.name,
        note: '来源：${source.name}${unknown ? '；来源未提供结束时间，时长未知' : ''}',
        exercises: [
          for (final e in g.exercises.values)
            ImportedExercise(name: e.$1, sets: e.$2),
        ],
      ),
    );
    stats.add(WorkoutImportStats(g.rows, g.pounds, unknown));
  }
  skipped.sort((a, b) => a.line.compareTo(b.line));
  return CsvParseResult(
    source: source,
    columns: nonempty.first.fields,
    workouts: workouts,
    skipped: skipped,
    statsByWorkout: stats,
  );
}
