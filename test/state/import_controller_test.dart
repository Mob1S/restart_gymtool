import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/migrations.dart';
import 'package:gym_tracker/data/files/backup_file_store.dart';
import 'package:gym_tracker/state/import_controller.dart';
import 'package:gym_tracker/domain/workout_csv.dart';

import '../support/backup_fakes.dart';

void main() {
  late FfiExecutor db;
  late MemoryBackupFiles files;
  late ImportController c;
  var calls = 0;
  setUp(() async {
    db = await FfiExecutor.openInMemory();
    await migrate(db);
    files = MemoryBackupFiles();
    calls = 0;
    c = ImportController(
      exec: db,
      files: files,
      onCommitted: (_) async {
        calls++;
      },
    );
    files.selected = PickedBackup(
      'input.csv',
      utf8.encode('Date,Exercise Name,Weight,Reps\n2024-01-01,Bench,100,8'),
    );
  });
  tearDown(() async {
    c.dispose();
    await db.close();
  });
  test(
    'unit reparse uses original values; double commit inserts once',
    () async {
      expect(await c.selectCsv(), true);
      await c.changeUnit(WeightUnit.lb);
      await c.changeUnit(WeightUnit.kg);
      expect(
        c.confirmed!.workouts.single.exercises.single.sets.single.weight,
        100,
      );
      final first = c.commit();
      final second = c.commit();
      expect(await second, ImportCommitOutcome.notCommitted);
      expect(await first, ImportCommitOutcome.committed);
      expect(calls, 1);
      expect(await db.all('SELECT * FROM session'), hasLength(1));
      expect(c.confirmed, isNull);
    },
  );
  test('cancel prevents late file selection from restoring preview', () async {
    final pending = Completer<PickedBackup?>();
    files.choose = () => pending.future;
    final task = c.selectCsv();
    c.cancel();
    pending.complete(files.selected);
    expect(await task, false);
    expect(c.draft, isNull);
    expect(c.busy, false);
  });
  test('callback failure is committed and cannot be retried', () async {
    c.dispose();
    c = ImportController(
      exec: db,
      files: files,
      onCommitted: (_) async {
        throw StateError('refresh');
      },
    );
    await c.selectCsv();
    expect(await c.commit(), ImportCommitOutcome.refreshFailed);
    expect(c.message, contains('已导入'));
    expect(await c.commit(), ImportCommitOutcome.notCommitted);
    expect(await db.all('SELECT * FROM session'), hasLength(1));
  });
}
