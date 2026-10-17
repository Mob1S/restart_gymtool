import '../../domain/weight_value.dart';
import '../ids.dart';
import 'sql_executor.dart';

/// Run only on the executor scoped to the version-six transaction.
Future<void> migrateTrainingV6(SqlExecutor tx) async {
  await tx.run('''
CREATE TABLE training_plan (
 id TEXT PRIMARY KEY, name TEXT NOT NULL,
 position INTEGER NOT NULL, created_at INTEGER NOT NULL
);
ALTER TABLE split_template ADD COLUMN plan_id TEXT;
ALTER TABLE session ADD COLUMN plan_id TEXT;
ALTER TABLE session ADD COLUMN plan_name_snapshot TEXT;
ALTER TABLE session ADD COLUMN day_name_snapshot TEXT;
ALTER TABLE session ADD COLUMN origin TEXT NOT NULL DEFAULT 'legacy';
ALTER TABLE set_entry ADD COLUMN source_weight TEXT;
ALTER TABLE set_entry ADD COLUMN source_unit TEXT NOT NULL DEFAULT 'kg'
 CHECK(source_unit IN ('kg','lb'));
CREATE INDEX idx_template_plan ON split_template(plan_id,position);
CREATE INDEX idx_session_plan_finished ON session(plan_id,finished_at);
CREATE INDEX idx_session_started_finished ON session(started_at,finished_at);
CREATE TABLE exercise_preference_v6 (
 exercise_id TEXT PRIMARY KEY REFERENCES exercise(id) ON DELETE CASCADE,
 weight_unit TEXT NOT NULL DEFAULT 'kg' CHECK(weight_unit IN ('kg','lb')),
 kg_step TEXT NOT NULL DEFAULT '2.5',
 lb_step TEXT NOT NULL DEFAULT '5',
 show_kg_equivalent INTEGER NOT NULL DEFAULT 0 CHECK(show_kg_equivalent IN (0,1)),
 is_favorite INTEGER NOT NULL DEFAULT 0 CHECK(is_favorite IN (0,1)),
 equipment_note TEXT NOT NULL DEFAULT '' CHECK(length(equipment_note)<=500)
);
''');
  final preferences = await tx.all<Map<String, Object?>>(
    'SELECT * FROM exercise_preference ORDER BY rowid',
  );
  for (final row in preferences) {
    final step = DecimalReading.parse(
      ((row['weight_step_milli'] as int) / 1000).toString(),
    );
    await tx.run(
      'INSERT INTO exercise_preference_v6 '
      '(exercise_id,kg_step,is_favorite,equipment_note) VALUES (?,?,?,?)',
      [
        row['exercise_id'],
        step.text,
        row['is_favorite'],
        row['equipment_note'],
      ],
    );
  }
  await tx.run('''
DROP TABLE exercise_preference;
ALTER TABLE exercise_preference_v6 RENAME TO exercise_preference;
''');
  final templates = await tx.all<Map<String, Object?>>(
    'SELECT id FROM split_template ORDER BY position,rowid',
  );
  if (templates.isEmpty) return;
  final planId = await ensureLegacyTrainingPlan(tx);
  await tx.run('UPDATE split_template SET plan_id=?', [planId]);
  await tx.run(
    '''UPDATE session SET plan_id=?,
    plan_name_snapshot='我的训练计划',
    day_name_snapshot=(SELECT name FROM split_template WHERE id=session.template_id)
    WHERE template_id IN (SELECT id FROM split_template)''',
    [planId],
  );
}

/// Compatibility entry point for old single-day-template callers.
/// The caller owns the transaction; this function never opens another one.
Future<String> ensureLegacyTrainingPlan(SqlExecutor tx) async {
  final first = await tx.first<Map<String, Object?>>(
    'SELECT id FROM training_plan ORDER BY position,rowid LIMIT 1',
  );
  if (first != null) return first['id'] as String;
  final id = newId();
  await tx.run(
    'INSERT INTO training_plan(id,name,position,created_at) VALUES (?,?,0,?)',
    [id, '我的训练计划', DateTime.now().millisecondsSinceEpoch],
  );
  return id;
}
