import 'package:gym_tracker/data/db/sql_executor.dart';

class WorkoutFaults {
  String? runPrefix;
  int occurrence = 1;
  int seen = 0;
  bool failReload = false;
}

class WorkoutFaultExecutor implements SqlExecutor {
  final SqlExecutor inner;
  final WorkoutFaults faults;
  final bool scoped;
  WorkoutFaultExecutor(this.inner, this.faults, {this.scoped = false});
  @override
  Future<T> transaction<T>(Future<T> Function(SqlExecutor) action) =>
      inner.transaction(
        (tx) => action(WorkoutFaultExecutor(tx, faults, scoped: true)),
      );
  @override
  Future<void> run(String sql, [List<Object?>? params]) async {
    await inner.run(sql, params);
    if (faults.runPrefix != null &&
        sql.startsWith(faults.runPrefix!) &&
        ++faults.seen == faults.occurrence) {
      throw StateError('injected write failure');
    }
  }

  @override
  Future<List<T>> all<T>(String sql, [List<Object?>? params]) {
    if (!scoped && faults.failReload && sql.contains('FROM session_exercise')) {
      faults.failReload = false;
      throw StateError('injected refresh failure');
    }
    return inner.all<T>(sql, params);
  }

  @override
  Future<T?> first<T>(String sql, [List<Object?>? params]) =>
      inner.first<T>(sql, params);
}
