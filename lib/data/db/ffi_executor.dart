import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'migrations.dart';
import 'sql_executor.dart';

/// 基于 `sqflite_common_ffi` 的执行器 —— 用于**单元测试**（内存库）与桌面运行。
///
/// 它在这里的角色，等同于旧项目（React Native 版）里 `node:sqlite` 适配器的角色：
/// 让同一套仓储代码在不启动 Android 的前提下被真实地测到。
///
/// 它也同时服务 Chrome 预览 —— `database_factory_web` 打开的那个
/// `Database` 直接交给 [FfiExecutor.fromDatabase] 即可，**不需要第二套实现**。
class FfiExecutor implements SqlExecutor {
  final Database _db;

  FfiExecutor._(this._db);

  /// 包一个已经打开的 `Database`。
  ///
  /// Chrome 预览走这条路（web 的 factory 在 `database.dart` 里设好之后打开库，
  /// 再把 `Database` 交给这里）—— **三个后端共用同一个执行器类**，
  /// 差别只在「怎么打开库」。
  factory FfiExecutor.fromDatabase(Database db) => FfiExecutor._(db);

  /// 打开一个**内存**库，并立刻开外键。
  ///
  /// `PRAGMA foreign_keys` 是**连接级**开关，不开的话建表时写的
  /// `ON DELETE CASCADE` 完全不生效 —— 而那种失效是静默的：
  /// 删除不会报错，只是子表数据留了下来。
  static Future<FfiExecutor> openInMemory() async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('PRAGMA foreign_keys = ON');
    return FfiExecutor._(db);
  }

  /// 在内存库上先跑完迁移，返回可直接使用的执行器 —— 测试里的常用入口。
  static Future<FfiExecutor> openMigrated() async {
    final exec = await openInMemory();
    await migrate(exec);
    return exec;
  }

  @override
  Future<void> run(String sql, [List<Object?>? params]) async {
    // 无参数 → 可能是一串多语句（迁移的建表脚本就是），逐条执行；
    // 有参数 → 走 rawInsert，因为 execute 不接受参数。
    if (params == null || params.isEmpty) {
      // 这里本可以让 `sqlite3` 包自己跑多语句（它确实支持），但**不这么做**：
      // 生产后端是 Android 的 execSQL，它只跑第一条且静默丢弃其余。
      // 统一走 splitSqlStatements，两端行为才真正一致，且测试跑的就是
      // Android 用的那条代码路径。
      for (final statement in splitSqlStatements(sql)) {
        await _db.execute(statement);
      }
    } else {
      await _db.rawInsert(sql, params);
    }
  }

  @override
  Future<List<T>> all<T>(String sql, [List<Object?>? params]) async {
    final rows = await _db.rawQuery(sql, params);
    return rows.cast<T>();
  }

  @override
  Future<T?> first<T>(String sql, [List<Object?>? params]) async {
    final rows = await _db.rawQuery(sql, params);
    return rows.isEmpty ? null : rows.first as T;
  }

  Future<void> close() => _db.close();
}
