import '../../domain/training_prescription.dart';
import '../../domain/set_detail.dart';
import '../../domain/plans.dart';
import '../../domain/backup_codec.dart';
import '../db/sql_executor.dart';
import 'backup_repo.dart';

Future<TrainingProgram?> readTrainingProgram(
  SqlExecutor tx,
  String planId,
) async {
  final row = await tx.first<Map<String, Object?>>(
    'SELECT payload FROM training_program WHERE id=?',
    [planId],
  );
  return row == null ? null : TrainingProgram.decode(row['payload'] as String);
}

Future<void> writeTrainingProgram(
  SqlExecutor tx,
  String planId,
  TrainingProgram program,
) async {
  TrainingProgram.decode(program.encode());
  final rows = await tx.all<Map<String, Object?>>(
    'SELECT te.id FROM template_exercise te JOIN split_template t ON t.id=te.template_id WHERE t.plan_id=?',
    [planId],
  );
  final ids = rows.map((r) => r['id']).toSet();
  if (program.stages.any(
    (s) => s.targets.keys.any((id) => !ids.contains(id)),
  )) {
    throw const PlanValidationException('目标动作不属于当前计划，请重新载入');
  }
  await tx.run(
    'INSERT INTO training_program(id,payload) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload',
    [planId, program.encode()],
  );
}

Future<void> saveTrainingProgram(
  SqlExecutor exec,
  String planId,
  TrainingProgram program, {
  String? expectedPayload,
}) => exec.transaction((tx) async {
  final old = await readTrainingProgram(tx, planId);
  if (old?.encode() != expectedPayload) {
    throw const PlanValidationException('训练处方已变化，请重新载入');
  }
  await writeTrainingProgram(tx, planId, program);
  encodeBackup(await readBackupSnapshot(tx, exportedAt: 0));
});
Future<void> selectProgramStage(
  SqlExecutor exec,
  String planId,
  String stageId, {
  required String expectedPayload,
}) => exec.transaction((tx) async {
  final p = await readTrainingProgram(tx, planId);
  if (p == null ||
      p.encode() != expectedPayload ||
      !p.stages.any((s) => s.id == stageId)) {
    throw const PlanValidationException('计划阶段已变化，请重新载入');
  }
  await writeTrainingProgram(tx, planId, p.select(stageId));
  encodeBackup(await readBackupSnapshot(tx, exportedAt: 0));
});
Future<void> pruneTrainingProgram(SqlExecutor tx, String planId) async {
  final p = await readTrainingProgram(tx, planId);
  if (p == null) return;
  final rows = await tx.all<Map<String, Object?>>(
    'SELECT te.id FROM template_exercise te JOIN split_template t ON t.id=te.template_id WHERE t.plan_id=?',
    [planId],
  );
  await writeTrainingProgram(
    tx,
    planId,
    p.prune(rows.map((r) => r['id'] as String).toSet()),
  );
}

Future<SessionPrescription?> readSessionPrescription(
  SqlExecutor tx,
  String id,
) async {
  final row = await tx.first<Map<String, Object?>>(
    'SELECT payload FROM session_prescription WHERE id=?',
    [id],
  );
  return row == null
      ? null
      : SessionPrescription.decode(row['payload'] as String);
}

Future<void> installPendingTarget(
  SqlExecutor tx,
  String sessionExerciseId,
  int index,
) async {
  final snapshot = await readSessionPrescription(tx, sessionExerciseId);
  if (snapshot == null) return;
  final target = index < snapshot.targets.length
      ? snapshot.targets[index]
      : null;
  final row = await tx.first<Map<String, Object?>>(
    'SELECT id FROM set_entry WHERE session_exercise_id=? AND is_completed=0 ORDER BY position LIMIT 1',
    [sessionExerciseId],
  );
  if (row == null) return;
  final id = row['id'] as String;
  if (target != null) {
    await tx.run('UPDATE set_entry SET reps=? WHERE id=?', [
      target.repsMin,
      id,
    ]);
  }
  final d = SetDetail(
    role: target?.role ?? 'work',
    target: target,
    targetIndex: index,
  );
  await tx.run(
    'INSERT INTO set_detail(id,payload) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload',
    [id, d.encode()],
  );
}

Future<void> snapshotWorkoutProgram(
  SqlExecutor tx,
  String planId,
  String dayId,
  String sessionId,
) async {
  final p = await readTrainingProgram(tx, planId);
  if (p == null) return;
  final plan = await tx.first<Map<String, Object?>>(
    'SELECT name FROM training_plan WHERE id=?',
    [planId],
  );
  final day = await tx.first<Map<String, Object?>>(
    'SELECT name FROM split_template WHERE id=?',
    [dayId],
  );
  final occurrences = await tx.all<Map<String, Object?>>(
    'SELECT id FROM template_exercise WHERE template_id=? ORDER BY position,rowid',
    [dayId],
  );
  final actual = await tx.all<Map<String, Object?>>(
    'SELECT id FROM session_exercise WHERE session_id=? ORDER BY position,rowid',
    [sessionId],
  );
  if (occurrences.length != actual.length) {
    throw const PlanValidationException('计划动作已变化');
  }
  for (var i = 0; i < actual.length; i++) {
    final targets =
        p.current.targets[occurrences[i]['id']] ?? const <SetTarget>[];
    final snapshot = SessionPrescription(
      stageId: p.current.id,
      stageName: p.current.name,
      planName: plan!['name'] as String,
      dayName: day!['name'] as String,
      targets: targets,
    );
    final id = actual[i]['id'] as String;
    await tx.run('INSERT INTO session_prescription(id,payload) VALUES(?,?)', [
      id,
      snapshot.encode(),
    ]);
    await installPendingTarget(tx, id, 0);
  }
}
