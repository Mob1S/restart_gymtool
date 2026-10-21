import '../../domain/beverage.dart';
import '../../domain/local_date.dart';
import '../db/sql_executor.dart';
import 'backup_repo.dart';
import '../../domain/backup_codec.dart';

class BeverageRepo {
  final SqlExecutor exec;
  const BeverageRepo(this.exec);
  Future<List<Beverage>> library({bool includeArchived = false}) async {
    final rows = await exec.all<Map<String, Object?>>(
      'SELECT b.id,b.payload,MAX(r.occurred_at) AS recent FROM beverage b LEFT JOIN drink_record r ON r.beverage_id=b.id GROUP BY b.id,b.payload',
    );
    final result = rows
        .map((r) => Beverage.decode(r['payload'] as String))
        .where((b) => includeArchived || !b.archived)
        .toList();
    final recent = {
      for (final row in rows) row['id'] as String: (row['recent'] as int?) ?? 0,
    };
    result.sort(
      (a, b) => a.favorite != b.favorite
          ? (a.favorite ? -1 : 1)
          : recent[a.id] != recent[b.id]
          ? recent[b.id]!.compareTo(recent[a.id]!)
          : b.updatedAt.compareTo(a.updatedAt),
    );
    return result;
  }

  Future<List<DrinkRecord>> records({
    LocalDate? from,
    LocalDate? through,
  }) async {
    final rows = await exec.all<Map<String, Object?>>(
      'SELECT payload FROM drink_record WHERE (? IS NULL OR date >= ?) AND (? IS NULL OR date <= ?) ORDER BY occurred_at DESC, id',
      [from?.key, from?.key, through?.key, through?.key],
    );
    return rows.map((r) => DrinkRecord.decode(r['payload'] as String)).toList();
  }

  Future<void> _bounded(SqlExecutor tx) async {
    // Use exactly the same nested-record and byte limits as export/restore.
    encodeBackup(await readBackupSnapshot(tx, exportedAt: 0));
  }

  Future<void> _saveBeverage(SqlExecutor tx, Beverage b) => tx.run(
    'INSERT INTO beverage(id,payload) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload',
    [b.id, b.encode()],
  );
  Future<void> saveBeverage(Beverage b) => exec.transaction((tx) async {
    await _saveBeverage(tx, b);
    await _bounded(tx);
  });
  Future<void> saveRecord(DrinkRecord r, {Beverage? newBeverage}) =>
      exec.transaction((tx) async {
        if (newBeverage != null) await _saveBeverage(tx, newBeverage);
        await tx.run(
          'INSERT INTO drink_record(id,beverage_id,occurred_at,date,payload) VALUES(?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET beverage_id=excluded.beverage_id,occurred_at=excluded.occurred_at,date=excluded.date,payload=excluded.payload',
          [r.id, r.beverageId, r.occurredAt, r.date.key, r.encode()],
        );
        await _bounded(tx);
      });
  Future<void> deleteRecord(String id) =>
      exec.run('DELETE FROM drink_record WHERE id=?', [id]);
}
