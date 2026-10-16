import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/sql_executor.dart';
import 'package:gym_tracker/data/repositories/exercise_repo.dart';
import 'package:gym_tracker/data/repositories/exercise_preferences_repo.dart';
import 'package:gym_tracker/domain/types.dart';
import 'package:gym_tracker/features/workout/exercise_picker.dart';

import 'backup_section_test.dart' show settle;

void main() {
  late FfiExecutor db;
  late Exercise a, b;
  setUp(() async {
    db = await FfiExecutor.openMigrated();
    a = await createCustomExercise(db, name: 'A');
    b = await createCustomExercise(db, name: 'B');
  });
  tearDown(() => db.close());
  testWidgets(
    'multi selection preserves click order; deselect and reselect moves to last',
    (t) async {
      List<Exercise>? selected;
      await t.pumpWidget(
        Provider<SqlExecutor>.value(
          value: db,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => TextButton(
                  onPressed: () async {
                    selected = await showExerciseMultiPicker(context);
                  },
                  child: const Text('打开'),
                ),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('打开'));
      await settle(t);
      expect(t.testTextInput.isVisible, false);
      Future<void> row(String name) async {
        await t.tap(find.widgetWithText(ListTile, name));
        await settle(t);
      }

      await row('B');
      await row('A');
      await row('B');
      await row('B');
      await t.tap(find.text('添加 2 个动作'));
      await settle(t);
      expect(selected!.map((e) => e.id), [a.id, b.id]);
      await t.pumpWidget(const SizedBox());
      await settle(t);
    },
  );
  testWidgets(
    'favorite click does not select; cancel preserves favorite and single picker still works',
    (t) async {
      List<Exercise>? selected;
      Exercise? single;
      await t.pumpWidget(
        Provider<SqlExecutor>.value(
          value: db,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => Column(
                  children: [
                    TextButton(
                      onPressed: () async {
                        selected = await showExerciseMultiPicker(context);
                      },
                      child: const Text('多选'),
                    ),
                    TextButton(
                      onPressed: () async {
                        single = await showExercisePicker(context);
                      },
                      child: const Text('单选'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await t.tap(find.text('多选'));
      await settle(t);
      await t.tap(find.byTooltip('收藏 A'));
      await settle(t);
      expect(find.text('添加 0 个动作'), findsOneWidget);
      await t.tapAt(const Offset(8, 8));
      await settle(t);
      expect(selected, isNull);
      await t.runAsync(() async {
        expect(
          (await readExercisePreferences(db, [a.id]))[a.id]!.isFavorite,
          true,
        );
      });
      await t.tap(find.text('单选'));
      await settle(t);
      expect(find.text('常用'), findsOneWidget);
      await t.tap(find.widgetWithText(ListTile, 'A'));
      await settle(t);
      expect(single!.id, a.id);
      await t.pumpWidget(const SizedBox());
      await settle(t);
      expect(t.takeException(), isNull);
    },
  );
}
