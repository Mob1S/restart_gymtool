/// 最小 SQL 执行接口。
///
/// 数据库层只对外暴露这三个方法，是为了让上层（仓储、迁移）**不依赖具体的
/// SQLite 实现**：生产用 sqflite，测试用 `sqflite_common_ffi` 的内存库，
/// Chrome 预览用 `sqflite_common_ffi_web`，同一套仓储代码三边都跑。
///
/// **它比旧项目（React Native 版）薄。** 旧版里 sqflite 与 expo-sqlite 是两套
/// 互不相干的 API，这层抽象承担了「隔离具体实现」的主要价值；在 Dart 里
/// sqflite 自己就有 `DatabaseExecutor` 接口、三个后端实现的是同一个，
/// 那部分价值下降了。
///
/// 保留它是因为另外两条，**改这里的人请先读完再决定要不要删**：
///
/// 1. 它承载两条自定义语义，这两条是仓储代码的隐含前提 ——
///    - [run] **不传参数时要能跑多语句**（迁移的建表脚本是多条 CREATE 拼成的）
///    - [first] 一行都没有时返回 `null`；[all] 没有命中时返回 `[]`（不是 `null`）
/// 2. 它让仓储层完全不出现 sqflite 的类型 —— 将来加云同步时改动面不扩散
abstract class SqlExecutor {
  /// Run atomically; every operation in [action] must use its scoped executor.
  Future<T> transaction<T>(Future<T> Function(SqlExecutor tx) action);

  /// 执行一条 SQL，不取返回行。
  ///
  /// [params] 省略或传空数组都表示「没有参数」，此时**必须能跑多语句**。
  Future<void> run(String sql, [List<Object?>? params]);

  /// 查询多行。**没有命中时返回空数组，不是 null**，调用方不必判空。
  Future<List<T>> all<T>(String sql, [List<Object?>? params]);

  /// 查询单行。
  ///
  /// `T` 是**数据库原始行**（snake_case 列名），不是 `domain/types.dart` 里的
  /// 实体 —— 列名到实体的转换由各仓储的 `toXxx()` 负责。
  ///
  /// **一行都没有时返回 null**（已统一抹平 null/undefined 的差异）。
  Future<T?> first<T>(String sql, [List<Object?>? params]);
}

/// 把一串 SQL 按 `;` 拆成单条语句，空白片段丢掉。
///
/// [SqlExecutor.run] 的**无参数分支**靠它实现「多语句」语义。两个后端都必须
/// 走这一条路，不能依赖底层 `execute` 自己支持多语句：
///
/// - `sqflite_common` 的接口文档写得很明白：`execute` **只接受单条语句**，
///   "You cannot have multiple statements (separated by `;` or by line)"。
/// - Android 上它落到 `SQLiteDatabase.execSQL`，而 `execSQL` 底层是
///   `sqlite3_prepare_v2` —— **只编译第一条语句，后面的静默丢弃、不报错**。
///
/// 所以同一个 `run(createTablesSql)`，在 FFI 上四张表都建出来（`sqlite3` 包的
/// `execute` 走的是支持多语句的路径），在 Android 上却只建出第一张
/// `exercise`，其余三张表和三个索引**无声消失**，直到运行时才报
/// `no such table: session`。测试全部跑在 FFI 上，**永远抓不到这个差异** ——
/// 这就是这里宁可自己拆、也不把多语句交给底层的原因。
///
/// 实现是朴素的按 `;` 切分：**它假定语句里没有字符串字面量 / 注释中的分号**，
/// 本项目的 DDL 与迁移脚本都不含这种。将来若真出现（例如 `DEFAULT ';'`、触发器
/// 的 `BEGIN ... END;`），**只需改这一个函数** —— 两个后端都从它取语句，
/// 不会各拆各的。
List<String> splitSqlStatements(String sql) => sql
    .split(';')
    .map((statement) => statement.trim())
    .where((statement) => statement.isNotEmpty)
    .toList();
