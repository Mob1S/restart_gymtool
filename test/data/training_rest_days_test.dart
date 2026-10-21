import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/migrations.dart';
import 'package:gym_tracker/data/db/training_v6_migration.dart';
import 'package:gym_tracker/data/repositories/training_plan_repo.dart';
import 'package:gym_tracker/data/repositories/workout_plan_repo.dart';
import 'package:gym_tracker/domain/local_date.dart';
import 'package:gym_tracker/domain/plans.dart';
import 'package:gym_tracker/domain/training_plans.dart';
import 'package:gym_tracker/domain/training_schedule.dart';
import 'package:gym_tracker/state/active_session_controller.dart';

import 'training_v6_migration_test.dart' show createV5, FaultExecutor;

void main() {
  late FfiExecutor db;
  setUp(() async {
    db = await FfiExecutor.openMigrated();
  });
  tearDown(() => db.close());
  Future<TrainingPlanDetail> make({bool leading = false}) => saveTrainingPlan(
    db,
    TrainingPlanDraft(
      name: '周期',
      days: [
        if (leading)
          TrainingDayDraft(
            name: '前导休息',
            kind: TrainingDayKind.rest,
            exerciseIds: [],
          ),
        TrainingDayDraft(name: '推', exerciseIds: []),
        TrainingDayDraft(
          name: '休息',
          kind: TrainingDayKind.rest,
          exerciseIds: [],
        ),
        TrainingDayDraft(name: '腿', exerciseIds: []),
      ],
    ),
  );
  Future<void> complete(
    TrainingPlanDetail plan, {
    String origin = 'live',
    String id = 'done',
    DateTime? at,
  }) => db.run(
    'INSERT INTO session(id,started_at,finished_at,plan_id,template_id,origin) VALUES(?,?,?,?,?,?)',
    [
      id,
      DateTime(2026, 10, 17, 23).millisecondsSinceEpoch,
      (at ?? DateTime(2026, 10, 18, 0, 30)).millisecondsSinceEpoch,
      plan.id,
      plan.days.first.id,
      origin,
    ],
  );

  test(
    'schema6 migration preserves empty training days and is idempotent',
    () async {
      await db.close();
      db = await FfiExecutor.openInMemory();
      final old = db;
      await createV5(old);
      await old.transaction((tx) async {
        await migrateTrainingV6(tx);
        await tx.run(
          "UPDATE app_meta SET value='6' WHERE key='schema_version'",
        );
      });
      await migrate(old);
      await migrate(old);
      expect(await getSchemaVersion(old), 11);
      expect(
        (await old.all<Map<String, Object?>>("SELECT * FROM split_template"))
            .every((r) => r['kind'] == 'training'),
        isTrue,
      );
      expect(
        (await old.first<Map<String, Object?>>(
          'SELECT * FROM training_plan',
        ))!['activated_on'],
        isNull,
      );
      expect((await old.all('SELECT id FROM template_exercise')).length, 2);
    },
  );
  test('schema7 ALTER failure rolls back all columns and version', () async {
    await db.close();
    db = await FfiExecutor.openInMemory();
    final old = db;
    await createV5(old);
    await old.transaction((tx) async {
      await migrateTrainingV6(tx);
      await tx.run("UPDATE app_meta SET value='6' WHERE key='schema_version'");
    });
    await expectLater(migrate(FaultExecutor(old, 'alter')), throwsStateError);
    expect(await getSchemaVersion(old), 6);
    expect(
      (await old.all<Map<String, Object?>>('PRAGMA table_info(split_template)'))
          .map((r) => r['name']),
      isNot(contains('kind')),
    );
    await migrate(old);
    expect(await getSchemaVersion(old), 11);
  });
  test('editing/listing does not activate and activation fills once', () async {
    final p = await make(leading: true);
    expect((await listTrainingPlans(db)).single.activatedOn, isNull);
    await loadNextWorkout(db, planId: p.id, now: DateTime(2026, 10, 18));
    expect((await getTrainingPlan(db, p.id))!.activatedOn, isNull);
    await activateTrainingPlan(db, p.id, today: LocalDate(2026, 10, 18));
    await activateTrainingPlan(db, p.id, today: LocalDate(2026, 10, 20));
    final activated = (await getTrainingPlan(db, p.id))!;
    expect(
      activated.token,
      p.token,
      reason: 'Activation must not invalidate content drafts',
    );
    expect(activated.activatedOn, LocalDate(2026, 10, 18));
    expect(
      (await loadNextWorkout(
        db,
        planId: p.id,
        now: DateTime(2026, 10, 18),
      )).schedule!.state,
      TrainingScheduleState.rest,
    );
    expect(
      (await loadNextWorkout(
        db,
        planId: p.id,
        now: DateTime(2026, 10, 19),
      )).dayName,
      '推',
    );
  });
  test(
    'rest cannot contain exercises and invalid draft leaves data intact',
    () async {
      final p = await make();
      await expectLater(
        saveTrainingPlan(
          db,
          TrainingPlanDraft(
            id: p.id,
            expectedToken: p.token,
            name: p.name,
            days: [
              TrainingDayDraft(
                name: '坏休息',
                kind: TrainingDayKind.rest,
                exerciseIds: ['missing'],
              ),
            ],
          ),
        ),
        throwsA(isA<PlanValidationException>()),
      );
      expect((await getTrainingPlan(db, p.id))!.token, p.token);
    },
  );
  test(
    'cross-midnight finish determines rest; training waits beyond rest',
    () async {
      final p = await make();
      await complete(p);
      expect(
        (await loadNextWorkout(
          db,
          planId: p.id,
          now: DateTime(2026, 10, 18),
        )).schedule!.state,
        TrainingScheduleState.completed,
      );
      expect(
        (await loadNextWorkout(
          db,
          planId: p.id,
          now: DateTime(2026, 10, 19),
        )).schedule!.state,
        TrainingScheduleState.rest,
      );
      expect(
        (await loadNextWorkout(
          db,
          planId: p.id,
          now: DateTime(2026, 10, 20),
        )).dayName,
        '腿',
      );
      expect(
        (await loadNextWorkout(
          db,
          planId: p.id,
          now: DateTime(2027, 1, 1),
        )).dayName,
        '腿',
      );
    },
  );
  test('manual/csv/free do not advance, plans remain independent', () async {
    final p = await make();
    final b = await make();
    await complete(p, origin: 'manual');
    await complete(p, origin: 'csv', id: 'csv');
    await db.run(
      "INSERT INTO session(id,started_at,finished_at,origin) VALUES('free',1,2,'live')",
    );
    expect((await loadNextWorkout(db, planId: p.id)).dayName, '推');
    await complete(p, id: 'live');
    expect(
      (await loadNextWorkout(
        db,
        planId: p.id,
        now: DateTime(2026, 10, 19),
      )).schedule!.state,
      TrainingScheduleState.rest,
    );
    expect(
      (await loadNextWorkout(
        db,
        planId: b.id,
        now: DateTime(2026, 10, 19),
      )).dayName,
      '推',
    );
  });
  test(
    'manual choice only accepts training; rest cannot start sessions',
    () async {
      final p = await make();
      await complete(p);
      await expectLater(
        loadNextWorkout(db, planId: p.id, preferredDayId: p.days[1].id),
        throwsA(isA<PlanValidationException>()),
      );
      final c = ActiveSessionController(
        db,
        now: () => DateTime(2026, 10, 19).millisecondsSinceEpoch,
      );
      addTearDown(c.dispose);
      expect(await c.startNew(planId: p.id), StartResult.planChanged);
      expect(
        await db.all('SELECT id FROM session WHERE finished_at IS NULL'),
        isEmpty,
      );
      final selected = await loadNextWorkout(
        db,
        planId: p.id,
        preferredDayId: p.days.last.id,
        now: DateTime(2026, 10, 19),
      );
      expect(selected.hasUsableDay, isTrue);
      expect(
        await c.startNew(
          planId: p.id,
          preferredDayId: p.days.last.id,
          selectionToken: selected.selectionToken,
        ),
        StartResult.started,
      );
    },
  );
  test(
    'midnight invalidates old start token; no duplicate active workout',
    () async {
      final p = await make();
      final previous = await loadNextWorkout(
        db,
        planId: p.id,
        now: DateTime(2026, 10, 18, 23, 59),
      );
      final c = ActiveSessionController(
        db,
        now: () => DateTime(2026, 10, 19).millisecondsSinceEpoch,
      );
      addTearDown(c.dispose);
      expect(
        await c.startNew(planId: p.id, selectionToken: previous.selectionToken),
        StartResult.planChanged,
      );
      expect(await db.all('SELECT id FROM session'), isEmpty);
      expect(await c.startNew(planId: p.id), StartResult.started);
      final id = c.session!.id;
      expect(await c.startNew(planId: p.id), StartResult.conflict);
      expect(c.session!.id, id);
    },
  );
  test('conversion retains historical references and reordering follows stable IDs', () async {
    final p = await make();
    await complete(p);
    final converted = await saveTrainingPlan(
      db,
      TrainingPlanDraft(
        id: p.id,
        expectedToken: p.token,
        name: '新名称',
        days: [
          TrainingDayDraft(
            id: p.days.first.id,
            name: '原上肢休息',
            kind: TrainingDayKind.rest,
            exerciseIds: [],
          ),
          p.days.last.toDraft(),
          p.days[1].toDraft(),
        ],
      ),
    );
    expect(converted.days.first.id, p.days.first.id);
    expect(
      (await db.first<Map<String, Object?>>(
        "SELECT template_id FROM session WHERE id='done'",
      ))!['template_id'],
      p.days.first.id,
    );
    expect(
      (await loadNextWorkout(
        db,
        planId: p.id,
        now: DateTime(2026, 10, 19),
      )).dayName,
      '腿',
    );
    final allRest = await saveTrainingPlan(
      db,
      TrainingPlanDraft(
        id: p.id,
        expectedToken: converted.token,
        name: converted.name,
        days: [
          for (final d in converted.days)
            TrainingDayDraft(
              id: d.id,
              name: d.name,
              kind: TrainingDayKind.rest,
              exerciseIds: [],
            ),
        ],
      ),
    );
    expect(allRest.days.every((d) => d.kind == TrainingDayKind.rest), isTrue);
    expect(
      (await loadNextWorkout(
        db,
        planId: p.id,
        now: DateTime(2026, 10, 18),
      )).schedule!.state,
      TrainingScheduleState.completed,
    );
    expect(
      (await loadNextWorkout(
        db,
        planId: p.id,
        now: DateTime(2026, 10, 19),
      )).dayName,
      '腿',
    );
    expect(
      (await loadNextWorkout(
        db,
        planId: p.id,
        now: DateTime(2026, 10, 20),
      )).dayName,
      '休息',
    );
  });
  test(
    'deleting latest session recalculates from remaining completion',
    () async {
      final p = await make();
      await complete(p, id: 'older');
      await db.run(
        'INSERT INTO session(id,started_at,finished_at,plan_id,template_id,origin) VALUES(?,?,?,?,?,?)',
        [
          'newer',
          DateTime(2026, 10, 19).millisecondsSinceEpoch,
          DateTime(2026, 10, 19, 12).millisecondsSinceEpoch,
          p.id,
          p.days.last.id,
          'live',
        ],
      );
      expect(
        (await loadNextWorkout(
          db,
          planId: p.id,
          now: DateTime(2026, 10, 19),
        )).dayName,
        '推',
      );
      await db.run("DELETE FROM session WHERE id='newer'");
      expect(
        (await loadNextWorkout(
          db,
          planId: p.id,
          now: DateTime(2026, 10, 19),
        )).schedule!.state,
        TrainingScheduleState.rest,
      );
    },
  );
  test(
    'legacy completion anchors schedule without writing a new activation date',
    () async {
      final p = await make();
      await complete(p);
      await activateTrainingPlan(db, p.id, today: LocalDate(2026, 10, 19));
      expect((await getTrainingPlan(db, p.id))!.activatedOn, isNull);
      await db.run("DELETE FROM session WHERE id='done'");
      await activateTrainingPlan(db, p.id, today: LocalDate(2026, 10, 20));
      expect(
        (await getTrainingPlan(db, p.id))!.activatedOn,
        LocalDate(2026, 10, 20),
      );
    },
  );
  test(
    'removing completed day uses original activation with current leading rest',
    () async {
      var p = await make();
      await activateTrainingPlan(db, p.id, today: LocalDate(2026, 10, 18));
      p = (await getTrainingPlan(db, p.id))!;
      await complete(p);
      await saveTrainingPlan(
        db,
        TrainingPlanDraft(
          id: p.id,
          expectedToken: p.token,
          name: p.name,
          days: p.days.skip(1).map((d) => d.toDraft()).toList(),
        ),
      );
      expect(
        (await loadNextWorkout(
          db,
          planId: p.id,
          now: DateTime(2026, 10, 18),
        )).schedule!.state,
        TrainingScheduleState.rest,
      );
      expect(
        (await loadNextWorkout(
          db,
          planId: p.id,
          now: DateTime(2026, 10, 19),
        )).dayName,
        '腿',
      );
    },
  );
}
