import 'schema.dart';
import 'sql_executor.dart';
import 'training_v6_migration.dart';
import 'training_v8_migration.dart';
import 'video_review_migration.dart';
import 'motion_project_migration.dart';
import 'beverage_migration.dart';
import 'plugin_migration.dart';

/// 一个版本化迁移项。
///
/// `version` 从 1 开始连续编号，[migrate] 按它升序执行所有大于当前版本的项。
/// 一个版本里可以有多条语句，它们会**逐条执行**，但**不在同一个事务里** ——
/// 所以单条语句**应当**是幂等的（都写成 `CREATE ... IF NOT EXISTS`）。
/// 唯一做不到幂等的是 `ALTER TABLE ... ADD COLUMN`（SQLite 没有
/// `ADD COLUMN IF NOT EXISTS`）—— 见 [migrations] 里 v3 那一条的说明。
/// v6 通过 [migrateTrainingV6] 的专用事务执行，DDL 与版本号原子提交；
/// 已发布 v1–v5 的执行路径保持不变。
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

  // v3 —— `session.template_id`。**Task 7（session_repo.dart）需要这一列**：
  // 它的 `createSession` 与 `sessionColumns` 都带 `template_id`（`domain/types.dart`
  // 的 `WorkoutSession.templateId` 从 Task 1 起就在），而 v1 建表时漏了它。
  // 少了这一列，Task 7 的每条用例都在 prepare 阶段就抛
  // `table session has no column named template_id`。
  //
  // **为什么不并进 v1 的建表语句**：v1/v2 早已发布，库里 `schema_version` 已是 2 的
  // 库不会再跑 v1（[migrate] 只跑 `version > current` 的项），把列写进 v1 等于
  // **新列永远加不上**。这正是「迁移只追加」的教科书场景。
  //
  // **刻意不写外键**（规格 §4.4）：`ALTER TABLE ... ADD COLUMN` 加上的列级外键
  // 在 SQLite 里不会被后续写入强制（实测），写一个不生效的约束只会误导后来的人；
  // 改为明文约定 —— 删计划时由 `templateRepo.deleteTemplate` 把引用它的
  // `session.template_id` 置空。
  //
  // ⚠️ 已知弱点：`ALTER TABLE ... ADD COLUMN` **不是幂等的**，而 [migrate] 的语句
  // 之间没有事务 —— 若 ALTER 成功、紧接着写版本号那一步失败，下次启动会以
  // `duplicate column name: template_id` 抛错。窗口只有两条语句之间，极小；
  // 选择**接受并记录**，而不是为它改 [migrate] 的事务语义（那会动到 v1/v2 的路径）。
  Migration(
    version: 3,
    statements: ['ALTER TABLE session ADD COLUMN template_id TEXT'],
  ),
  Migration(version: 4, statements: [createBackupPlansSql]),
  Migration(version: 5, statements: [createExercisePreferencesSql]),
  Migration(version: 6, statements: []),
  Migration(
    version: 7,
    statements: [
      "ALTER TABLE split_template ADD COLUMN kind TEXT NOT NULL DEFAULT 'training' CHECK(kind IN ('training','rest'))",
      'ALTER TABLE training_plan ADD COLUMN activated_on TEXT',
    ],
  ),
  Migration(version: 8, statements: trainingV8Statements),
  Migration(version: 9, statements: videoReviewStatements),
  Migration(version: 10, statements: motionProjectStatements),
  Migration(version: 11, statements: beverageStatements),
  Migration(version: 12, statements: []),
];

/// 当前库结构版本。必须与 [migrations] 的最后一项保持一致。
const int schemaVersion = 12;

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
  await recordPluginInstallOrigin(exec);

  final current = await getSchemaVersion(exec);
  final pending = migrations.where((m) => m.version > current).toList()
    ..sort((a, b) => a.version - b.version);

  for (final migration in pending) {
    if (migration.version == 12) {
      await exec.transaction((tx) async {
        await migratePluginsV12(tx);
        await tx.run(
          "INSERT INTO app_meta(key,value) VALUES('schema_version',?) "
          'ON CONFLICT(key) DO UPDATE SET value=excluded.value',
          ['12'],
        );
      });
      continue;
    }
    if (migration.version >= 7) {
      await exec.transaction((tx) async {
        for (final statement in migration.statements) {
          await tx.run(statement);
        }
        await tx.run(
          "INSERT INTO app_meta(key,value) VALUES('schema_version',?) "
          'ON CONFLICT(key) DO UPDATE SET value=excluded.value',
          ['${migration.version}'],
        );
      });
      continue;
    }
    if (migration.version == 6) {
      await exec.transaction((tx) async {
        await migrateTrainingV6(tx);
        await tx.run(
          "INSERT INTO app_meta (key,value) VALUES ('schema_version',?) "
          'ON CONFLICT(key) DO UPDATE SET value=excluded.value',
          ['6'],
        );
      });
      continue;
    }
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
