import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/app/providers.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/repositories/backup_repo.dart';
import 'package:gym_tracker/data/repositories/exercise_repo.dart';
import 'package:gym_tracker/data/repositories/settings_repo.dart';
import 'package:gym_tracker/domain/backup_codec.dart';
import 'package:gym_tracker/domain/backup.dart';
import 'package:gym_tracker/features/settings/backup_section.dart';
import 'package:gym_tracker/state/active_session_controller.dart';
import 'package:gym_tracker/state/backup_controller.dart';
import 'package:gym_tracker/ui/theme.dart';
import 'package:gym_tracker/ui/tokens.dart';
import 'package:provider/provider.dart';

import '../data/backup_repo_test.dart' show loadFixture;
import '../support/backup_fakes.dart';
import '../domain/backup_test.dart' show fixture;

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  late FfiExecutor exec;
  late MemoryBackupFiles files;
  late BackupController controller;
  Future<void> Function()? refresh;
  setUp(() async {
    exec = await FfiExecutor.openMigrated();
    files = MemoryBackupFiles();
    refresh = null;
    controller = BackupController(
      exec: exec,
      files: files,
      onRestored: () async {
        await refresh?.call();
      },
    );
  });
  tearDown(() async {
    controller.dispose();
    await exec.close();
  });

  Future<void> pumpSection(WidgetTester tester, {double scale = 1}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(AppColors.light),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: ListView(children: [BackupSection(controller: controller)]),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> tap(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    await tester.tap(find.text(text));
    await settle(tester);
  }

  testWidgets('real export button saves parseable snapshot', (tester) async {
    await pumpSection(tester);
    await tap(tester, '导出备份');
    expect(decodeBackup(files.savedBytes!).schemaVersion, 5);
    expect(find.text('备份已保存'), findsOneWidget);
  });

  testWidgets(
    'restore explains replacement of 52 library actions with the one-action fixture',
    (tester) async {
      await tester.runAsync(() => seedExercisesIfEmpty(exec));
      files.useFixture();
      await pumpSection(tester);
      await tap(tester, '从备份恢复');
      expect(find.text('动作库：本机 52 个 → 备份 1 个'), findsOneWidget);
      expect(find.text('训练计划：本机 0 个 → 备份 1 个'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.textContaining('动作库、训练记录和训练计划'),
        ),
        findsOneWidget,
      );
      await tap(tester, '取消');
      await tester.runAsync(() async {
        expect(
          (await exportBackup(exec, exportedAt: 0)).rows('exercises'),
          hasLength(52),
        );
      });
    },
  );

  testWidgets(
    'preview shows source/local counts, plans, active warning; cancel never writes',
    (tester) async {
      await tester.runAsync(
        () async =>
            restoreBackup(exec, await inspectBackup(exec, loadFixture())),
      );
      files.useFixture();
      await pumpSection(tester);
      await tap(tester, '从备份恢复');
      expect(find.text('训练：2 场 · 已完成 1 场'), findsOneWidget);
      expect(find.text('计划：1 个'), findsOneWidget);
      expect(find.textContaining('本机的 2 场训练'), findsOneWidget);
      expect(find.text('本机有进行中的训练，它也会被替换。'), findsOneWidget);
      await tap(tester, '取消');
      expect(controller.revision, 0);
      expect(controller.preview, isNull);
      await tester.runAsync(() async {
        expect(
          (await exportBackup(exec, exportedAt: 0)).rows('sessions'),
          hasLength(2),
        );
      });
    },
  );

  testWidgets('empty restore warns; system back cancels and controls recover', (
    tester,
  ) async {
    files.useFixture('current-v2');
    await pumpSection(tester);
    await tap(tester, '从备份恢复');
    expect(find.text('此备份没有训练记录，恢复后本机现有训练将被清空'), findsOneWidget);
    await tester.binding.handlePopRoute();
    await settle(tester);
    expect(find.byType(AlertDialog), findsNothing);
    expect(controller.preview, isNull);
    await tap(tester, '导出备份');
    expect(files.saves, 1);
  });

  testWidgets('write/refresh blocks back, barrier and double submit', (
    tester,
  ) async {
    final gate = Completer<void>();
    refresh = () => gate.future;
    files.useFixture();
    await pumpSection(tester);
    await tap(tester, '从备份恢复');
    await tap(tester, '替换并恢复');
    expect(controller.restoring, isTrue);
    await tester.binding.handlePopRoute();
    await tester.tapAt(const Offset(2, 2));
    await settle(tester);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '正在恢复…'))
          .onPressed,
      isNull,
    );
    gate.complete();
    await settle(tester);
    expect(controller.revision, 1);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final (size, scale) in [
    (const Size(320, 480), 1.0),
    (const Size(640, 360), 1.0),
    (const Size(360, 640), 2.0),
  ]) {
    testWidgets(
      'preview scrolls and confirmation reachable $size scale=$scale',
      (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = size;
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.view.resetPhysicalSize);
        files.useFixture('current-v2');
        await pumpSection(tester, scale: scale);
        await tap(tester, '从备份恢复');
        await tester.ensureVisible(find.text('替换并恢复'));
        expect(tester.takeException(), isNull);
        await tap(tester, '取消');
      },
    );
  }

  testWidgets(
    'production bootstrap refreshes active memory, theme, history and progress without restart',
    (tester) async {
      final visibleFixture = fixture();
      visibleFixture['data']['exercises'][0]['isArchived'] = false;
      await tester.runAsync(
        () async => restoreBackup(
          exec,
          await inspectBackup(exec, validateBackup(visibleFixture)),
        ),
      );
      await tester.pumpWidget(
        AppBootstrap(openDatabase: () async => exec, backupFiles: files),
      );
      await settle(tester);
      final session = tester
          .element(find.byType(Scaffold).first)
          .read<ActiveSessionController>();
      await tester.runAsync(session.resume);
      await settle(tester);
      expect(session.session?.id, 'active-s');
      expect(session.exercises, isNotEmpty);
      await tap(tester, '历史');
      expect(find.textContaining('推日'), findsWidgets);
      await tap(tester, '进步');
      expect(find.textContaining('我的推胸'), findsWidgets);
      files.useFixture('current-v2');
      await tap(tester, '设置');
      await tap(tester, '从备份恢复');
      await tap(tester, '替换并恢复');
      expect(session.session, isNull);
      expect(session.exercises, isEmpty);
      expect(session.currentIndex, 0);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.text('开始训练'), findsOneWidget);
      expect(
        Theme.of(tester.element(find.byType(Scaffold).first)).brightness,
        Brightness.dark,
      );
      await tester.runAsync(
        () async => expect(await getSetting(exec, 'theme_mode'), 'dark'),
      );
      await tap(tester, '历史');
      expect(find.textContaining('还没有已完成的训练'), findsOneWidget);
      await tap(tester, '进步');
      expect(find.textContaining('还没有练过的动作'), findsOneWidget);
      files.useJson(visibleFixture);
      await tap(tester, '设置');
      await tap(tester, '从备份恢复');
      await tap(tester, '替换并恢复');
      expect(session.session?.id, 'active-s');
      expect(session.exercises.single.sets.single.weight, 20);
      expect(find.textContaining('继续'), findsWidgets);
      await tap(tester, '历史');
      expect(find.textContaining('推日'), findsWidgets);
      await tap(tester, '进步');
      expect(find.textContaining('我的推胸'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    },
  );
}
