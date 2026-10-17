import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/sql_executor.dart';
import 'package:gym_tracker/data/repositories/training_plan_repo.dart';
import 'package:gym_tracker/data/repositories/workout_plan_repo.dart';
import 'package:gym_tracker/domain/plans.dart';
import 'package:gym_tracker/domain/training_plans.dart';

class _FailSecondExercise implements SqlExecutor {
  final SqlExecutor inner;
  final List<int> count;
  _FailSecondExercise(this.inner, [List<int>? count]) : count = count ?? [0];
  @override
  Future<T> transaction<T>(Future<T> Function(SqlExecutor tx) action) =>
      inner.transaction((tx) => action(_FailSecondExercise(tx, count)));
  @override
  Future<void> run(String sql, [List<Object?>? params]) async {
    await inner.run(sql, params);
    if (sql.startsWith('INSERT INTO template_exercise') && ++count[0] == 2) {
      throw StateError('second day insert failed');
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
    db = await FfiExecutor.openMigrated();
    await db.run(
      "INSERT INTO exercise(id,name,is_custom,is_archived,created_at) VALUES('e','Bench',1,0,0),('f','Squat',1,0,0)",
    );
  });
  tearDown(() => db.close());
  Future<TrainingPlanDetail> makePlan(String name, int days) =>
      saveTrainingPlan(
        db,
        TrainingPlanDraft(
          name: name,
          days: [
            for (var i = 0; i < days; i++)
              TrainingDayDraft(name: '$name${i + 1}', exerciseIds: ['e']),
          ],
        ),
      );
  Future<void> complete(
    String id,
    TrainingPlanDetail plan,
    String? day,
    int time, {
    String origin = 'live',
    bool active = false,
    int? startedAt,
  }) => db.run(
    'INSERT INTO session(id,started_at,finished_at,plan_id,template_id,origin,plan_name_snapshot,day_name_snapshot) VALUES(?,?,?,?,?,?,?,?)',
    [
      id,
      startedAt ?? time - 1,
      active ? null : time,
      plan.id,
      day,
      origin,
      plan.name,
      day,
    ],
  );

  test(
    'completion rotation is per plan and uses finished time and source',
    () async {
      final a = await makePlan('A', 3);
      final b = await makePlan('B', 2);
      await complete('a2', a, a.days[1].id, 100);
      expect(
        (await loadNextWorkout(db, planId: a.id)).templateId,
        a.days[2].id,
      );
      expect(
        (await loadNextWorkout(db, planId: b.id)).templateId,
        b.days.first.id,
      );
      await complete('active', a, a.days.last.id, 200, active: true);
      await complete('manual', a, a.days.last.id, 201, origin: 'manual');
      await complete('csv', a, a.days.last.id, 202, origin: 'csv');
      await db.run(
        "INSERT INTO session(id,started_at,finished_at,origin) VALUES('free',203,204,'live')",
      );
      expect(
        (await loadNextWorkout(db, planId: a.id)).templateId,
        a.days.last.id,
      );
      await complete('b2', b, b.days.last.id, 300);
      expect(
        (await loadNextWorkout(db, planId: b.id)).templateId,
        b.days.first.id,
      );
      await complete(
        'oldStartedNewFinished',
        a,
        a.days.last.id,
        400,
        startedAt: 1,
      );
      expect(
        (await loadNextWorkout(db, planId: a.id)).templateId,
        a.days.first.id,
      );
      await db.run("DELETE FROM session WHERE id='oldStartedNewFinished'");
      expect(
        (await loadNextWorkout(db, planId: a.id)).templateId,
        a.days.last.id,
      );
    },
  );

  test(
    'an in-progress day never becomes the completion source for rotation',
    () async {
      final plan = await makePlan('Three days', 3);
      await complete('active-b', plan, plan.days[1].id, 200, active: true);

      // With no completion yet, even an ongoing second day must leave the
      // recommendation at the first day. Removing the finished filter would
      // incorrectly treat active-b as a completion and recommend the third.
      expect(
        (await loadNextWorkout(db, planId: plan.id)).templateId,
        plan.days.first.id,
      );

      await complete('finished-a', plan, plan.days.first.id, 100);
      expect(
        (await loadNextWorkout(db, planId: plan.id)).templateId,
        plan.days[1].id,
      );
      final activeRows = await db.all<Map<String, Object?>>(
        'SELECT id,template_id FROM session WHERE finished_at IS NULL',
      );
      expect(activeRows, hasLength(1));
      expect(activeRows.single['id'], 'active-b');
      expect(activeRows.single['template_id'], plan.days[1].id);
    },
  );

  test(
    'latest deleted day returns to first instead of using older history',
    () async {
      final a = await makePlan('A', 3);
      await complete('older', a, a.days.first.id, 20);
      await complete('latest', a, a.days.last.id, 30);
      final updated = await saveTrainingPlan(
        db,
        TrainingPlanDraft(
          id: a.id,
          expectedToken: a.token,
          name: a.name,
          days: [a.days[0].toDraft(), a.days[1].toDraft()],
        ),
      );
      final latest = await db.first<Map<String, Object?>>(
        "SELECT * FROM session WHERE id='latest'",
      );
      expect(latest!['template_id'], isNull);
      expect(latest['plan_id'], a.id);
      expect(latest['day_name_snapshot'], a.days.last.id);
      expect(
        (await loadNextWorkout(db, planId: a.id)).templateId,
        updated.days.first.id,
      );
    },
  );

  test(
    'names, day IDs and repeated occurrence IDs survive reordering',
    () async {
      final plan = await saveTrainingPlan(
        db,
        TrainingPlanDraft(
          name: 'A',
          days: [
            TrainingDayDraft(name: 'One', exerciseIds: ['e', 'f', 'e']),
            TrainingDayDraft(name: 'Two', exerciseIds: ['f']),
          ],
        ),
      );
      final original = await db.all<Map<String, Object?>>(
        'SELECT * FROM template_exercise WHERE template_id=? ORDER BY position',
        [plan.days.first.id],
      );
      final edited = await saveTrainingPlan(
        db,
        TrainingPlanDraft(
          id: plan.id,
          expectedToken: plan.token,
          name: 'Renamed',
          days: [
            plan.days.last.toDraft(),
            TrainingDayDraft(
              id: plan.days.first.id,
              name: 'New One',
              exerciseIds: ['e', 'e', 'f'],
            ),
          ],
        ),
      );
      expect(edited.days.map((day) => day.id), [
        plan.days.last.id,
        plan.days.first.id,
      ]);
      final reordered = await db.all<Map<String, Object?>>(
        'SELECT * FROM template_exercise WHERE template_id=? ORDER BY position',
        [plan.days.first.id],
      );
      expect(reordered.map((row) => row['id']), [
        original[0]['id'],
        original[2]['id'],
        original[1]['id'],
      ]);
      await expectLater(
        saveTrainingPlan(db, plan.toDraft()),
        throwsA(isA<PlanValidationException>()),
      );
      expect((await getTrainingPlan(db, plan.id))!.name, 'Renamed');
    },
  );

  test('archived occurrences may remain but cannot be added or copied to another day', () async {
    final plan = await saveTrainingPlan(
      db,
      TrainingPlanDraft(
        name: 'A',
        days: [
          TrainingDayDraft(name: 'One', exerciseIds: ['e', 'e']),
        ],
      ),
    );
    await db.run("UPDATE exercise SET is_archived=1 WHERE id='e'");
    final refreshed = (await getTrainingPlan(db, plan.id))!;
    final kept = await saveTrainingPlan(db, refreshed.toDraft());
    await expectLater(
      saveTrainingPlan(
        db,
        TrainingPlanDraft(
          id: kept.id,
          expectedToken: kept.token,
          name: 'A',
          days: [
            TrainingDayDraft(
              id: kept.days.single.id,
              name: 'One',
              exerciseIds: ['e', 'e', 'e'],
            ),
          ],
        ),
      ),
      throwsA(isA<PlanValidationException>()),
    );
    await expectLater(
      saveTrainingPlan(
        db,
        TrainingPlanDraft(
          name: 'New',
          days: [
            TrainingDayDraft(name: 'Day', exerciseIds: ['e']),
          ],
        ),
      ),
      throwsA(isA<PlanValidationException>()),
    );
  });

  test(
    'failure in second day rolls back all writes and preserves library',
    () async {
      final plan = await makePlan('A', 1);
      final rows = await db.all<Map<String, Object?>>(
        'SELECT * FROM template_exercise',
      );
      await expectLater(
        saveTrainingPlan(
          _FailSecondExercise(db),
          TrainingPlanDraft(
            id: plan.id,
            expectedToken: plan.token,
            name: 'Changed',
            days: [
              plan.days.single.toDraft(),
              TrainingDayDraft(name: 'B', exerciseIds: ['f']),
              TrainingDayDraft(name: 'C', exerciseIds: ['e']),
            ],
          ),
        ),
        throwsStateError,
      );
      expect((await getTrainingPlan(db, plan.id))!.token, plan.token);
      expect(
        await db.all<Map<String, Object?>>('SELECT * FROM template_exercise'),
        rows,
      );
      expect(await db.all('SELECT * FROM exercise'), hasLength(2));
    },
  );

  test('delete parent detaches references but preserves sessions sets and snapshots', () async {
    final plan = await makePlan('A', 1);
    await complete('s', plan, plan.days.single.id, 20);
    await db.run(
      "INSERT INTO session_exercise(id,session_id,exercise_id,position) VALUES('se','s','e',0)",
    );
    await db.run(
      "INSERT INTO set_entry(id,session_exercise_id,position,weight,reps,is_completed) VALUES('set','se',0,40,8,1)",
    );
    await expectLater(
      deleteTrainingPlan(db, plan.id, expectedToken: 'stale'),
      throwsA(isA<PlanValidationException>()),
    );
    await deleteTrainingPlan(db, plan.id, expectedToken: plan.token);
    final session = (await db.first<Map<String, Object?>>(
      "SELECT * FROM session WHERE id='s'",
    ))!;
    expect(session['plan_id'], isNull);
    expect(session['template_id'], isNull);
    expect(session['plan_name_snapshot'], 'A');
    expect(await db.all('SELECT * FROM set_entry'), hasLength(1));
    expect(await db.all('SELECT * FROM exercise'), hasLength(2));
    expect(await listTrainingPlans(db), isEmpty);
  });

  test(
    'no plan is free, zero days stays distinguishable and aliases validate',
    () async {
      expect((await loadNextWorkout(db)).freeTraining, isTrue);
      final empty = await makePlan('Empty', 0);
      final selection = await loadNextWorkout(db, planId: empty.id);
      expect(selection.planId, empty.id);
      expect(selection.hasUsableDay, isFalse);
      expect(selection.freeTraining, isFalse);
      final plan = await makePlan('Other', 2);
      expect(
        (await loadNextWorkout(
          db,
          preferredTemplateId: plan.days.last.id,
        )).planId,
        plan.id,
      );
      expect((await loadNextWorkout(db, freeTraining: true)).planId, isNull);
      await expectLater(
        loadNextWorkout(
          db,
          preferredDayId: plan.days.first.id,
          preferredTemplateId: plan.days.last.id,
        ),
        throwsA(isA<PlanValidationException>()),
      );
      await expectLater(
        loadNextWorkout(
          db,
          planId: empty.id,
          preferredDayId: plan.days.first.id,
        ),
        throwsA(isA<PlanValidationException>()),
      );
    },
  );

  test('selection token detects completion and day edits; manual choice does not advance', () async {
    final plan = await makePlan('A', 2);
    final initial = await loadNextWorkout(db, planId: plan.id);
    expect(
      (await loadNextWorkout(
        db,
        planId: plan.id,
        preferredDayId: plan.days.last.id,
      )).templateId,
      plan.days.last.id,
    );
    expect(
      (await loadNextWorkout(db, planId: plan.id)).selectionToken,
      initial.selectionToken,
    );
    await complete('s', plan, plan.days.first.id, 20, origin: 'legacy');
    final finished = await loadNextWorkout(db, planId: plan.id);
    expect(finished.selectionToken, isNot(initial.selectionToken));
    await saveTrainingPlan(
      db,
      TrainingPlanDraft(
        id: plan.id,
        expectedToken: plan.token,
        name: plan.name,
        days: plan.days.reversed.map((day) => day.toDraft()).toList(),
      ),
    );
    final reordered = await loadNextWorkout(db, planId: plan.id);
    expect(reordered.templateId, plan.days.last.id);
    expect(reordered.selectionToken, isNot(finished.selectionToken));
  });

  test(
    'parent reorder uses a conflict token and retains independent days',
    () async {
      final a = await makePlan('A', 2);
      final b = await makePlan('B', 1);
      final order = trainingPlanOrderToken(await listTrainingPlans(db));
      expect(
        await moveTrainingPlan(db, b.id, -1, expectedOrderToken: order),
        isTrue,
      );
      expect((await listTrainingPlans(db)).map((plan) => plan.id), [
        b.id,
        a.id,
      ]);
      expect((await loadNextWorkout(db)).planId, b.id);
      expect(
        (await getTrainingPlan(db, a.id))!.days.map((day) => day.id),
        a.days.map((day) => day.id),
      );
      await expectLater(
        moveTrainingPlan(db, a.id, -1, expectedOrderToken: order),
        throwsA(isA<PlanValidationException>()),
      );
    },
  );

  test('invalid child ownership, duplicate IDs and missing actions never partially save', () async {
    final a = await makePlan('A', 1);
    final b = await makePlan('B', 1);
    for (final days in <List<TrainingDayDraft>>[
      [b.days.single.toDraft()],
      [a.days.single.toDraft(), a.days.single.toDraft()],
      [TrainingDayDraft(name: ' ', exerciseIds: [])],
      [
        TrainingDayDraft(name: 'Bad', exerciseIds: ['missing']),
      ],
    ]) {
      await expectLater(
        saveTrainingPlan(
          db,
          TrainingPlanDraft(
            id: a.id,
            expectedToken: a.token,
            name: 'Changed',
            days: days,
          ),
        ),
        throwsA(isA<PlanValidationException>()),
      );
      expect((await getTrainingPlan(db, a.id))!.token, a.token);
    }
  });

  test('free training can reuse last completed actions without retaining its source', () async {
    final plan = await makePlan('A', 1);
    await complete('s', plan, plan.days.single.id, 20);
    await db.run(
      "INSERT INTO session_exercise(id,session_id,exercise_id,position) VALUES('se','s','e',0)",
    );
    final free = await loadNextWorkout(db, freeTraining: true);
    expect(free.exerciseIds, ['e']);
    expect(free.planId, isNull);
    expect(free.templateId, isNull);
  });
}
