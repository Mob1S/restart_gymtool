import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/sql_executor.dart';
import 'package:gym_tracker/data/repositories/template_repo.dart';
import 'package:gym_tracker/data/repositories/workout_plan_repo.dart';
import 'package:gym_tracker/data/repositories/record_management_repo.dart';
import 'package:gym_tracker/data/repositories/session_repo.dart';
import 'package:gym_tracker/data/repositories/backup_repo.dart';
import 'package:gym_tracker/domain/plans.dart';
import 'package:gym_tracker/domain/rotation.dart';
import 'package:gym_tracker/state/active_session_controller.dart';

import 'backup_repo_test.dart' show FailingExecutor;

class _FailPostCommitRead implements SqlExecutor {
  final SqlExecutor inner;
  _FailPostCommitRead(this.inner);
  @override
  Future<T> transaction<T>(Future<T> Function(SqlExecutor tx) action) =>
      inner.transaction(action);
  @override
  Future<void> run(String sql, [List<Object?>? params]) =>
      inner.run(sql, params);
  @override
  Future<T?> first<T>(String sql, [List<Object?>? params]) =>
      inner.first<T>(sql, params);
  @override
  Future<List<T>> all<T>(String sql, [List<Object?>? params]) {
    if (sql.contains('FROM session_exercise')) {
      throw StateError('post-commit read');
    }
    return inner.all<T>(sql, params);
  }
}

class _FailSecondSet implements SqlExecutor {
  final SqlExecutor inner;
  final List<int> count;
  _FailSecondSet(this.inner, [List<int>? count]) : count = count ?? [0];
  @override
  Future<T> transaction<T>(Future<T> Function(SqlExecutor tx) action) =>
      inner.transaction((tx) => action(_FailSecondSet(tx, count)));
  @override
  Future<void> run(String sql, [List<Object?>? params]) async {
    await inner.run(sql, params);
    if (sql.startsWith('INSERT INTO set_entry') && ++count[0] == 2) {
      throw StateError('second set insert');
    }
  }

  @override
  Future<T?> first<T>(String sql, [List<Object?>? params]) =>
      inner.first<T>(sql, params);
  @override
  Future<List<T>> all<T>(String sql, [List<Object?>? params]) =>
      inner.all<T>(sql, params);
}

void main() {
  late FfiExecutor db;
  setUp(() async {
    db = await FfiExecutor.openMigrated();
    await db.run(
      "INSERT INTO exercise(id,name,is_custom,is_archived,created_at) VALUES('e','Bench',1,0,0)",
    );
    await db.run(
      "INSERT INTO exercise(id,name,is_custom,is_archived,created_at) VALUES('f','Squat',1,0,0)",
    );
  });
  tearDown(() async => db.close());
  Future<TemplateDetail> plan(String name, List<String> ids) =>
      saveTemplate(db, TemplateDraft(name: name, exerciseIds: ids));
  test('committed start with failed UI read reports refresh failure, retains session', () async {
    final c = ActiveSessionController(_FailPostCommitRead(db));
    expect(await c.startNew(), StartResult.refreshFailed);
    expect((await getActiveSession(db))?.id, c.session!.id);
    expect(await db.all('SELECT * FROM session'), hasLength(1));
    c.dispose();
  });
  test('rotation ignores free/active history and empty plans remain', () async {
    expect(nextTemplateIndex([], null), null);
    expect(nextTemplateIndex(['a', 'b'], 'b'), 0);
    final a = await plan('A', ['e', 'e']);
    final b = await plan('B', []);
    expect((await getTemplate(db, a.template.id))!.exercises, hasLength(2));
    expect((await loadNextWorkout(db)).templateId, a.template.id);
    final c = ActiveSessionController(db);
    await c.startNew();
    expect(c.exercises, hasLength(2));
    expect((await loadNextWorkout(db)).templateId, a.template.id);
    await c.endWorkout();
    expect((await loadNextWorkout(db)).templateId, b.template.id);
    final free = await createSession(db);
    await finishSession(db, free.id, DateTime.now().millisecondsSinceEpoch);
    expect((await loadNextWorkout(db)).templateId, b.template.id);
    c.dispose();
  });
  test(
    'save rollback, stale edits, tied position move and detaching deletion',
    () async {
      final a = await plan('A', ['e']);
      final b = await plan('B', ['f']);
      await db.run('UPDATE split_template SET position=0');
      final list = await listTemplates(db);
      expect(
        await moveTemplate(db, b.template.id, -1, templateOrderToken(list)),
        true,
      );
      expect((await listTemplates(db)).map((e) => e.template.id), [
        b.template.id,
        a.template.id,
      ]);
      final before = (await exportBackup(db, exportedAt: 0)).data;
      final old = (await getTemplate(db, a.template.id))!;
      await expectLater(
        saveTemplate(
          FailingExecutor(
            db,
            'INSERT INTO template_exercise',
            StateError('injected'),
          ),
          TemplateDraft(
            id: a.template.id,
            name: 'changed',
            exerciseIds: ['f'],
            expectedToken: old.editToken,
          ),
        ),
        throwsA(anything),
      );
      expect((await exportBackup(db, exportedAt: 0)).data, before);
      await saveTemplate(
        db,
        TemplateDraft(
          id: a.template.id,
          name: 'new',
          exerciseIds: ['e'],
          expectedToken: old.editToken,
        ),
      );
      await expectLater(
        saveTemplate(
          db,
          TemplateDraft(
            id: a.template.id,
            name: 'stale',
            exerciseIds: [],
            expectedToken: old.editToken,
          ),
        ),
        throwsA(anything),
      );
      final s = await createSession(db, templateId: a.template.id);
      final preview = (await inspectTemplateDeletion(db, a.template.id))!;
      await deleteTemplate(db, preview);
      expect((await getSession(db, s.id))!.templateId, isNull);
      expect(await getTemplate(db, a.template.id), isNull);
      await exportBackup(db, exportedAt: 0);
    },
  );
  test('start is atomic and conflict first; failed second exercise leaves no session', () async {
    await plan('A', ['e', 'f']);
    final c = ActiveSessionController(_FailSecondSet(db));
    await expectLater(c.startNew(), throwsA(anything));
    expect(await getActiveSession(db), isNull);
    final normal = ActiveSessionController(db);
    await normal.startNew();
    expect(
      await normal.startNew(preferredTemplateId: 'gone'),
      StartResult.conflict,
    );
    expect(await db.all('SELECT * FROM session'), hasLength(1));
    c.dispose();
    normal.dispose();
  });
  test(
    'session deletion is targeted, stale-confirmation safe and cascades',
    () async {
      final a = await createSession(db);
      final b = await createSession(db);
      final p = (await inspectSessionDeletion(db, a.id))!;
      await addExerciseToSession(db, a.id, 'e');
      await expectLater(deleteSession(db, p), throwsA(anything));
      final fresh = (await inspectSessionDeletion(db, a.id))!;
      await deleteSession(db, fresh);
      expect(await getSession(db, a.id), isNull);
      expect(await getSession(db, b.id), isNotNull);
      expect(await db.all('SELECT * FROM session_exercise'), isEmpty);
    },
  );
}
