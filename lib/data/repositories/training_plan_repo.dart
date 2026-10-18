import 'dart:convert';

import '../../domain/plans.dart';
import '../../domain/backup_codec.dart';
import '../../domain/training_plans.dart';
import '../../domain/local_date.dart';
import '../db/sql_executor.dart';
import '../ids.dart';
import 'template_repo.dart';
import 'backup_repo.dart';

Future<List<TrainingPlanDetail>> listTrainingPlans(SqlExecutor exec) =>
    exec.transaction(readTrainingPlans);

/// Transaction-scoped read, also used by atomic workout selection.
Future<List<TrainingPlanDetail>> readTrainingPlans(SqlExecutor tx) async {
  final rows = await tx.all<Map<String, Object?>>(
    'SELECT id FROM training_plan ORDER BY position,rowid',
  );
  return [
    for (final row in rows) (await readTrainingPlan(tx, row['id'] as String))!,
  ];
}

Future<TrainingPlanDetail?> getTrainingPlan(SqlExecutor exec, String id) =>
    exec.transaction((tx) => readTrainingPlan(tx, id));

Future<TrainingPlanDetail?> readTrainingPlan(SqlExecutor tx, String id) async {
  final row = await tx.first<Map<String, Object?>>(
    'SELECT * FROM training_plan WHERE id=?',
    [id],
  );
  if (row == null) return null;
  final children = await tx.all<Map<String, Object?>>(
    'SELECT id FROM split_template WHERE plan_id=? ORDER BY position,rowid',
    [id],
  );
  final details = <TemplateDetail>[];
  for (final child in children) {
    details.add((await readTemplate(tx, child['id'] as String))!);
  }
  return TrainingPlanDetail(
    id: id,
    name: row['name'] as String,
    position: row['position'] as int,
    createdAt: row['created_at'] as int,
    activatedOn: LocalDate.tryParse(row['activated_on'] as String?),
    token: jsonEncode([row, for (final day in details) day.editToken]),
    days: [
      for (final day in details)
        TrainingDay(
          id: day.template.id,
          name: day.template.name,
          kind: day.template.kind,
          exerciseIds: [
            for (final item in day.exercises) item.entry.exerciseId,
          ],
        ),
    ],
  );
}

Future<TrainingPlanDetail> saveTrainingPlan(
  SqlExecutor exec,
  TrainingPlanDraft draft,
) => exec.transaction((tx) async {
  final name = draft.name.trim();
  if (name.isEmpty) throw const PlanValidationException('请输入训练计划名称');
  if (draft.days.length > 100000 ||
      draft.days.fold<int>(0, (n, day) => n + day.exerciseIds.length) >
          100000) {
    throw const PlanValidationException('计划内容过多');
  }
  final old = draft.id == null ? null : await readTrainingPlan(tx, draft.id!);
  if (draft.id != null && (old == null || old.token != draft.expectedToken)) {
    throw const PlanValidationException('训练计划已变化，请重新载入');
  }
  final existingDays = {
    for (final day in old?.days ?? <TrainingDay>[]) day.id: day,
  };
  final retained = <String>{};
  final oldDetails = <String, TemplateDetail>{};
  final exercises = await tx.all<Map<String, Object?>>(
    'SELECT id,is_archived FROM exercise',
  );
  final available = {
    for (final row in exercises) row['id'] as String: row['is_archived'] == 1,
  };
  // Validate everything before allocating IDs or writing any part of the draft.
  for (final day in draft.days) {
    if (day.kind == TrainingDayKind.rest && day.exerciseIds.isNotEmpty) {
      throw const PlanValidationException('休息日不能包含动作');
    }
    if (day.name.trim().isEmpty) {
      throw const PlanValidationException('请输入训练日名称');
    }
    if (day.id != null &&
        (!existingDays.containsKey(day.id) || !retained.add(day.id!))) {
      throw const PlanValidationException('训练日已变化，请重新载入');
    }
    final allowances = <String, int>{};
    if (day.id != null) {
      final detail = (await readTemplate(tx, day.id!))!;
      oldDetails[day.id!] = detail;
      for (final item in detail.exercises) {
        allowances.update(
          item.entry.exerciseId,
          (n) => n + 1,
          ifAbsent: () => 1,
        );
      }
    }
    for (final exerciseId in day.exerciseIds) {
      if (!available.containsKey(exerciseId)) {
        throw const PlanValidationException('动作已不存在，请重新选择');
      }
      final remaining = allowances[exerciseId] ?? 0;
      if (available[exerciseId]! && remaining == 0) {
        throw const PlanValidationException('不能新增已归档动作');
      }
      if (remaining > 0) allowances[exerciseId] = remaining - 1;
    }
  }
  final id = draft.id ?? newId();
  if (old == null) {
    final max = await tx.first<Map<String, Object?>>(
      'SELECT MAX(position) AS p FROM training_plan',
    );
    await tx.run(
      'INSERT INTO training_plan(id,name,position,created_at) VALUES(?,?,?,?)',
      [
        id,
        name,
        ((max?['p'] as int?) ?? -1) + 1,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
  } else {
    await tx.run('UPDATE training_plan SET name=? WHERE id=?', [name, id]);
  }
  for (final removed in existingDays.keys.where(
    (id) => !retained.contains(id),
  )) {
    await tx.run('UPDATE session SET template_id=NULL WHERE template_id=?', [
      removed,
    ]);
    await tx.run('DELETE FROM template_exercise WHERE template_id=?', [
      removed,
    ]);
    await tx.run('DELETE FROM split_template WHERE id=?', [removed]);
  }
  for (var position = 0; position < draft.days.length; position++) {
    final day = draft.days[position];
    final dayId = day.id ?? newId();
    if (day.id == null) {
      await tx.run(
        'INSERT INTO split_template(id,name,position,created_at,plan_id,kind) VALUES(?,?,?,?,?,?)',
        [
          dayId,
          day.name.trim(),
          position,
          DateTime.now().millisecondsSinceEpoch,
          id,
          day.kind.name,
        ],
      );
    } else {
      await tx.run(
        'UPDATE split_template SET name=?,position=?,kind=? WHERE id=?',
        [day.name.trim(), position, day.kind.name, dayId],
      );
    }
    final queues = <String, List<String>>{};
    for (final item in oldDetails[dayId]?.exercises ?? <TemplateItem>[]) {
      queues.putIfAbsent(item.entry.exerciseId, () => []).add(item.entry.id);
    }
    for (var index = 0; index < day.exerciseIds.length; index++) {
      final exerciseId = day.exerciseIds[index];
      final queue = queues[exerciseId];
      if (queue != null && queue.isNotEmpty) {
        await tx.run('UPDATE template_exercise SET position=? WHERE id=?', [
          index,
          queue.removeAt(0),
        ]);
      } else {
        await tx.run(
          'INSERT INTO template_exercise(id,template_id,exercise_id,position) VALUES(?,?,?,?)',
          [newId(), dayId, exerciseId, index],
        );
      }
    }
    for (final removed in queues.values.expand((ids) => ids)) {
      await tx.run('DELETE FROM template_exercise WHERE id=?', [removed]);
    }
  }
  encodeBackup(await readBackupSnapshot(tx, exportedAt: 0));
  return (await readTrainingPlan(tx, id))!;
});

/// Home selection starts leading rest exactly once. Listing/editing never does.
Future<void> activateTrainingPlan(
  SqlExecutor exec,
  String id, {
  required LocalDate today,
}) => exec.transaction((tx) async {
  await tx.run(
    'UPDATE training_plan SET activated_on=? WHERE id=? AND activated_on IS NULL',
    [today.key, id],
  );
  encodeBackup(await readBackupSnapshot(tx, exportedAt: 0));
});

Future<void> deleteTrainingPlan(
  SqlExecutor exec,
  String id, {
  required String expectedToken,
}) => exec.transaction((tx) async {
  final current = await readTrainingPlan(tx, id);
  if (current == null || current.token != expectedToken) {
    throw const PlanValidationException('训练计划已变化，请重新确认');
  }
  await tx.run(
    'UPDATE session SET plan_id=NULL,template_id=NULL WHERE plan_id=? OR template_id IN '
    '(SELECT id FROM split_template WHERE plan_id=?)',
    [id, id],
  );
  await tx.run(
    'DELETE FROM template_exercise WHERE template_id IN (SELECT id FROM split_template WHERE plan_id=?)',
    [id],
  );
  await tx.run('DELETE FROM split_template WHERE plan_id=?', [id]);
  await tx.run('DELETE FROM training_plan WHERE id=?', [id]);
  final remaining = await tx.all<Map<String, Object?>>(
    'SELECT id FROM training_plan ORDER BY position,rowid',
  );
  for (var i = 0; i < remaining.length; i++) {
    await tx.run('UPDATE training_plan SET position=? WHERE id=?', [
      i,
      remaining[i]['id'],
    ]);
  }
});

Future<bool> moveTrainingPlan(
  SqlExecutor exec,
  String id,
  int direction, {
  required String expectedOrderToken,
}) => exec.transaction((tx) async {
  if (direction != -1 && direction != 1) {
    throw const PlanValidationException('移动方向无效');
  }
  final plans = await readTrainingPlans(tx);
  if (trainingPlanOrderToken(plans) != expectedOrderToken) {
    throw const PlanValidationException('计划顺序已变化，请重新载入');
  }
  final ids = plans.map((plan) => plan.id).toList();
  final current = ids.indexOf(id);
  if (current < 0 ||
      current + direction < 0 ||
      current + direction >= ids.length) {
    return false;
  }
  ids.insert(current + direction, ids.removeAt(current));
  for (var i = 0; i < ids.length; i++) {
    await tx.run('UPDATE training_plan SET position=? WHERE id=?', [i, ids[i]]);
  }
  encodeBackup(await readBackupSnapshot(tx, exportedAt: 0));
  return true;
});
