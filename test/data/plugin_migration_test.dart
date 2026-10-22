import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/migrations.dart';
import 'package:gym_tracker/data/db/training_v6_migration.dart';
import 'package:gym_tracker/data/repositories/plugin_state_repo.dart';

import 'backup_repo_test.dart' show FailingExecutor;

void main() {
  late FfiExecutor exec;
  setUp(() async => exec = await FfiExecutor.openInMemory());
  tearDown(() => exec.close());

  test(
    'fresh migration enables only required training and preserves choices',
    () async {
      // Android's SQLite driver can create this before the application schema.
      await exec.run('CREATE TABLE android_metadata(locale TEXT)');
      await migrate(exec);
      expect(await loadPluginPreferences(exec), {
        'gym.training': true,
        'gym.calories': false,
        'gym.motion': false,
      });
      await savePluginPreference(exec, 'gym.calories', true);
      await migrate(exec);
      expect((await loadPluginPreferences(exec))['gym.calories'], true);
      await expectLater(
        savePluginPreference(exec, 'gym.training', false),
        throwsArgumentError,
      );
    },
  );

  test('schema 11 empty legacy install retains all features', () async {
    // Build the published schema without running plugin initialization.
    for (final item in migrations.where((item) => item.version <= 11)) {
      if (item.version == 6) {
        await migrateTrainingV6(exec);
        continue;
      }
      for (final statement in item.statements) {
        await exec.run(statement);
      }
    }
    await exec.run(
      "INSERT INTO app_meta(key,value) VALUES('schema_version','11')",
    );
    await migrate(exec);
    expect(await loadPluginPreferences(exec), {
      'gym.training': true,
      'gym.calories': true,
      'gym.motion': true,
    });
  });

  test('origin survives interrupted historical migration retry', () async {
    final faulty = FailingExecutor(
      exec,
      'CREATE TABLE IF NOT EXISTS exercise',
      StateError('interrupted'),
    );
    await expectLater(migrate(faulty), throwsStateError);
    expect(
      (await exec.first<Map<String, Object?>>(
        "SELECT value FROM app_meta WHERE key='plugin_install_origin'",
      ))?['value'],
      'fresh',
    );
    await migrate(exec);
    expect((await loadPluginPreferences(exec))['gym.motion'], false);
  });

  test('schema 12 tables defaults and version roll back together', () async {
    await migrate(exec);
    await exec.run('DROP TABLE plugin_document');
    await exec.run('DROP TABLE plugin_data_version');
    await exec.run('DROP TABLE plugin_state');
    await exec.run("UPDATE app_meta SET value='11' WHERE key='schema_version'");
    final faulty = FailingExecutor(
      exec,
      "INSERT INTO app_meta(key,value) VALUES('schema_version'",
      StateError('version'),
    );
    await expectLater(migrate(faulty), throwsStateError);
    expect(await getSchemaVersion(exec), 11);
    expect(
      await exec.first(
        "SELECT name FROM sqlite_master WHERE name='plugin_state'",
      ),
      isNull,
    );
    await migrate(exec);
    expect((await loadPluginPreferences(exec))['gym.calories'], false);
  });
}
