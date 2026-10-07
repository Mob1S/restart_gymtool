import 'package:sqflite/sqflite.dart' as sqflite;

import 'sql_executor.dart';

/// 生产用的执行器（Android / iOS）。
///
/// 与 [FfiExecutor] 的差别只在「怎么打开库」，三个方法的语义完全一致 ——
/// 这正是保留 [SqlExecutor] 这层接缝的意义。
class SqfliteExecutor implements SqlExecutor {
  final sqflite.Database _db;

  SqfliteExecutor._(this._db);

  static Future<SqfliteExecutor> open(String path) async {
    final db = await sqflite.openDatabase(path);
    // 连接级的开关，不开则 ON DELETE CASCADE 静默失效
    await db.execute('PRAGMA foreign_keys = ON');
    return SqfliteExecutor._(db);
  }

  static Future<SqfliteExecutor> openInMemory() async {
    final db = await sqflite.openDatabase(sqflite.inMemoryDatabasePath);
    await db.execute('PRAGMA foreign_keys = ON');
    return SqfliteExecutor._(db);
  }

  @override
  Future<void> run(String sql, [List<Object?>? params]) async {
    if (params == null || params.isEmpty) {
      // Android 的 execSQL 只执行第一条语句、其余静默丢弃，所以多语句
      // **必须**在这里自己拆开逐条跑（详见 splitSqlStatements 的注释）。
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
