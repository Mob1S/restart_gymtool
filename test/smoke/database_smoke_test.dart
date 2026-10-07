import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  test('内存库能建表、能写、能读回', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute(
      'CREATE TABLE t (id TEXT PRIMARY KEY, n INTEGER NOT NULL)',
    );
    await db.insert('t', {'id': 'a', 'n': 42});
    final rows = await db.query('t');
    expect(rows, hasLength(1));
    expect(rows.first['n'], 42);
    await db.close();
  });

  test('PRAGMA foreign_keys 能打开，级联删除生效', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('PRAGMA foreign_keys = ON');
    await db.execute('CREATE TABLE parent (id TEXT PRIMARY KEY)');
    await db.execute(
      'CREATE TABLE child (id TEXT PRIMARY KEY, p TEXT NOT NULL REFERENCES parent(id) ON DELETE CASCADE)',
    );
    await db.insert('parent', {'id': 'p1'});
    await db.insert('child', {'id': 'c1', 'p': 'p1'});
    await db.delete('parent', where: 'id = ?', whereArgs: ['p1']);
    expect(await db.query('child'), isEmpty);
    await db.close();
  });
}
