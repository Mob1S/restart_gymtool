import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/migrations.dart';
import 'package:gym_tracker/data/repositories/video_review_repo.dart';
import 'package:gym_tracker/data/repositories/backup_repo.dart';

import '../support/workout_faults.dart';

void main() {
  late FfiExecutor db;
  late VideoReviewRepo repo;
  setUp(() async {
    db = await FfiExecutor.openMigrated();
    repo = VideoReviewRepo(db);
    await db.run(
      "INSERT INTO exercise(id,name,is_custom,is_archived,created_at) VALUES('e','Bench',1,0,0)",
    );
    await db.run("INSERT INTO session(id,started_at) VALUES('s',0)");
    await db.run(
      "INSERT INTO session_exercise(id,session_id,exercise_id,position) VALUES('se','s','e',0)",
    );
    await db.run(
      "INSERT INTO set_entry(id,session_exercise_id,position,weight,reps,is_completed) VALUES('st','se',0,60,8,1),('pending','se',1,60,0,0)",
    );
  });
  tearDown(() => db.close());
  test('failed restore rolls back cascaded review deletion', () async {
    await repo.save('st', 'private-media', {'result': 'old'});
    final snapshot = await exportBackup(db, exportedAt: 1);
    final preview = await inspectBackup(db, snapshot);
    final fault = WorkoutFaultExecutor(
      db,
      WorkoutFaults()..runPrefix = 'INSERT INTO session ',
    );
    await expectLater(restoreBackup(fault, preview), throwsStateError);
    expect((await repo.load('st'))!['result'], 'old');
    expect((await repo.group('st'))!['reps'], 8);
  });
  test(
    'successful backup restore retains projects and clears set links',
    () async {
      final snapshot = await exportBackup(db, exportedAt: 1);
      await repo.save('st', 'private-media', {'result': 'old'});
      await restoreBackup(db, await inspectBackup(db, snapshot));
      expect(await repo.folders(), ['private-media']);
      expect(await repo.load('st'), isNull);
      expect((await repo.group('st'))!['reps'], 8);
    },
  );
  test('v8 upgrade preserves existing training and is repeatable', () async {
    await db.run('DROP TABLE motion_project');
    await db.run('DROP TABLE video_review');
    await db.run("UPDATE app_meta SET value='8' WHERE key='schema_version'");
    await migrate(db);
    await migrate(db);
    expect(await getSchemaVersion(db), 11);
    expect((await repo.group('st'))!['weight'], 60.0);
    await repo.save('st', 'new', {'result': 'new'});
    expect(await repo.load('st'), isNotNull);
  });
  test(
    'new schema and saved review survive reload; original set unchanged',
    () async {
      expect(await getSchemaVersion(db), 11);
      await repo.save('st', 'folder1', {'result': 'a'});
      await repo.save('st', 'folder2', {'result': 'b'});
      expect((await repo.load('st'))!['folder'], 'folder2');
      expect(await repo.folders(), ['folder2']);
      expect((await repo.group('st'))!['reps'], 8);
    },
  );
  test('reject missing and unfinished sets', () async {
    await expectLater(repo.save('pending', 'x', {}), throwsStateError);
    await expectLater(repo.save('missing', 'x', {}), throwsStateError);
    expect(await repo.folders(), isEmpty);
  });
  test(
    'deleting a session removes associations, rollback preserves them',
    () async {
      await repo.save('st', 'f', {'result': 'a'});
      await expectLater(
        db.transaction((tx) async {
          await tx.run("DELETE FROM session WHERE id='s'");
          throw StateError('rollback');
        }),
        throwsStateError,
      );
      expect(await repo.load('st'), isNotNull);
      await db.run("DELETE FROM session WHERE id='s'");
      expect(await repo.load('st'), isNull);
    },
  );
  test(
    'JSON backup includes beverage schema 11 and excludes local media',
    () async {
      await repo.save('st', 'private-media', {'result': 'private-result'});
      final backup = await exportBackup(db, exportedAt: 1);
      expect(backup.schemaVersion, 11);
      expect(backup.version, 7);
      expect(backup.toJson().toString(), isNot(contains('private-media')));
    },
  );
}
