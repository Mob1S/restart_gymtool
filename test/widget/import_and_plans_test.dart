import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/app/providers.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/files/backup_file_store.dart';
import 'package:gym_tracker/data/repositories/backup_repo.dart';
import 'package:gym_tracker/data/repositories/template_repo.dart';
import 'package:gym_tracker/data/repositories/session_repo.dart';

import '../support/backup_fakes.dart';
import 'backup_section_test.dart' show settle;

void main() {
  late FfiExecutor db;
  late MemoryBackupFiles files;
  setUp(() async {
    db = await FfiExecutor.openMigrated();
    files = MemoryBackupFiles();
  });
  tearDown(() async => db.close());
  Future<void> tap(WidgetTester t, String text) async {
    await t.ensureVisible(find.text(text).first);
    await t.pumpAndSettle();
    await t.tap(find.text(text).first);
    await settle(t);
  }

  Future<void> boot(WidgetTester t) async {
    await t.pumpWidget(
      AppBootstrap(openDatabase: () async => db, backupFiles: files),
    );
    await settle(t);
    await tap(t, '设置');
  }

  testWidgets(
    'CSV real picker button, cancel, append, note and targeted history deletion',
    (t) async {
      files.selected = PickedBackup(
        'strong.csv',
        utf8.encode(
          'Date,Workout Name,Exercise Name,Weight,Reps\n2024-01-01 10:00,Import day,深蹲,20,8',
        ),
      );
      await boot(t);
      await tap(t, '历史');
      await t.tap(find.byTooltip('记录操作'));
      await settle(t);
      await tap(t, '导入 CSV');
      await tap(t, '选择 CSV 文件');
      expect(find.text('追加 1 场训练'), findsOneWidget);
      await t.runAsync(() async {
        expect(
          (await exportBackup(db, exportedAt: 0)).rows('sessions'),
          isEmpty,
        );
      });
      await tap(t, '取消预览');
      await tap(t, '选择 CSV 文件');
      await tap(t, '追加 1 场训练');
      expect(find.text('Import day'), findsOneWidget);
      await tap(t, 'Import day');
      expect(find.textContaining('时长未知'), findsOneWidget);
      await t.tap(find.byTooltip('删除这场训练'));
      await settle(t);
      await tap(t, '取消');
      await t.runAsync(() async {
        expect(await listSessions(db, 10), hasLength(1));
      });
      await t.tap(find.byTooltip('删除这场训练'));
      await settle(t);
      await tap(t, '删除这场训练');
      expect(find.text('还没有已完成的训练'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
      await settle(t);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'plan draft supports duplicate actions; save, cancel delete and delete',
    (t) async {
      await boot(t);
      await tap(t, '训练');
      await tap(t, '管理计划');
      await tap(t, '新建计划');
      await t.enterText(find.byType(TextField), 'A');
      await settle(t);
      await tap(t, '添加训练日');
      await t.enterText(find.widgetWithText(TextField, '训练日名称'), '力量日');
      await tap(t, '添加动作');
      await t.enterText(find.widgetWithText(TextField, '搜索动作'), '深蹲');
      await settle(t);
      await t.tap(find.widgetWithText(ListTile, '深蹲'));
      await settle(t);
      await tap(t, '添加 1 个动作');
      await tap(t, '添加动作');
      await t.enterText(find.widgetWithText(TextField, '搜索动作'), '深蹲');
      await settle(t);
      await t.tap(find.widgetWithText(ListTile, '深蹲'));
      await settle(t);
      await tap(t, '添加 1 个动作');
      await t.runAsync(() async {
        expect(await listTemplates(db), isEmpty);
      });
      await tap(t, '完成');
      await tap(t, '保存');
      expect(find.text('A'), findsOneWidget);
      expect(find.text('1 个训练日 · 2 个动作'), findsOneWidget);
      await t.runAsync(() async {
        final list = await listTemplates(db);
        expect(
          (await getTemplate(db, list.single.template.id))!.exercises,
          hasLength(2),
        );
      });
      await t.tap(find.byTooltip('删除计划'));
      await settle(t);
      await tap(t, '取消');
      expect(find.text('A'), findsOneWidget);
      await t.tap(find.byTooltip('删除计划'));
      await settle(t);
      await tap(t, '删除计划');
      await t.runAsync(() async {
        expect(await listTemplates(db), isEmpty);
      });
      await t.pumpWidget(const SizedBox());
      await settle(t);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'manual input uses preview and same repository for 460 kg volume',
    (t) async {
      await boot(t);
      await tap(t, '历史');
      await tap(t, '补加');
      await t.enterText(
        find.widgetWithText(TextField, '训练名称（可空）'),
        'Manual day',
      );
      await t.enterText(
        find.widgetWithText(TextField, '开始时间'),
        '2024-01-01 10:00',
      );
      await t.enterText(
        find.widgetWithText(TextField, '结束时间'),
        '2024-01-01 11:00',
      );
      await t.enterText(
        find.widgetWithText(TextField, '或输入新动作名称'),
        'New action',
      );
      await tap(t, '加入新动作草稿');
      await tap(t, '添加一组');
      await t.enterText(find.widgetWithText(TextField, '重量 kg').last, '30');
      await t.enterText(find.widgetWithText(TextField, '次数').last, '10');
      await tap(t, '预览补记');
      await tap(t, '追加 1 场训练');
      await tap(t, 'Manual day');
      expect(find.text('460'), findsOneWidget);
      await t.runAsync(() async {
        expect(
          (await exportBackup(db, exportedAt: 0)).rows('sets'),
          hasLength(2),
        );
      });
      await t.pumpWidget(const SizedBox());
      await settle(t);
      expect(t.takeException(), isNull);
    },
  );
}
