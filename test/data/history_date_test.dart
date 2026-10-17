import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/repositories/session_repo.dart';
import 'package:gym_tracker/data/repositories/csv_export_repo.dart';
import 'package:gym_tracker/domain/local_date.dart';

void main() {
  late FfiExecutor db;
  setUp(() async {
    db = await FfiExecutor.openMigrated();
  });
  tearDown(() async {
    await db.close();
  });

  test('history day filters use local midnight boundaries and retain zero-set sessions', () async {
    final date = LocalDate(2026, 10, 16);
    final start = date.start.millisecondsSinceEpoch;
    final next = date.nextStart.millisecondsSinceEpoch;
    for (final row in <(String, int, int?)>[
      ('before', start - 1, start),
      ('first', start, start + 1),
      ('last', next - 1, next),
      ('after', next, next + 1),
      ('active', start + 1, null),
    ]) {
      await db.run(
        'INSERT INTO session(id,started_at,finished_at) VALUES (?,?,?)',
        [row.$1, row.$2, row.$3],
      );
    }
    final rows = await listSessionSummaries(db, date: date);
    expect(rows.map((r) => r.session.id), ['last', 'first']);
    expect(rows.every((r) => r.setCount == 0 && r.volumeLoad == 0), isTrue);
    expect(await listCompletedTrainingDates(db, date), contains(date.key));
    await db.run("DELETE FROM session WHERE id IN ('first','last')");
    expect(
      await listCompletedTrainingDates(db, date),
      isNot(contains(date.key)),
    );
  });

  test(
    'CSV export respects date range and preserves lb source with unrounded kg',
    () async {
      final date = LocalDate(2026, 10, 16);
      await db.run(
        "INSERT INTO exercise(id,name,is_custom,is_archived,created_at) VALUES('e','Cable',1,0,0)",
      );
      await db.run(
        'INSERT INTO session(id,started_at,finished_at) VALUES (?,?,?)',
        [
          's',
          date.start.millisecondsSinceEpoch,
          date.nextStart.millisecondsSinceEpoch,
        ],
      );
      await db.run(
        "INSERT INTO session_exercise(id,session_id,exercise_id,position) VALUES('se','s','e',0)",
      );
      await db.run(
        "INSERT INTO set_entry(id,session_exercise_id,position,weight,reps,is_completed,source_weight,source_unit) VALUES('st','se',0,22.6796185,8,1,'50','lb')",
      );
      final rows = await readWorkoutCsvRows(
        db,
        startInclusive: date.start.millisecondsSinceEpoch,
        endExclusive: date.nextStart.millisecondsSinceEpoch,
      );
      expect(rows.single.reading.label, '50 lb');
      expect(rows.single.reading.kilograms, closeTo(22.6796185, 1e-12));
      expect(
        await readWorkoutCsvRows(
          db,
          startInclusive: date.nextStart.millisecondsSinceEpoch,
        ),
        isEmpty,
      );
    },
  );
}
