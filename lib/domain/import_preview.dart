import 'import_records.dart';
import 'types.dart';
import 'workout_csv.dart';

class ImportCatalog {
  final List<Exercise> exercises;
  final Set<String> fingerprints;
  final String token;
  ImportCatalog({
    required List<Exercise> exercises,
    required Set<String> fingerprints,
    required this.token,
  }) : exercises = List.unmodifiable(exercises),
       fingerprints = Set.unmodifiable(fingerprints);
}

class ImportDraft {
  final CsvParseResult parsed;
  final ImportCatalog catalog;
  final Map<String, List<Exercise>> matches;
  final Set<int> duplicates;
  ImportDraft._(
    this.parsed,
    this.catalog,
    Map<String, List<Exercise>> matches,
    Set<int> duplicates,
  ) : matches = Map.unmodifiable(
        matches.map((k, v) => MapEntry(k, List<Exercise>.unmodifiable(v))),
      ),
      duplicates = Set.unmodifiable(duplicates);
}

class ImportSelection {
  final Set<int> selected;

  /// Missing means unresolved; null means explicitly create a new exercise.
  final Map<String, String?> matches;
  final bool acknowledgeSkipped;
  ImportSelection({
    required Set<int> selected,
    required Map<String, String?> matches,
    this.acknowledgeSkipped = false,
  }) : selected = Set.unmodifiable(selected),
       matches = Map.unmodifiable(matches);
  factory ImportSelection.defaults(ImportDraft draft) => ImportSelection(
    selected: {
      for (var i = 0; i < draft.parsed.workouts.length; i++)
        if (!draft.duplicates.contains(i)) i,
    },
    matches: {
      for (final e in draft.matches.entries)
        if (e.value.length <= 1)
          e.key: e.value.isEmpty ? null : e.value.single.id,
    },
  );
}

class ConfirmedImport {
  final String token;
  final List<ImportedWorkout> workouts;
  final Map<String, String?> matches;
  final int poundsConverted;
  final int unknownDurationCount;
  ConfirmedImport._(
    this.token,
    List<ImportedWorkout> workouts,
    Map<String, String?> matches,
    this.poundsConverted,
    this.unknownDurationCount,
  ) : workouts = List.unmodifiable(workouts),
      matches = Map.unmodifiable(matches);
}

ImportDraft buildImportDraft(CsvParseResult parsed, ImportCatalog catalog) {
  if (parsed.workouts.isNotEmpty) validateImportedWorkouts(parsed.workouts);
  final matches = <String, List<Exercise>>{};
  final seen = {...catalog.fingerprints};
  final duplicates = <int>{};
  for (var i = 0; i < parsed.workouts.length; i++) {
    final w = parsed.workouts[i];
    if (!seen.add(workoutFingerprint(w))) duplicates.add(i);
    for (final e in w.exercises) {
      final key = normalizeExerciseName(e.name);
      matches.putIfAbsent(
        key,
        () => catalog.exercises
            .where((x) => normalizeExerciseName(x.name) == key)
            .toList(),
      );
    }
  }
  return ImportDraft._(parsed, catalog, matches, duplicates);
}

ConfirmedImport confirmImportDraft(
  ImportDraft draft,
  ImportSelection selection,
) {
  if (draft.parsed.skipped.isNotEmpty && !selection.acknowledgeSkipped) {
    throw const ImportValidationException('请先确认将跳过的坏行');
  }
  final indices = selection.selected.toList()..sort();
  final workouts = <ImportedWorkout>[];
  final matches = <String, String?>{};
  var pounds = 0;
  var unknown = 0;
  for (final i in indices) {
    if (i < 0 || i >= draft.parsed.workouts.length) {
      throw const ImportValidationException('训练选择已失效');
    }
    final w = draft.parsed.workouts[i];
    workouts.add(w);
    final stats = draft.parsed.statsByWorkout[i];
    pounds += stats.poundsConverted;
    if (stats.durationUnknown) unknown++;
    for (final e in w.exercises) {
      final key = normalizeExerciseName(e.name);
      if (!selection.matches.containsKey(key)) {
        throw ImportValidationException('请确认动作「${e.name}」的匹配');
      }
      final id = selection.matches[key];
      if (id != null && !draft.catalog.exercises.any((x) => x.id == id)) {
        throw const ImportValidationException('匹配动作不存在');
      }
      matches[key] = id;
    }
  }
  validateImportedWorkouts(workouts);
  return ConfirmedImport._(
    draft.catalog.token,
    workouts,
    matches,
    pounds,
    unknown,
  );
}
