import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/domain/beverage.dart';
import 'package:gym_tracker/features/calories/beverage_editor_page.dart';
import 'package:gym_tracker/ui/theme.dart';
import 'package:gym_tracker/ui/tokens.dart';

import '../domain/beverage_test.dart' show beverage;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Finder field(String label) => find.widgetWithText(TextFormField, label);
  String value(WidgetTester t, String label) =>
      t.widget<TextFormField>(field(label)).controller!.text;
  Future<void> pump(WidgetTester t, Beverage b) async {
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(AppColors.light),
        home: BeverageEditorPage(initial: b),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets(
    'every prepared configuration change invalidates carried energy',
    (t) async {
      await pump(
        t,
        Beverage.fromJson({
          ...beverage().toJson(),
          'kind': 'prepared',
          'sugar': '全糖',
        }),
      );
      expect(value(t, '标注能量（留空为待补热量）'), '42');
      await t.enterText(field('糖度'), '三分糖');
      await t.pump();
      expect(value(t, '标注能量（留空为待补热量）'), '');
      await t.enterText(field('标注能量（留空为待补热量）'), '120');
      await t.enterText(field('冷热（可选）'), '热');
      await t.pump();
      expect(value(t, '标注能量（留空为待补热量）'), '');
      await t.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'OCR replaces old fields and ambiguous mass basis cannot keep old energy',
    (t) async {
      const channel = MethodChannel('gym_tracker/beverage_ocr');
      var scans = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method != 'scan') return null;
            scans++;
            return {
              'text': scans == 1
                  ? '品名：可乐\n每100毫升\n能量180kJ\n净含量330mL'
                  : '每100g\n能量180kJ',
              'image': File('web/icons/Icon-192.png').readAsBytesSync(),
            };
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      await pump(t, beverage());
      await t.tap(find.text('导入标签图片'));
      await t.pumpAndSettle();
      expect(value(t, '标注能量（留空为待补热量）'), '180');
      expect(value(t, '饮料名称'), '可乐');
      await t.tap(find.text('导入标签图片'));
      await t.pumpAndSettle();
      expect(value(t, '标注能量（留空为待补热量）'), '');
      expect(value(t, '每份体积 mL（未知可留空）'), '');
      expect(find.textContaining('每 100 g；不能按 mL'), findsOneWidget);
      await t.enterText(field('标注能量（留空为待补热量）'), '180');
      await t.scrollUntilVisible(
        find.text('确认资料'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await t.tap(find.text('确认资料'));
      await t.pumpAndSettle();
      expect(find.text('请选择基准'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    },
  );
}
