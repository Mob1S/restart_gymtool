import 'package:flutter/material.dart';

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/app/providers.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/sql_executor.dart';
import 'package:gym_tracker/state/active_session_controller.dart';
import 'package:gym_tracker/features/workout/record_page.dart';
import 'package:gym_tracker/ui/theme.dart';
import 'package:gym_tracker/ui/tokens.dart';
import 'package:provider/provider.dart';
import 'package:gym_tracker/features/workout/drag_number.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:wakelock_plus_platform_interface/wakelock_plus_platform_interface.dart';

import 'backup_section_test.dart' show settle;

class _Wake extends WakelockPlusPlatformInterface {
  @override
  Future<void> toggle({required bool enable}) async {}
  @override
  Future<bool> get enabled async => false;
}

class _DelayedResume extends ActiveSessionController {
  final gate = Completer<void>();
  bool gated = false;
  _DelayedResume(super.exec);
  @override
  Future<bool> resume() async {
    if (gated) await gate.future;
    return super.resume();
  }
}

void main() {
  testWidgets(
    'record screen waits for initial resume before enabling completion',
    (t) async {
      final previous = wakelockPlusPlatformInstance;
      wakelockPlusPlatformInstance = _Wake();
      final db = (await t.runAsync(() => FfiExecutor.openMigrated()))!;
      final c = _DelayedResume(db);
      addTearDown(() async {
        c.dispose();
        wakelockPlusPlatformInstance = previous;
        await db.close();
      });
      await t.runAsync(() async {
        await db.run(
          "INSERT INTO exercise(id,name,is_custom,is_archived,created_at) VALUES('a','a',1,0,0)",
        );
        await c.startNew();
        await c.addExercise('a');
      });
      c.gated = true;
      await t.pumpWidget(
        MultiProvider(
          providers: [
            Provider<SqlExecutor>.value(value: db),
            ChangeNotifierProvider<ActiveSessionController>.value(value: c),
          ],
          child: MaterialApp(
            theme: buildTheme(AppColors.light),
            home: RecordPage(sessionId: c.session!.id),
          ),
        ),
      );
      expect(find.text('✓ 完成这组'), findsNothing);
      c.gate.complete();
      await settle(t);
      expect(find.text('✓ 完成这组'), findsOneWidget);
      await t.tap(find.text('✓ 完成这组'));
      await settle(t);
      expect(c.exercises.single.sets.where((s) => s.isCompleted), hasLength(1));
      await t.pumpWidget(const SizedBox());
      await settle(t);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'real removal keeps correct next focus and replaces 50kg draft with 20kg',
    (t) async {
      final previous = wakelockPlusPlatformInstance;
      wakelockPlusPlatformInstance = _Wake();
      final db = (await t.runAsync(() => FfiExecutor.openMigrated()))!;
      addTearDown(() async {
        wakelockPlusPlatformInstance = previous;
        await db.close();
      });
      await t.runAsync(() async {
        for (final (id, weight) in [('a', 50), ('b', 20)]) {
          await db.run(
            'INSERT INTO exercise(id,name,is_custom,is_archived,created_at) VALUES(?,?,1,0,0)',
            [id, id],
          );
          await db.run(
            'INSERT INTO session(id,started_at,finished_at) VALUES(?,1,2)',
            [id],
          );
          await db.run(
            'INSERT INTO session_exercise(id,session_id,exercise_id,position) VALUES(?,?,?,0)',
            [id, id, id],
          );
          await db.run(
            'INSERT INTO set_entry(id,session_exercise_id,position,weight,reps,is_completed,completed_at) VALUES(?,?,0,?,8,1,2)',
            [id, id, weight],
          );
        }
        await db.run(
          "INSERT INTO split_template(id,name,position,created_at) VALUES('plan','AB',0,0)",
        );
        await db.run(
          "INSERT INTO template_exercise(id,template_id,exercise_id,position) VALUES('pa','plan','a',0),('pb','plan','b',1)",
        );
      });
      await t.pumpWidget(AppBootstrap(openDatabase: () async => db));
      await settle(t);
      await t.tap(find.text('开始训练'));
      await settle(t);
      expect(t.widget<DragNumber>(find.byType(DragNumber)).value, 50);
      await t.tap(find.text('✓ 完成这组'));
      await settle(t);
      await t.tap(find.byTooltip('移除当前动作'));
      await settle(t);
      await t.tap(find.text('删掉这 1 组'));
      await settle(t);
      expect(t.widget<DragNumber>(find.byType(DragNumber)).value, 20);
      expect(find.byTooltip('移除当前动作'), findsNothing);
      await t.tap(find.text('✓ 完成这组'));
      await settle(t);
      await t.runAsync(() async {
        final rows = await db.all<Map<String, Object?>>(
          'SELECT st.weight,se.exercise_id FROM set_entry st JOIN session_exercise se ON se.id=st.session_exercise_id JOIN session s ON s.id=se.session_id WHERE s.finished_at IS NULL AND st.is_completed=1',
        );
        expect(rows, hasLength(1));
        expect(rows.single['exercise_id'], 'b');
        expect(rows.single['weight'], 20);
      });
      await t.pumpWidget(const SizedBox());
      await settle(t);
      expect(t.takeException(), isNull);
    },
  );
}
