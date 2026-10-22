import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/migrations.dart';
import 'package:gym_tracker/data/builtin_programs.dart';
import 'package:gym_tracker/data/repositories/builtin_program_repo.dart';
import 'package:gym_tracker/data/repositories/exercise_repo.dart';
import 'package:gym_tracker/data/repositories/backup_repo.dart';
import 'package:gym_tracker/domain/backup.dart';

void main() {
  test(
    'v6 preserves catalog and programs and rejects an unowned target',
    () async {
      final db = await FfiExecutor.openInMemory();
      addTearDown(db.close);
      await migrate(db);
      await seedExercisesIfEmpty(db);
      await importBuiltinProgram(db, builtinPrograms.first);
      final before = await exportBackup(db, exportedAt: 0);
      expect(before.version, 8);
      expect(before.schemaVersion, 12);
      expect(before.rows('catalogBindings').length, 71);
      await restoreBackup(db, await inspectBackup(db, before));
      expect((await exportBackup(db, exportedAt: 0)).data, before.data);
      final bad = before.toJson();
      final data = {
        ...before.data,
        'programs': [
          {
            'id': 'missing-plan',
            'payload': before.rows('programs').single['payload'],
          },
        ],
      };
      expect(
        () => validateBackup({...bad, 'data': data}),
        throwsA(isA<BackupValidationException>()),
      );
    },
  );
}
