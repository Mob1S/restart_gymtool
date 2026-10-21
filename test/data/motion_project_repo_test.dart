import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/migrations.dart';
import 'package:gym_tracker/data/repositories/motion_project_repo.dart';
import 'package:gym_tracker/data/repositories/backup_repo.dart';

import '../support/workout_faults.dart';

void main() {
  late FfiExecutor db;
  late MotionProjectRepo repo;
  setUp(() async {
    db = await FfiExecutor.openMigrated();
    repo = MotionProjectRepo(db);
    await db.run(
      "INSERT INTO exercise(id,name,created_at) VALUES('e','Bench',0)",
    );
    await db.run("INSERT INTO session(id,started_at) VALUES('s',0)");
    await db.run(
      "INSERT INTO session_exercise(id,session_id,exercise_id,position) VALUES('se','s','e',0)",
    );
    await db.run(
      "INSERT INTO set_entry(id,session_exercise_id,position,weight,reps,is_completed) VALUES('st','se',0,60,8,1)",
    );
  });
  tearDown(() => db.close());
  Future<void> save(String id, {String? setId}) => repo.save(
    id: id,
    setId: setId,
    mode: 'import',
    folder: 'media-$id',
    payload: {'result': 'result-$id', 'version': 2},
  );
  test('independent project reload and link conflict are atomic', () async {
    await save('a');
    expect((await repo.load('a'))!['setId'], isNull);
    await save('a', setId: 'st');
    await save('b');
    await expectLater(save('b', setId: 'st'), throwsStateError);
    expect((await repo.load('b'))!['setId'], isNull);
    expect((await repo.forSet('st'))!['id'], 'a');
  });
  test('set deletion unlinks and keeps managed media', () async {
    await save('a', setId: 'st');
    await db.run("DELETE FROM session WHERE id='s'");
    expect((await repo.load('a'))!['setId'], isNull);
    expect(await repo.resultFiles(), {'media-a': 'result-a'});
  });
  test(
    'cleanup retains every observation result in a multi-view project',
    () async {
      await repo.save(
        id: 'multi',
        mode: 'import',
        folder: 'side',
        payload: {
          'version': 3,
          'result': 'side-result',
          'observations': [
            {
              'id': 'a',
              'view': 'side',
              'folder': 'side',
              'result': 'side-result',
            },
            {
              'id': 'b',
              'view': 'front',
              'folder': 'front',
              'result': 'front-result',
            },
          ],
        },
      );
      expect((await repo.load('multi'))!['observations'], hasLength(2));
      expect(await repo.resultFiles(), {
        'side': 'side-result',
        'front': 'front-result',
      });
    },
  );
  test('restore retains projects, unlinks even matching IDs, rollback preserves link', () async {
    await save('a', setId: 'st');
    final preview = await inspectBackup(
      db,
      await exportBackup(db, exportedAt: 0),
    );
    final fault = WorkoutFaultExecutor(
      db,
      WorkoutFaults()..runPrefix = 'INSERT INTO session ',
    );
    await expectLater(restoreBackup(fault, preview), throwsStateError);
    expect((await repo.load('a'))!['setId'], 'st');
    await restoreBackup(db, preview);
    expect((await repo.load('a'))!['setId'], isNull);
    expect(await repo.resultFiles(), {'media-a': 'result-a'});
  });
  test('v9 migration preserves payload and folder, can be repeated', () async {
    await db.run('DROP TABLE motion_project');
    await db.run(
      "INSERT INTO video_review(set_id,folder,payload) VALUES('st','old-folder','{\"result\":\"old-result\",\"reps\":[[0,100,100,200]]}')",
    );
    await db.run("UPDATE app_meta SET value='9' WHERE key='schema_version'");
    await migrate(db);
    await migrate(db);
    final p = await repo.forSet('st');
    expect(p!['folder'], 'old-folder');
    expect(p['result'], 'old-result');
    expect(p['reps'], [
      [0, 100, 100, 200],
    ]);
    expect((await repo.list()).length, 1);
  });
}
