import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/sql_executor.dart';
import 'package:gym_tracker/data/repositories/session_comparison_repo.dart';
import 'package:gym_tracker/data/repositories/session_summary_loader.dart';
import 'package:gym_tracker/data/repositories/set_detail_repo.dart';
import 'package:gym_tracker/data/repositories/set_repo.dart';
import 'package:gym_tracker/domain/set_detail.dart';
import 'package:gym_tracker/domain/training_prescription.dart';
import 'package:gym_tracker/domain/weight_value.dart';

void main() {
  late FfiExecutor db;
  setUp(() async {
    db = await FfiExecutor.openMigrated();
    for (final id in ['bench', 'other-bench', 'row']) {
      await db.run(
        'INSERT INTO exercise(id,name,is_custom,is_archived,created_at) VALUES(?,?,1,0,0)',
        [id, id == 'row' ? '划船' : '卧推'],
      );
    }
  });
  tearDown(() => db.close());

  Future<void> session(
    String id,
    int at, {
    bool finished = true,
    String origin = 'manual',
  }) => db.run(
    'INSERT INTO session(id,name,started_at,finished_at,note,origin) VALUES(?,?,?,?,?,?)',
    [id, '训练-$id', at, finished ? at + 100 : null, '备注-$id', origin],
  );

  Future<String> occurrence(String sid, String eid, int position) async {
    final id = '$sid-$eid-$position';
    await db.run(
      'INSERT INTO session_exercise(id,session_id,exercise_id,position) VALUES(?,?,?,?)',
      [id, sid, eid, position],
    );
    return id;
  }

  Future<String> completed(
    String occurrenceId, {
    double kg = 60,
    int reps = 8,
    EquipmentWeight? reading,
    SetDetail? detail,
  }) async {
    final entry = await addSet(
      db,
      occurrenceId,
      reading?.kilograms ?? kg,
      reps,
      reading: reading,
    );
    await completeSet(db, entry.id, 1);
    if (detail != null) await writeSetDetail(db, entry.id, detail);
    return entry.id;
  }

  Future<void> simple(
    String sid,
    int at, {
    bool finished = true,
    String eid = 'bench',
    String origin = 'manual',
  }) async {
    await session(sid, at, finished: finished, origin: origin);
    await completed(await occurrence(sid, eid, 0));
  }

  test('batch query picks each action baseline by actual training date and stable ID', () async {
    await simple('current', 300, origin: 'live');
    await completed(await occurrence('current', 'row', 1));
    await simple('row-previous', 150, eid: 'row');
    await simple('older', 100);
    await simple('z-nearest', 200, origin: 'csv');
    await simple('a-nearest', 200);
    await simple('future', 400);
    await simple('same-time', 300);
    await simple('running', 250, finished: false);
    await simple('same-name', 270, eid: 'other-bench');
    await session('pending-only', 280);
    await addSet(db, await occurrence('pending-only', 'bench', 0), 999, 99);

    final current = (await loadSessionSummary(db, 'current'))!;
    final counter = CountingExecutor(db);
    final result = await loadSessionComparisons(counter, current);

    expect(result.map((e) => e.exerciseId), ['bench', 'row']);
    expect(result.first.previous!.session.id, 'z-nearest');
    expect(result.first.previous!.session.origin, 'csv');
    expect(result.first.previous!.session.note, '备注-z-nearest');
    expect(result.last.previous!.session.id, 'row-previous');
    expect(
      counter.allQueries,
      1,
      reason: 'One batched query serves both exercise histories.',
    );
    expect(counter.firstQueries, 0);
    expect(counter.writes, 0);
  });

  test('one action retains multiple occurrence boundaries, parent count, source unit and detail', () async {
    await simple('previous', 100);
    await completed(await occurrence('previous', 'bench', 2), kg: 40, reps: 10);
    await session('current', 300);
    final native = EquipmentWeight(DecimalReading.parse('100'), WeightUnit.lb);
    await completed(
      await occurrence('current', 'bench', 0),
      reading: native,
      reps: 5,
      detail: SetDetail(role: 'warmup', effort: const Effort('rir', 3)),
    );
    final segmentedOccurrence = await occurrence('current', 'bench', 2);
    await completed(
      segmentedOccurrence,
      kg: 30,
      reps: 10,
      detail: SetDetail(
        role: 'work',
        target: SetTarget(
          repsMin: 10,
          repsMax: 10,
          extraReps: [5, 4],
          pauseSeconds: 5,
        ),
        firstCompletedAt: 1,
        endedEarly: true,
        continuations: [
          RecordedSegment(
            reading: EquipmentWeight.kg(25),
            reps: 5,
            completedAt: 2,
            pauseSeconds: 5,
          ),
        ],
      ),
    );
    await addSet(db, segmentedOccurrence, 999, 99);
    final current = (await loadSessionSummary(db, 'current'))!;

    final comparison = (await loadSessionComparisons(db, current)).single;

    expect(comparison.current.occurrences, hasLength(2));
    expect(comparison.current.logicalSetCount, 2);
    expect(comparison.current.volumeLoad, closeTo(651.796185, 1e-8));
    expect(comparison.current.volumeLoad, current.volumeLoad);
    expect(
      comparison.current.occurrences.first.sets.single.equipmentWeight.unit,
      WeightUnit.lb,
    );
    expect(
      comparison
          .current
          .occurrences
          .first
          .sets
          .single
          .equipmentWeight
          .amount
          .text,
      '100',
    );
    expect(
      comparison.current.occurrences.first.sets.single.detail!.role,
      'warmup',
    );
    expect(
      comparison.current.occurrences.last.sets.single.detail!.continuations,
      hasLength(1),
    );
    expect(
      comparison
          .current
          .occurrences
          .last
          .sets
          .single
          .detail!
          .continuations
          .single
          .effort,
      isNull,
    );
    expect(
      comparison.current.occurrences.last.sets.single.detail!.endedEarly,
      isTrue,
    );
    expect(comparison.previous!.occurrences, hasLength(2));
    expect(comparison.previous!.logicalSetCount, 2);
    expect(comparison.previous!.volumeLoad, 880);
  });

  test(
    'reload observes edits, deletes and later imports of older sessions',
    () async {
      await simple('previous', 100);
      await simple('current', 300);
      final current = (await loadSessionSummary(db, 'current'))!;
      Future<double> previousVolume() async => (await loadSessionComparisons(
        db,
        current,
      )).single.previous!.volumeLoad;
      expect(await previousVolume(), 480);

      final previousSet =
          (await db.first<Map<String, Object?>>(
                'SELECT st.id FROM set_entry st JOIN session_exercise se ON se.id=st.session_exercise_id WHERE se.session_id=?',
                ['previous'],
              ))!['id']
              as String;
      await updateSetValues(db, previousSet, 50, 5);
      expect(await previousVolume(), 250);

      await simple('backdated-import', 200, origin: 'csv');
      expect(
        (await loadSessionComparisons(db, current)).single.previous!.session.id,
        'backdated-import',
      );
      await db.run('DELETE FROM session WHERE id=?', ['backdated-import']);
      expect(
        (await loadSessionComparisons(db, current)).single.previous!.session.id,
        'previous',
      );
      await db.run('DELETE FROM session WHERE id=?', ['previous']);
      expect(
        (await loadSessionComparisons(db, current)).single.previous,
        isNull,
      );
    },
  );

  test(
    'first records and pending current sessions need no invented baseline',
    () async {
      await simple('first', 100);
      final first = (await loadSessionSummary(db, 'first'))!;
      expect((await loadSessionComparisons(db, first)).single.previous, isNull);
      await simple('running', 200, finished: false);
      final running = (await loadSessionSummary(db, 'running'))!;
      final counter = CountingExecutor(db);
      expect(await loadSessionComparisons(counter, running), isEmpty);
      expect(counter.allQueries, 0);
    },
  );

  test('a previous segmented group is loaded once and archived identities still match', () async {
    await session('previous', 100);
    await completed(
      await occurrence('previous', 'bench', 0),
      kg: 30,
      reps: 10,
      detail: SetDetail(
        target: SetTarget(
          repsMin: 10,
          repsMax: 10,
          extraReps: [5],
          pauseSeconds: 5,
        ),
        firstCompletedAt: 1,
        continuations: [
          RecordedSegment(
            reading: EquipmentWeight.kg(20),
            reps: 5,
            completedAt: 2,
            pauseSeconds: 5,
          ),
        ],
      ),
    );
    await simple('current', 300);
    await db.run('UPDATE exercise SET is_archived=1,name=? WHERE id=?', [
      '改名后的卧推',
      'bench',
    ]);
    final result = (await loadSessionComparisons(
      db,
      (await loadSessionSummary(db, 'current'))!,
    )).single;
    expect(result.exerciseId, 'bench');
    expect(result.exerciseName, '改名后的卧推');
    expect(result.previous!.logicalSetCount, 1);
    expect(result.previous!.volumeLoad, 400);
    expect(
      result.previous!.occurrences.single.sets.single.detail!.role,
      'unknown',
    );
  });
}

class CountingExecutor implements SqlExecutor {
  final SqlExecutor inner;
  int allQueries = 0, firstQueries = 0, writes = 0;
  CountingExecutor(this.inner);
  @override
  Future<List<T>> all<T>(String sql, [List<Object?>? params]) {
    allQueries++;
    return inner.all<T>(sql, params);
  }

  @override
  Future<T?> first<T>(String sql, [List<Object?>? params]) {
    firstQueries++;
    return inner.first<T>(sql, params);
  }

  @override
  Future<void> run(String sql, [List<Object?>? params]) {
    writes++;
    return inner.run(sql, params);
  }

  @override
  Future<T> transaction<T>(Future<T> Function(SqlExecutor tx) action) =>
      inner.transaction((tx) => action(CountingTransactionExecutor(tx, this)));
}

class CountingTransactionExecutor implements SqlExecutor {
  final SqlExecutor inner;
  final CountingExecutor counter;
  CountingTransactionExecutor(this.inner, this.counter);
  @override
  Future<List<T>> all<T>(String sql, [List<Object?>? params]) {
    counter.allQueries++;
    return inner.all<T>(sql, params);
  }

  @override
  Future<T?> first<T>(String sql, [List<Object?>? params]) {
    counter.firstQueries++;
    return inner.first<T>(sql, params);
  }

  @override
  Future<void> run(String sql, [List<Object?>? params]) {
    counter.writes++;
    return inner.run(sql, params);
  }

  @override
  Future<T> transaction<T>(Future<T> Function(SqlExecutor tx) action) => inner
      .transaction((tx) => action(CountingTransactionExecutor(tx, counter)));
}
