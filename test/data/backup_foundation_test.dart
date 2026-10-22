import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/migrations.dart';
import 'package:gym_tracker/data/db/schema.dart';
import 'package:gym_tracker/data/repositories/exercise_repo.dart';

import 'backup_repo_test.dart' show FailingExecutor;

void main() {
  late FfiExecutor exec;
  setUp(() async => exec = await FfiExecutor.openInMemory());
  tearDown(() async => exec.close());

  test(
    'nested transaction rejects promptly and rolls back outer writes',
    () async {
      await migrate(exec);
      await expectLater(
        exec
            .transaction((tx) async {
              await tx.run("INSERT INTO app_setting VALUES ('test','outer')");
              await tx.transaction((_) async {});
            })
            .timeout(const Duration(seconds: 3)),
        throwsStateError,
      );
      expect(await exec.all('SELECT * FROM app_setting'), isEmpty);
    },
  );

  test(
    'existing custom exercise only gets the initialization marker',
    () async {
      await migrate(exec);
      await exec.run(
        "INSERT INTO exercise (id,name,is_custom,is_archived,created_at) VALUES ('kept','保留',1,0,1)",
      );
      await seedExercisesIfEmpty(exec);
      expect(
        (await exec.all<Map<String, Object?>>('SELECT id FROM exercise'))
            .single['id'],
        'kept',
      );
      expect(
        await exec.first(
          "SELECT value FROM app_meta WHERE key='seed_initialized'",
        ),
        {'value': '1'},
      );
    },
  );

  test('seed insertion failure rolls back both exercises and marker', () async {
    await migrate(exec);
    final failure = StateError('seed');
    await expectLater(
      seedExercisesIfEmpty(
        FailingExecutor(exec, 'INSERT INTO exercise', failure),
      ),
      throwsA(same(failure)),
    );
    expect(await exec.all('SELECT * FROM exercise'), isEmpty);
    expect(
      await exec.first(
        "SELECT value FROM app_meta WHERE key='seed_initialized'",
      ),
      isNull,
    );
  });

  test(
    'transaction failure rolls back every insert and preserves the error',
    () async {
      await migrate(exec);
      final failure = StateError('injected');
      await expectLater(
        exec.transaction<void>((tx) async {
          await tx.run(
            "INSERT INTO exercise (id,name,is_custom,is_archived,created_at) VALUES ('new','新动作',1,0,1)",
          );
          throw failure;
        }),
        throwsA(same(failure)),
      );
      expect(await exec.all('SELECT * FROM exercise'), isEmpty);
    },
  );

  test('v3 upgrades to v4 without changing existing sessions', () async {
    await exec.run(createMetaSql);
    for (final migration in migrations.where((item) => item.version <= 3)) {
      for (final sql in migration.statements) {
        await exec.run(sql);
      }
    }
    await exec.run("INSERT INTO app_meta VALUES ('schema_version','3')");
    await exec.run("INSERT INTO session (id,started_at) VALUES ('kept',123)");
    expect(
      await exec.all(
        "SELECT name FROM sqlite_master WHERE name='split_template'",
      ),
      isEmpty,
    );
    await migrate(exec);
    expect(await getSchemaVersion(exec), schemaVersion);
    await exec.run(
      "INSERT INTO split_template (id,name,position,created_at) VALUES ('p','推日',0,1)",
    );
    expect(
      (await exec.first<Map<String, Object?>>('SELECT id FROM session'))!['id'],
      'kept',
    );
    expect(await exec.all('PRAGMA foreign_key_check'), isEmpty);
  });

  test('an intentionally empty restored database is not reseeded', () async {
    await migrate(exec);
    await exec.run("INSERT INTO app_meta VALUES ('seed_initialized','1')");
    await seedExercisesIfEmpty(exec);
    expect(await listExercises(exec), isEmpty);
  });

  test('first seed records initialization and remains idempotent', () async {
    await migrate(exec);
    await seedExercisesIfEmpty(exec);
    await seedExercisesIfEmpty(exec);
    expect(await listExercises(exec), hasLength(52));
    expect(
      (await exec.first<Map<String, Object?>>(
        "SELECT value FROM app_meta WHERE key='seed_initialized'",
      ))!['value'],
      '1',
    );
  });
}
