import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'ffi_executor.dart';
import 'migrations.dart';
import 'sql_executor.dart';
import 'sqflite_executor.dart';

/// 打开 App 数据库并跑完迁移。
///
/// **三后端**（规格 §3.1）：
/// - Android 真机 → `sqflite`
/// - Chrome 预览 → `sqflite_common_ffi_web`（真 SQLite wasm，落 IndexedDB）
/// - 单元测试 → 走 `FfiExecutor.openMigrated()`，**不经过这里**
///
/// 三个后端最终都汇到同一个执行器类，**差别只在「怎么打开库」**。
///
/// 打开后**必须立刻开 `PRAGMA foreign_keys = ON`** —— 它是连接级开关，
/// 不开的话建表时写的 `ON DELETE CASCADE` 静默失效。
Future<SqlExecutor> openAppDatabase() async {
  if (kIsWeb) {
    // Chrome 预览：真 SQLite，但数据落在浏览器 IndexedDB，与手机完全隔离。
    // ⚠️ 官方标为 experimental 且 slow，有已知 bug，且 IndexedDB 绑端口 ——
    // **预览只用于看视觉与基本流程，不是验收**（规格 §3.1）。
    final db = await databaseFactoryFfiWeb.openDatabase(
      'gym_tracker.db',
      options: OpenDatabaseOptions(version: 1),
    );
    await db.execute('PRAGMA foreign_keys = ON');
    final exec = FfiExecutor.fromDatabase(db);
    await migrate(exec);
    return exec;
  }

  final dir = await sqflite.getDatabasesPath();
  final exec = await SqfliteExecutor.open(p.join(dir, 'gym_tracker.db'));
  await migrate(exec);
  return exec;
}
