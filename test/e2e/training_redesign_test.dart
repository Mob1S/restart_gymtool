import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/app/providers.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/domain/local_date.dart';
import 'package:gym_tracker/domain/weight_value.dart';

import '../widget/backup_section_test.dart' show settle;

void main() {
  testWidgets(
    'calendar date, manual lb entry, detail return and same-page deletion',
    (tester) async {
      final db = (await tester.runAsync(FfiExecutor.openMigrated))!;
      addTearDown(db.close);
      final today = LocalDate.fromDateTime(DateTime.now());
      await tester.pumpWidget(AppBootstrap(openDatabase: () async => db));
      await settle(tester);
      final dateCell = find.byKey(ValueKey('calendar-day-${today.key}'));
      await tester.ensureVisible(dateCell);
      await tester.tap(dateCell);
      await settle(tester);
      expect(find.text('所选日期：${today.key}'), findsOneWidget);
      expect(find.text('当天没有训练记录'), findsOneWidget);
      await tester.tap(find.text('补加'));
      await settle(tester);
      final start = find.widgetWithText(TextField, '开始时间');
      expect(
        tester.widget<TextField>(start).controller!.text,
        startsWith(today.key),
      );
      await tester.enterText(
        find.widgetWithText(TextField, '训练名称（可空）'),
        '原始磅数补记',
      );
      await tester.enterText(start, '${today.key} 10:00');
      await tester.enterText(
        find.widgetWithText(TextField, '结束时间'),
        '${today.key} 11:00',
      );
      await tester.enterText(
        find.widgetWithText(TextField, '或输入新动作名称'),
        '磅数器械',
      );
      await tester.ensureVisible(find.text('加入新动作草稿'));
      await tester.tap(find.text('加入新动作草稿'));
      await settle(tester);
      await tester.ensureVisible(find.byType(DropdownButton<WeightUnit>));
      await tester.tap(find.byType(DropdownButton<WeightUnit>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('lb').last);
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, '重量 lb'), '50');
      await tester.ensureVisible(find.text('预览补记'));
      await tester.tap(find.text('预览补记'));
      await settle(tester);
      await tester.tap(find.text('追加 1 场训练'));
      await settle(tester);
      expect(find.text('所选日期：${today.key}'), findsOneWidget);
      await tester.runAsync(() async {
        final set = (await db.all<Map<String, Object?>>(
          'SELECT * FROM set_entry',
        )).single;
        expect(set['source_weight'], '50');
        expect(set['source_unit'], 'lb');
        expect(set['weight'], closeTo(22.6796185, 1e-12));
        final session = (await db.all<Map<String, Object?>>(
          'SELECT * FROM session',
        )).single;
        expect(session['origin'], 'manual');
        expect(session['plan_id'], isNull);
      });
      await tester.tap(find.text('原始磅数补记'));
      await settle(tester);
      expect(find.textContaining('50 lb'), findsWidgets);
      await tester.pageBack();
      await settle(tester);
      expect(find.text('所选日期：${today.key}'), findsOneWidget);
      await tester.tap(find.byTooltip('删除这场训练'));
      await settle(tester);
      await tester.tap(find.text('取消'));
      await settle(tester);
      expect(find.text('原始磅数补记'), findsOneWidget);
      await tester.tap(find.byTooltip('删除这场训练'));
      await settle(tester);
      await tester.tap(find.text('删除这场训练'));
      await settle(tester);
      expect(find.text('当天没有训练记录'), findsOneWidget);
      await tester.tap(find.text('训练').last);
      await settle(tester);
      expect(
        find.byKey(ValueKey('calendar-completed-${today.key}')),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
      expect(tester.takeException(), isNull);
    },
  );
}
