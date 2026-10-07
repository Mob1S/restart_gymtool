import 'schema.dart';
import 'sql_executor.dart';

/// 一个版本化迁移项。
///
/// `version` 从 1 开始连续编号，[migrate] 按它升序执行所有大于当前版本的项。
/// 一个版本里可以有多条语句，它们会**逐条执行**，但**不在同一个事务里** ——
/// 所以单条语句必须是幂等的（都写成 `CREATE ... IF NOT EXISTS`）。
class Migration {
  final int version;
  final List<String> statements;

  const Migration({required this.version, required this.statements});
}

/// **版本化迁移。新增 schema 变更时追加一项，绝不修改已发布的项。**
///
/// 为什么不能并进旧项：v1/v2 早就发布过，库里的 `schema_version` 已经是 2 的库
/// 不会再跑它们（[migrate] 只跑 `version > current` 的项），新列会永远加不上。
///
/// 每一项都应配一条回归测试：手工造一个「只跑到 vN-1」的库，
/// 验证它升到 vN 后有表 / 列可用（见 `test/data/migrations_test.dart`）。
const List<Migration> migrations = [
  Migration(version: 1, statements: [createMetaSql, createTablesSql]),
  Migration(version: 2, statements: [createSettingsSql]),
];

/// 当前库结构版本。必须与 [migrations] 的最后一项保持一致。
const int schemaVersion = 2;

/// 读出当前库结构版本。
///
/// 全新数据库里 `app_meta` 还不存在，直接查会抛 `no such table` ——
/// 迁移尚未跑过时版本号定义为 0。
Future<int> getSchemaVersion(SqlExecutor exec) async {
  final meta = await exec.first<Map<String, Object?>>(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'app_meta'",
  );
  if (meta == null) return 0;

  final row = await exec.first<Map<String, Object?>>(
    "SELECT value FROM app_meta WHERE key = 'schema_version'",
  );
  return row == null ? 0 : int.parse(row['value'] as String);
}

/// 依次执行尚未应用的迁移，完成后写入新的版本号。
/// 已经是最新版本时不做任何事（幂等，每次启动都会调用）。
Future<void> migrate(SqlExecutor exec) async {
  // app_meta 必须先存在，否则读不到版本号
  await exec.run(createMetaSql);

  final current = await getSchemaVersion(exec);
  final pending = migrations.where((m) => m.version > current).toList()
    ..sort((a, b) => a.version - b.version);

  for (final migration in pending) {
    for (final statement in migration.statements) {
      await exec.run(statement);
    }
    await exec.run(
      """INSERT INTO app_meta (key, value) VALUES ('schema_version', ?)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value""",
      [migration.version.toString()],
    );
  }
}
