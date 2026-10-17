import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/migrations.dart';
import 'package:gym_tracker/data/db/sql_executor.dart';
import 'package:gym_tracker/data/repositories/session_repo.dart';
import 'package:gym_tracker/data/repositories/set_repo.dart';
import 'package:gym_tracker/data/repositories/exercise_preferences_repo.dart';
import 'package:gym_tracker/domain/weight_value.dart';

Future<void> createV5(SqlExecutor db, {bool populate = true}) async {
  for (final migration in migrations.where((m) => m.version <= 5)) {
    for (final statement in migration.statements) {
      await db.run(statement);
    }
  }
  await db.run("INSERT INTO app_meta(key,value) VALUES('schema_version','5')");
  if (!populate) return;
  await db.run('''
INSERT INTO exercise(id,name,created_at) VALUES('e1','划船',1);
INSERT INTO split_template(id,name,position,created_at) VALUES('d1','上肢 A',4,1);
INSERT INTO split_template(id,name,position,created_at) VALUES('d2','下肢 B',4,2);
INSERT INTO template_exercise(id,template_id,exercise_id,position) VALUES('i1','d1','e1',0);
INSERT INTO template_exercise(id,template_id,exercise_id,position) VALUES('i2','d1','e1',1);
INSERT INTO session(id,name,started_at,finished_at,template_id) VALUES('s1','原始名称',1,2,'d1');
INSERT INTO session(id,name,started_at,finished_at,template_id) VALUES('s2','已删来源',3,4,'missing');
INSERT INTO session_exercise(id,session_id,exercise_id,position) VALUES('se1','s1','e1',0);
INSERT INTO set_entry(id,session_exercise_id,position,weight,reps,is_completed) VALUES('st1','se1',0,42.5,8,1);
''');
  await db.run(
    'INSERT INTO exercise_preference(exercise_id,weight_step_milli,is_favorite,equipment_note) VALUES(?,?,?,?)',
    ['e1', 1250, 1, '座椅4\n😀  保留空白 '],
  );
}

/// Wrap the executor supplied by transaction, so faulted DDL/data/version writes
/// really run inside the same SQLite transaction as the migration itself.
class FaultExecutor implements SqlExecutor {
  final SqlExecutor inner;
  final String checkpoint;
  FaultExecutor(this.inner, this.checkpoint);
  @override
  Future<T> transaction<T>(Future<T> Function(SqlExecutor tx) action) =>
      inner.transaction((tx) => action(FaultExecutor(tx, checkpoint)));
  @override
  Future<void> run(String sql, [List<Object?>? params]) async {
    if (params == null || params.isEmpty) {
      for (final statement in splitSqlStatements(sql)) {
        await inner.run(statement);
        if (checkpoint == 'alter' &&
            statement.startsWith('ALTER TABLE split_template')) {
          throw StateError('fault after ALTER');
        }
      }
    } else {
      if (checkpoint == 'version' &&
          sql.contains('schema_version') &&
          params.contains('6')) {
        throw StateError('fault before version write');
      }
      await inner.run(sql, params);
      if (checkpoint == 'preference' &&
          sql.startsWith('INSERT INTO exercise_preference_v6')) {
        throw StateError('fault after copying preference');
      }
    }
  }

  @override
  Future<List<T>> all<T>(String sql, [List<Object?>? params]) =>
      inner.all<T>(sql, params);
  @override
  Future<T?> first<T>(String sql, [List<Object?>? params]) =>
      inner.first<T>(sql, params);
}

void main() {
  late FfiExecutor db;
  setUp(() async {
    db = await FfiExecutor.openInMemory();
  });
  tearDown(() async {
    await db.close();
  });

  test('v5 wraps all days once, preserves occurrence IDs/order and original records', () async {
    await createV5(db);
    final beforeDays = await db.all<Map<String, Object?>>(
      'SELECT * FROM split_template ORDER BY position,rowid',
    );
    final beforeItems = await db.all<Map<String, Object?>>(
      'SELECT * FROM template_exercise ORDER BY rowid',
    );
    await migrate(db);
    expect(await getSchemaVersion(db), 6);
    final plans = await db.all<Map<String, Object?>>(
      'SELECT * FROM training_plan',
    );
    expect(plans, hasLength(1));
    expect(plans.single['name'], '我的训练计划');
    final days = await db.all<Map<String, Object?>>(
      'SELECT * FROM split_template ORDER BY position,rowid',
    );
    expect(days.map((r) => r['plan_id']), everyElement(plans.single['id']));
    for (var i = 0; i < days.length; i++) {
      final oldShape = Map<String, Object?>.from(days[i])..remove('plan_id');
      expect(oldShape, beforeDays[i]);
    }
    expect(
      await db.all('SELECT * FROM template_exercise ORDER BY rowid'),
      beforeItems,
    );
    final session = (await getSession(db, 's1'))!;
    expect(session.name, '原始名称');
    expect(session.planId, plans.single['id']);
    expect(session.planNameSnapshot, '我的训练计划');
    expect(session.dayNameSnapshot, '上肢 A');
    expect(session.origin, 'legacy');
    expect(session.copyWith(finishedAt: 7).planId, session.planId);
    expect(
      session.copyWith(finishedAt: 7).dayNameSnapshot,
      session.dayNameSnapshot,
    );
    expect((await getSession(db, 's2'))!.planId, isNull);
    final set = (await listSets(db, 'se1')).single;
    expect(set.weight, 42.5);
    expect(set.recordedWeight, isNull);
    expect(set.equipmentWeight.label, '42.5 kg');
    final pref = (await readExercisePreferences(db, ['e1']))['e1']!;
    expect(pref.kgStep.text, '1.25');
    expect(pref.lbStep.text, '5');
    expect(pref.weightStepMilli, 1250);
    expect(pref.weightUnit, WeightUnit.kg);
    expect(pref.showKgEquivalent, isFalse);
    expect(pref.isFavorite, isTrue);
    expect(pref.equipmentNote, '座椅4\n😀  保留空白 ');
    final snapshot = await db.all('SELECT * FROM training_plan');
    await migrate(db);
    expect(await db.all('SELECT * FROM training_plan'), snapshot);
  });

  test('empty v5 upgrade creates no phantom plan', () async {
    await createV5(db, populate: false);
    await migrate(db);
    expect(await db.all('SELECT * FROM training_plan'), isEmpty);
    expect(await getSchemaVersion(db), 6);
  });

  for (final checkpoint in ['alter', 'preference', 'version']) {
    test(
      'v6 fault at $checkpoint rolls back DDL, preferences and version then retries',
      () async {
        await createV5(db);
        await expectLater(
          migrate(FaultExecutor(db, checkpoint)),
          throwsStateError,
        );
        expect(await getSchemaVersion(db), 5);
        expect(
          await db.first(
            "SELECT name FROM sqlite_master WHERE name='training_plan'",
          ),
          isNull,
        );
        expect(
          await db.first(
            "SELECT name FROM sqlite_master WHERE name='exercise_preference_v6'",
          ),
          isNull,
        );
        final columns = await db.all<Map<String, Object?>>(
          'PRAGMA table_info(session)',
        );
        expect(columns.map((r) => r['name']), isNot(contains('plan_id')));
        final oldPref = await db.first<Map<String, Object?>>(
          'SELECT * FROM exercise_preference',
        );
        expect(oldPref!['weight_step_milli'], 1250);
        expect(oldPref['equipment_note'], '座椅4\n😀  保留空白 ');
        await migrate(db);
        expect(await getSchemaVersion(db), 6);
        expect(await db.all('SELECT * FROM training_plan'), hasLength(1));
      },
    );
  }

  test(
    'new live session snapshots and both set writers retain native lb reading',
    () async {
      await createV5(db);
      await migrate(db);
      final plan =
          (await db.first<Map<String, Object?>>(
                'SELECT id FROM training_plan',
              ))!['id']
              as String;
      final session = await createSession(
        db,
        templateId: 'd2',
        planId: plan,
        planNameSnapshot: '当前计划',
        dayNameSnapshot: '下肢 B',
      );
      final read = (await getSession(db, session.id))!;
      expect(read.origin, 'live');
      expect(read.planId, plan);
      expect(read.planNameSnapshot, '当前计划');
      expect(read.copyWith(finishedAt: 8).origin, 'live');
      final exercise = await addExerciseToSession(db, session.id, 'e1');
      var set = await addSet(
        db,
        exercise.id,
        50 * 0.45359237,
        8,
        reading: EquipmentWeight(DecimalReading.parse('50'), WeightUnit.lb),
      );
      expect(set.equipmentWeight.label, '50 lb');
      expect(set.weight, closeTo(22.6796185, 1e-12));
      await updateSetValues(
        db,
        set.id,
        52.5 * 0.45359237,
        10,
        reading: EquipmentWeight(DecimalReading.parse('52.5'), WeightUnit.lb),
      );
      set = (await listSets(db, exercise.id)).single;
      expect(set.equipmentWeight.label, '52.5 lb');
      expect(set.weight, closeTo(52.5 * 0.45359237, 1e-12));
      await updateSetValues(db, set.id, 40, 6);
      set = (await listSets(db, exercise.id)).single;
      expect(set.equipmentWeight.label, '40 kg');
      expect(set.weight, 40);
      final lb = EquipmentWeight(DecimalReading.parse('50'), WeightUnit.lb);
      await expectLater(
        addSet(db, exercise.id, 50, 8, reading: lb),
        throwsFormatException,
      );
      await expectLater(
        updateSetValues(db, set.id, 50, 8, reading: lb),
        throwsFormatException,
      );
      for (final invalid in [double.nan, double.infinity, -1.0]) {
        await expectLater(
          addSet(db, exercise.id, invalid, 8),
          throwsFormatException,
        );
        await expectLater(
          updateSetValues(db, set.id, invalid, 8),
          throwsFormatException,
        );
      }
      expect(
        (await listSets(db, exercise.id)).single.equipmentWeight.label,
        '40 kg',
      );
    },
  );
}
