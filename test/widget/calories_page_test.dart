import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:gym_tracker/app/providers.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/repositories/beverage_repo.dart';
import 'package:gym_tracker/domain/beverage.dart';
import 'package:gym_tracker/features/calories/beverage_editor_page.dart';
import 'package:gym_tracker/ui/theme.dart';
import 'package:gym_tracker/ui/tokens.dart';

import '../domain/beverage_test.dart' show beverage;
import '../support/backup_fakes.dart';
import 'backup_section_test.dart' show settle;

void main() {
  late FfiExecutor db;
  setUp(() async => db = await FfiExecutor.openMigrated());
  tearDown(() async => db.close());
  Future<void> boot(WidgetTester t) async {
    await t.pumpWidget(
      AppBootstrap(
        openDatabase: () async => db,
        backupFiles: MemoryBackupFiles(),
      ),
    );
    await settle(t);
    for (
      var i = 0;
      i < 100 && find.byType(NavigationBar).evaluate().isEmpty;
      i++
    ) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(NavigationBar), findsOneWidget);
  }

  Future<void> tap(WidgetTester t, Finder f) async {
    if (f.evaluate().isEmpty) {
      await t.scrollUntilVisible(
        f,
        250,
        scrollable: find.byType(Scrollable).first,
      );
    } else {
      await t.ensureVisible(f);
    }
    await t.pumpAndSettle();
    await t.tap(f);
    await settle(t);
  }

  testWidgets('five destinations and settings return to every main page', (
    t,
  ) async {
    await boot(t);
    final router = GoRouter.of(t.element(find.byType(NavigationBar)));
    final labels = t
        .widget<NavigationBar>(find.byType(NavigationBar))
        .destinations
        .cast<NavigationDestination>()
        .map((d) => d.label);
    expect(labels, ['训练', '热量', '动作分析', '历史', '进步']);
    for (final path in [
      '/',
      '/calories',
      '/analysis',
      '/history',
      '/progress',
    ]) {
      router.go(path);
      await settle(t);
      await tap(t, find.byTooltip('设置'));
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(BackButton), findsOneWidget);
      await tap(t, find.byType(BackButton));
      expect(router.state.uri.path, path);
    }
    await t.pumpWidget(const SizedBox());
    await settle(t);
  });
  testWidgets(
    'quick record validates zero quantity, saves once and undo deletes',
    (t) async {
      await t.runAsync(() => BeverageRepo(db).saveBeverage(beverage()));
      await boot(t);
      await tap(t, find.byType(NavigationDestination).at(1));
      expect(find.text('尚未记录'), findsWidgets);
      await tap(t, find.widgetWithText(ActionChip, '可乐'));
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(AppBar), findsOneWidget);
      final amount = find.widgetWithText(TextField, '饮用量');
      await t.enterText(amount, '0');
      await tap(t, find.text('保存记录'));
      expect(find.textContaining('保存失败'), findsOneWidget);
      await t.enterText(amount, '0.5');
      await tap(t, find.text('保存记录'));
      expect(find.text('69.3 kcal'), findsWidgets);
      await t.runAsync(
        () async => expect((await BeverageRepo(db).records()).length, 1),
      );
      await tap(t, find.text('撤销'));
      await t.runAsync(
        () async => expect(await BeverageRepo(db).records(), isEmpty),
      );
      await t.pumpWidget(const SizedBox());
      await settle(t);
    },
  );
  for (final size in [const Size(320, 480), const Size(640, 360)]) {
    testWidgets('review form scrolls at $size with large text and keyboard', (
      t,
    ) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      t.view.viewInsets = const FakeViewPadding(bottom: 180);
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      addTearDown(t.view.resetViewInsets);
      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(AppColors.light),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(2),
              disableAnimations: true,
            ),
            child: child!,
          ),
          home: BeverageEditorPage(
            initial: Beverage.fromJson({
              ...beverage().toJson(),
              'kind': 'prepared',
              'size': '大杯',
              'sugar': '三分糖',
            }),
          ),
        ),
      );
      await t.pumpAndSettle();
      await t.scrollUntilVisible(
        find.text('确认资料'),
        300,
        scrollable: find.byType(Scrollable).first,
        maxScrolls: 40,
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.pumpWidget(const SizedBox());
    });
  }
}
