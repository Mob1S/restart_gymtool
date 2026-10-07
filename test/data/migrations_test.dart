import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/migrations.dart';
import 'package:gym_tracker/data/db/schema.dart';

void main() {
  late FfiExecutor exec;

  setUp(() async {
    exec = await FfiExecutor.openInMemory();
  });

  tearDown(() async {
    await exec.close();
  });

  test('全新库版本号为 0', () async {
    expect(await getSchemaVersion(exec), 0);
  });

  test('migrate 后版本号升到当前版本', () async {
    await migrate(exec);
    expect(await getSchemaVersion(exec), schemaVersion);
  });

  test('migrate 是幂等的 —— 跑两次结果一样', () async {
    await migrate(exec);
    await migrate(exec);
    expect(await getSchemaVersion(exec), schemaVersion);
  });

  test('迁移后四张表 + app_meta 都在', () async {
    await migrate(exec);
    final rows = await exec.all<Map<String, Object?>>(
      "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
    );
    final names = rows.map((r) => r['name'] as String).toSet();
    expect(names, containsAll(<String>[
      'app_meta',
      'exercise',
      'session',
      'session_exercise',
      'set_entry',
    ]));
  });

  test('三行索引都建出来了（漏了会退化成全表扫描）', () async {
    await migrate(exec);
    final rows = await exec.all<Map<String, Object?>>(
      "SELECT name FROM sqlite_master WHERE type = 'index' AND name LIKE 'idx_%'",
    );
    final names = rows.map((r) => r['name'] as String).toSet();
    expect(names, containsAll(<String>[
      'idx_session_finished',
      'idx_session_exercise_session',
      'idx_set_entry_session_exercise',
    ]));
  });

  test('外键级联生效 —— 删 session 会带走它的 session_exercise', () async {
    await migrate(exec);
    await exec.run(
      "INSERT INTO exercise (id, name, is_custom, is_archived, created_at) VALUES ('e1', '深蹲', 0, 0, 1)",
    );
    await exec.run(
      "INSERT INTO session (id, started_at) VALUES ('s1', 1)",
    );
    await exec.run(
      "INSERT INTO session_exercise (id, session_id, exercise_id, position) VALUES ('se1', 's1', 'e1', 0)",
    );
    await exec.run(
      "INSERT INTO set_entry (id, session_exercise_id, position, weight, reps, is_completed) VALUES ('st1', 'se1', 0, 20, 8, 1)",
    );

    await exec.run("DELETE FROM session WHERE id = 's1'");

    expect(await exec.all("SELECT * FROM session_exercise"), isEmpty);
    expect(await exec.all("SELECT * FROM set_entry"), isEmpty);
    // 动作库不受影响 —— 动作只归档不删除
    expect(await exec.all("SELECT * FROM exercise"), hasLength(1));
  });

  test('只跑到 v1 的旧库能升到 v2 —— 迁移只跑 version > current 的项', () async {
    // 手工造一个「只跑到 v1」的库：v1 的建表脚本 + 版本号 1。
    // 这正是老用户装上新版本时的状态 —— 库里已经有 exercise 等四张表，
    // schema_version 停在 1。
    await exec.run(createMetaSql);
    await exec.run(createTablesSql);
    await exec.run(
      "INSERT INTO app_meta (key, value) VALUES ('schema_version', '1')",
    );
    expect(await getSchemaVersion(exec), 1);
    expect(
      await exec.first<Map<String, Object?>>(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'app_setting'",
      ),
      isNull,
      reason: 'v2 的表此刻还不该存在，否则这条用例就没在测升级',
    );

    await migrate(exec);

    expect(await getSchemaVersion(exec), schemaVersion);
    expect(
      await exec.first<Map<String, Object?>>(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'app_setting'",
      ),
      isNotNull,
      reason: 'migrate 必须跑 v2，否则已发布的库永远拿不到 app_setting',
    );
  });
}
