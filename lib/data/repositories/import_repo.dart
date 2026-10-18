import 'dart:convert';

import '../../domain/backup_codec.dart';
import '../../domain/import_records.dart';
import '../../domain/import_preview.dart';
import '../../domain/types.dart';
import '../../domain/weight_value.dart';
import '../db/sql_executor.dart';
import '../ids.dart';
import 'backup_repo.dart';
import '../../domain/set_detail.dart';
import 'set_detail_repo.dart';

Future<ImportCatalog> loadImportCatalog(SqlExecutor exec) =>
    exec.transaction((tx) async {
      final snapshot = await readBackupSnapshot(tx, exportedAt: 0);
      final exercises = [
        for (final e in snapshot.rows('exercises'))
          Exercise(
            id: e['id'] as String,
            name: e['name'] as String,
            muscleGroup: e['muscleGroup'] as String?,
            equipment: e['equipment'] as String?,
            isCustom: e['isCustom'] as bool,
            isArchived: e['isArchived'] as bool,
            createdAt: e['createdAt'] as int,
          ),
      ];
      final names = {for (final e in exercises) e.id: e.name};
      final sets = <String, List<ImportedSet>>{};
      List<Map<String, Object?>> orderedRows(String key) {
        final indexed = snapshot.rows(key).indexed.toList()
          ..sort((a, b) {
            final result = (a.$2['position'] as int).compareTo(
              b.$2['position'] as int,
            );
            return result != 0 ? result : a.$1.compareTo(b.$1);
          });
        return indexed.map((r) => r.$2).toList();
      }

      final orderedSets = orderedRows('sets');
      final details = {
        for (final row in snapshot.rows('setDetails'))
          row['id']: SetDetail.decode(row['payload'] as String),
      };
      for (final s in orderedSets) {
        if (s['isCompleted'] == true) {
          sets
              .putIfAbsent(s['sessionExerciseId'] as String, () => [])
              .add(
                ImportedSet(
                  detail: details[s['id']],
                  weight: (s['weight'] as num).toDouble(),
                  reps: s['reps'] as int,
                  recordedWeight: s['sourceWeight'] == null
                      ? null
                      : EquipmentWeight(
                          DecimalReading.parse(s['sourceWeight'] as String),
                          WeightUnit.values.byName(s['sourceUnit'] as String),
                        ),
                ),
              );
        }
      }
      final children = <String, List<ImportedExercise>>{};
      final ordered = orderedRows('sessionExercises');
      for (final e in ordered) {
        final groups = sets[e['id']];
        if (groups == null || groups.isEmpty) continue;
        children
            .putIfAbsent(e['sessionId'] as String, () => [])
            .add(ImportedExercise(name: names[e['exerciseId']]!, sets: groups));
      }
      final fingerprints = <String>{};
      for (final w in snapshot.rows('sessions')) {
        if (w['finishedAt'] == null) continue;
        fingerprints.add(
          workoutFingerprint(
            ImportedWorkout(
              sourceRow: 0,
              startedAt: w['startedAt'] as int,
              finishedAt: w['finishedAt'] as int,
              name: w['name'] as String?,
              exercises: children[w['id']] ?? [],
            ),
          ),
        );
      }
      return ImportCatalog(
        exercises: exercises,
        fingerprints: fingerprints,
        token: jsonEncode(snapshot.data),
      );
    });

Future<ImportResult> importWorkouts(
  SqlExecutor exec,
  ConfirmedImport batch, {
  String origin = 'csv',
}) async {
  if (origin != 'csv' && origin != 'manual') {
    throw const ImportValidationException('导入来源无效');
  }
  validateImportedWorkouts(batch.workouts);
  return exec.transaction((tx) async {
    final snapshot = await readBackupSnapshot(tx, exportedAt: 0);
    if (jsonEncode(snapshot.data) != batch.token) {
      throw const ImportValidationException('本机数据已变化，请重新预览');
    }
    final available = {
      for (final e in snapshot.rows('exercises')) e['id'] as String,
    };
    final resolved = <String, String>{};
    final ids = <String>[];
    var created = 0;
    var sets = 0;
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final w in batch.workouts) {
      final sessionId = newId();
      ids.add(sessionId);
      await tx.run(
        'INSERT INTO session (id,name,started_at,finished_at,note,template_id,origin) VALUES (?,?,?,?,?,NULL,?)',
        [sessionId, w.name, w.startedAt, w.finishedAt, w.note, origin],
      );
      // Merge blocks of the same canonical name without discarding equal sets.
      final combined = <String, (String, List<ImportedSet>)>{};
      for (final e in w.exercises) {
        combined
            .putIfAbsent(
              normalizeExerciseName(e.name),
              () => (e.name, <ImportedSet>[]),
            )
            .$2
            .addAll(e.sets);
      }
      var position = 0;
      for (final entry in combined.entries) {
        final key = entry.key;
        var exerciseId = resolved[key];
        if (exerciseId == null) {
          if (!batch.matches.containsKey(key)) {
            throw const ImportValidationException('动作匹配未确认');
          }
          exerciseId = batch.matches[key];
          if (exerciseId == null) {
            exerciseId = newId();
            created++;
            await tx.run(
              'INSERT INTO exercise (id,name,is_custom,is_archived,created_at) VALUES (?,?,1,0,?)',
              [exerciseId, entry.value.$1, now],
            );
          } else if (!available.contains(exerciseId)) {
            throw const ImportValidationException('动作匹配已失效');
          }
          resolved[key] = exerciseId;
        }
        final seId = newId();
        await tx.run(
          'INSERT INTO session_exercise (id,session_id,exercise_id,position) VALUES (?,?,?,?)',
          [seId, sessionId, exerciseId, position++],
        );
        var setPosition = 0;
        for (final set in entry.value.$2) {
          final setId = newId();
          await tx.run(
            'INSERT INTO set_entry (id,session_exercise_id,position,weight,reps,is_completed,rest_seconds,rest_started_at,completed_at,source_weight,source_unit) VALUES (?,?,?,?,?,1,NULL,NULL,?,?,?)',
            [
              setId,
              seId,
              setPosition++,
              set.weight,
              set.reps,
              w.finishedAt,
              set.equipmentWeight.amount.text,
              set.equipmentWeight.unit.name,
            ],
          );
          if (set.detail != null) await writeSetDetail(tx, setId, set.detail!);
          sets++;
        }
      }
    }
    encodeBackup(await readBackupSnapshot(tx, exportedAt: now));
    return ImportResult(
      sessionIds: ids,
      sets: sets,
      usedExercises: resolved.length,
      createdExercises: created,
    );
  });
}
