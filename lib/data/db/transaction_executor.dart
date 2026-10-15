import 'package:sqflite/sqflite.dart' show DatabaseExecutor;

import 'sql_executor.dart';

/// Adapts only the current transaction, never the outer Database connection.
class TransactionExecutor implements SqlExecutor {
  final DatabaseExecutor _transaction;
  TransactionExecutor(this._transaction);

  @override
  Future<void> run(String sql, [List<Object?>? params]) async {
    if (params == null || params.isEmpty) {
      for (final statement in splitSqlStatements(sql)) {
        await _transaction.execute(statement);
      }
    } else {
      await _transaction.rawInsert(sql, params);
    }
  }

  @override
  Future<List<T>> all<T>(String sql, [List<Object?>? params]) async =>
      (await _transaction.rawQuery(sql, params)).cast<T>();

  @override
  Future<T?> first<T>(String sql, [List<Object?>? params]) async {
    final rows = await all<T>(sql, params);
    return rows.isEmpty ? null : rows.first;
  }

  @override
  Future<T> transaction<T>(Future<T> Function(SqlExecutor tx) action) =>
      Future.error(StateError('Nested transactions are not supported'));
}
