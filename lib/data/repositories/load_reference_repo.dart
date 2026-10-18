import 'dart:convert';

import '../../domain/load_reference.dart';
import '../../domain/training_prescription.dart';
import '../../domain/weight_value.dart';
import '../../domain/backup_codec.dart';
import '../../domain/record_management.dart';
import '../db/sql_executor.dart';
import 'exercise_catalog_repo.dart';
import 'exercise_preferences_repo.dart';
import 'exercise_repo.dart';
import 'set_repo.dart';
import 'set_detail_repo.dart';
import 'workout_write_repo.dart';
import 'backup_repo.dart';

Future<LoadReference> loadReferenceForPending(
  SqlExecutor exec,
  String pendingSetId, {
  int? now,
}) => exec.transaction(
  (tx) => readLoadReference(
    tx,
    pendingSetId,
    now: now ?? DateTime.now().millisecondsSinceEpoch,
  ),
);
Future<LoadReference> readLoadReference(
  SqlExecutor tx,
  String pendingSetId, {
  required int now,
}) async {
  final row = await tx.first<Map<String, Object?>>(
    'SELECT st.*,se.exercise_id,se.session_id FROM set_entry st JOIN session_exercise se ON se.id=st.session_exercise_id JOIN session s ON s.id=se.session_id WHERE st.id=? AND st.is_completed=0 AND s.finished_at IS NULL',
    [pendingSetId],
  );
  if (row == null) return const LoadReference(message: '当前组已变化，请重新载入');
  final exerciseId = row['exercise_id'] as String;
  final prefs = (await readExercisePreferences(tx, [exerciseId]))[exerciseId]!;
  final detail = await readSetDetail(tx, pendingSetId);
  final target =
      detail.target ??
      SetTarget(
        repsMin: (row['reps'] as int).clamp(1, 10000),
        repsMax: (row['reps'] as int).clamp(1, 10000),
      );
  final facts = await tx.all<Map<String, Object?>>(
    'SELECT $setColumnsPrefixed,s.id AS sid,s.started_at,sd.payload AS detail_payload FROM set_entry st JOIN session_exercise se ON se.id=st.session_exercise_id JOIN session s ON s.id=se.session_id LEFT JOIN set_detail sd ON sd.id=st.id WHERE se.exercise_id=? AND st.is_completed=1 AND s.finished_at IS NOT NULL AND s.started_at<=? AND s.started_at>=? ORDER BY s.started_at DESC,s.rowid DESC,st.position ASC,st.rowid ASC',
    [exerciseId, now, now - 90 * 86400000],
  );
  final history = <LoadObservation>[];
  final segmentIndex = detail.currentSegment;
  for (final f in facts) {
    final sid = f['sid'] as String;
    final s = toSetEntry(SetRow.fromMap(f));
    final d = s.detail;
    if (target.isRestPause && segmentIndex > (d?.continuations.length ?? 0)) {
      continue;
    }
    final part = target.isRestPause && segmentIndex > 0
        ? d!.continuations[segmentIndex - 1]
        : null;
    history.add(
      LoadObservation(
        sessionId: sid,
        setId: s.id,
        at: f['started_at'] as int,
        reps: part?.reps ?? s.reps,
        reading: part?.reading ?? s.equipmentWeight,
        effort: part?.effort ?? (part == null ? d?.effort : null),
        firstReps: s.reps,
        segmentIndex: segmentIndex,
        warmup: d?.role == 'warmup',
        pattern: d?.isRestPause == true
            ? (d!.continuations.isEmpty
                  ? [-1]
                  : d.continuations.map((s) => s.reps).toList())
            : [],
        pauseSeconds: d?.continuations.isNotEmpty == true
            ? (d!.continuations.every(
                    (s) =>
                        (s.pauseSeconds - (d.target?.pauseSeconds ?? -100))
                            .abs() <=
                        1,
                  )
                  ? d.target!.pauseSeconds
                  : d.continuations.first.pauseSeconds)
            : 0,
      ),
    );
  }
  final exercise = await getExercise(tx, exerciseId);
  var meaning = exercise?.equipment == '自重' ? 'bodyweight' : 'external';
  final bindings = await readCatalogBindings(tx);
  for (final item in builtinExerciseCatalog) {
    if (bindings[item.key] == exerciseId) meaning = item.loadMeaning;
  }
  final result = suggestLoad(
    history: history,
    target: target,
    unit: prefs.weightUnit,
    step: prefs.weightUnit == WeightUnit.kg ? prefs.kgStep : prefs.lbStep,
    now: now,
    loadMeaning: meaning,
    segmentIndex: segmentIndex,
  );
  return result.withToken(
    jsonEncode([row, detail.toJson(), prefs.token, facts, now ~/ 86400000]),
  );
}

Future<void> applyLoadReference(
  SqlExecutor exec, {
  required String pendingSetId,
  required String expectedToken,
  required int now,
}) => exec.transaction((tx) async {
  final reference = await readLoadReference(tx, pendingSetId, now: now);
  if (reference.token != expectedToken || reference.reading == null) {
    throw const RecordManagementException('参考依据已变化，请重新获取建议');
  }
  final row = await tx.first<Map<String, Object?>>(
    'SELECT se.session_id FROM set_entry st JOIN session_exercise se ON se.id=st.session_exercise_id WHERE st.id=?',
    [pendingSetId],
  );
  if (row == null) throw const RecordManagementException('当前组已变化');
  final pending = await requirePendingSet(
    tx,
    row['session_id'] as String,
    pendingSetId,
  );
  var d = await readSetDetail(tx, pendingSetId);
  if (d.firstCompletedAt != null) {
    d = d.copyWith(pendingReading: reference.reading);
  } else {
    await updateSetValues(
      tx,
      pendingSetId,
      reference.reading!.kilograms,
      pending.reps,
      reading: reference.reading,
    );
  }
  d = d.copyWith(
    reference:
        'personal-v1 · ${reference.reading!.label} · ${reference.message} · ${reference.trend}\n${reference.evidence.join('\n')}',
  );
  await writeSetDetail(tx, pendingSetId, d);
  encodeBackup(await readBackupSnapshot(tx, exportedAt: now));
});
