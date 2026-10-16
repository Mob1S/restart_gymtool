import 'dart:convert';

import '../../domain/plans.dart';
import '../../domain/backup_codec.dart';
import '../db/sql_executor.dart';
import '../ids.dart';
import 'backup_repo.dart';

SplitTemplate _template(Map<String, Object?> row) => SplitTemplate(
  id: row['id'] as String,
  name: row['name'] as String,
  position: row['position'] as int,
  createdAt: row['created_at'] as int,
);

Future<List<TemplateSummary>> listTemplates(SqlExecutor exec) =>
    exec.transaction(readTemplates);
Future<List<TemplateSummary>> readTemplates(SqlExecutor tx) async {
  final rows = await tx.all<Map<String, Object?>>(
    'SELECT t.*, COUNT(te.id) AS exercise_count FROM split_template t LEFT JOIN template_exercise te ON te.template_id=t.id GROUP BY t.id ORDER BY t.position ASC,t.rowid ASC',
  );
  return [
    for (final r in rows)
      TemplateSummary(_template(r), r['exercise_count'] as int),
  ];
}

Future<TemplateDetail?> getTemplate(SqlExecutor exec, String id) =>
    exec.transaction((tx) => readTemplate(tx, id));
Future<TemplateDetail?> readTemplate(SqlExecutor tx, String id) async {
  final row = await tx.first<Map<String, Object?>>(
    'SELECT * FROM split_template WHERE id=?',
    [id],
  );
  if (row == null) return null;
  final items = await tx.all<Map<String, Object?>>(
    'SELECT te.*,e.name,e.is_archived FROM template_exercise te JOIN exercise e ON e.id=te.exercise_id WHERE te.template_id=? ORDER BY te.position ASC,te.rowid ASC',
    [id],
  );
  final token = jsonEncode([row, items]);
  return TemplateDetail(_template(row), [
    for (final e in items)
      TemplateItem(
        TemplateExercise(
          id: e['id'] as String,
          templateId: id,
          exerciseId: e['exercise_id'] as String,
          position: e['position'] as int,
        ),
        e['name'] as String,
        e['is_archived'] == 1,
      ),
  ], token);
}

Future<TemplateDetail> saveTemplate(
  SqlExecutor exec,
  TemplateDraft draft,
) => exec.transaction((tx) async {
  final name = draft.name.trim();
  if (name.isEmpty) throw const PlanValidationException('请输入计划名称');
  if (draft.exerciseIds.length > 100000) {
    throw const PlanValidationException('计划动作过多');
  }
  final existing = draft.id == null ? null : await readTemplate(tx, draft.id!);
  if (draft.id != null &&
      (existing == null || existing.editToken != draft.expectedToken)) {
    throw const PlanValidationException('计划已变化，请重新载入');
  }
  final available = await tx.all<Map<String, Object?>>(
    'SELECT id FROM exercise',
  );
  final ids = {for (final r in available) r['id']};
  if (draft.exerciseIds.any((id) => !ids.contains(id))) {
    throw const PlanValidationException('动作已不存在，请重新选择');
  }
  final id = draft.id ?? newId();
  if (existing == null) {
    final max = await tx.first<Map<String, Object?>>(
      'SELECT MAX(position) AS p FROM split_template',
    );
    await tx.run(
      'INSERT INTO split_template(id,name,position,created_at) VALUES(?,?,?,?)',
      [
        id,
        name,
        ((max?['p'] as int?) ?? -1) + 1,
        DateTime.now().millisecondsSinceEpoch,
      ],
    );
  } else {
    await tx.run('UPDATE split_template SET name=? WHERE id=?', [name, id]);
    await tx.run('DELETE FROM template_exercise WHERE template_id=?', [id]);
  }
  for (var i = 0; i < draft.exerciseIds.length; i++) {
    await tx.run(
      'INSERT INTO template_exercise(id,template_id,exercise_id,position) VALUES(?,?,?,?)',
      [newId(), id, draft.exerciseIds[i], i],
    );
  }
  encodeBackup(await readBackupSnapshot(tx, exportedAt: 0));
  return (await readTemplate(tx, id))!;
});
Future<void> _renumber(SqlExecutor tx, List<String> ids) async {
  for (var i = 0; i < ids.length; i++) {
    await tx.run('UPDATE split_template SET position=? WHERE id=?', [
      i,
      ids[i],
    ]);
  }
}

Future<bool> moveTemplate(
  SqlExecutor exec,
  String id,
  int direction,
  String expectedOrderToken,
) => exec.transaction((tx) async {
  if (direction != -1 && direction != 1) {
    throw const PlanValidationException('移动方向无效');
  }
  final list = await readTemplates(tx);
  if (templateOrderToken(list) != expectedOrderToken) {
    throw const PlanValidationException('计划顺序已变化，请重新载入');
  }
  final ids = list.map((t) => t.template.id).toList();
  final i = ids.indexOf(id);
  if (i < 0 || i + direction < 0 || i + direction >= ids.length) return false;
  final moved = ids.removeAt(i);
  ids.insert(i + direction, moved);
  await _renumber(tx, ids);
  return true;
});
Future<TemplateDeletePreview?> inspectTemplateDeletion(
  SqlExecutor exec,
  String id,
) => exec.transaction((tx) => _inspectDeletion(tx, id));
Future<TemplateDeletePreview?> _inspectDeletion(
  SqlExecutor tx,
  String id,
) async {
  final detail = await readTemplate(tx, id);
  if (detail == null) return null;
  final references = await tx.all<Map<String, Object?>>(
    'SELECT id,finished_at FROM session WHERE template_id=? ORDER BY rowid ASC',
    [id],
  );
  return TemplateDeletePreview(
    id,
    detail.template.name,
    detail.exercises.length,
    references.where((r) => r['finished_at'] != null).length,
    references.where((r) => r['finished_at'] == null).length,
    jsonEncode([detail.editToken, references]),
  );
}

Future<TemplateDeleteResult> deleteTemplate(
  SqlExecutor exec,
  TemplateDeletePreview preview,
) => exec.transaction((tx) async {
  final current = await _inspectDeletion(tx, preview.id);
  if (current == null) return const TemplateDeleteResult(false, 0, 0);
  if (current.token != preview.token) {
    throw const PlanValidationException('计划或关联训练已变化，请重新确认');
  }
  await tx.run('UPDATE session SET template_id=NULL WHERE template_id=?', [
    preview.id,
  ]);
  await tx.run('DELETE FROM split_template WHERE id=?', [preview.id]);
  await _renumber(
    tx,
    (await readTemplates(tx)).map((e) => e.template.id).toList(),
  );
  return TemplateDeleteResult(
    true,
    current.completedReferences,
    current.activeReferences,
  );
});
