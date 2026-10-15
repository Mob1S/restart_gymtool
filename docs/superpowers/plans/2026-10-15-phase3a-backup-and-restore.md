# Phase 3A Backup and Restore Implementation Plan

> **For agentic workers:** 在当前会话逐项实施和自查。用户已选择按推荐设计继续，不重复要求选择执行方式。步骤使用复选框记录实际结果。

**Goal:** 提供 Android / Web 可用的 JSON 导出与完整恢复，兼容旧 v1 / v2；坏文件不写库，写入异常全量回滚。

**Architecture:** 纯 Dart 协议与校验 → SQL 仓储的真实事务 → 可注入文件接口 → controller → 现有设置页。提前增加计划存储，不添加计划界面。

**Tech Stack:** Flutter 3.47.6、Dart 3.13.5、sqflite / FFI / wasm、file_picker 13.1.0、Node 24 / Chrome / ADB。

## Global Constraints

- 规格：[Phase 3A 设计](../specs/2026-10-15-flutter-gym-tracker-phase3a-design.md)，用户已确认。
- 备份标识 `gym-tracker-backup`，导出 version 2；导入 version 1 / 2；schema v4。
- 已发布 v1–v3 迁移不改动；两张计划表只追加在 v4。
- UTF-8 文件最多 20 MiB，总实体记录最多 100,000；字段、唯一性、引用全部先校验。
- 参数化 SQL；事务内只使用传入的 tx；文件选择和确认在事务之外。
- 不恢复来源 schema_version；seed_initialized 标记是本机内部约定。
- domain 不依赖 Flutter / IO，SQL 仅在数据层，界面不直接 import data/db。
- 真机恢复对抗测试仅使用 `.acceptance` 包，不清空主应用数据。
- 保留上一期未提交成果、用户 `.claude/settings.local.json` 和 `.tmp/`；提交只使用明确文件清单。
- CSV 与手动补记留 Phase 3B，计划编辑与轮转留 Phase 4。

## 文件结构与接口

| 文件 | 职责 / 输出 |
|---|---|
| lib/domain/backup.dart | BackupFile 不可变快照、BackupValidationException、字段与引用校验 |
| lib/domain/backup_codec.dart | decodeBackup / encodeBackup、UTF-8 BOM 与 20 MiB 上限 |
| lib/data/db/sql_executor.dart | transaction<T>(Future<T> Function(SqlExecutor tx)) |
| lib/data/db/transaction_executor.dart | 底层 DatabaseExecutor 的事务作用域适配 |
| lib/data/repositories/backup_repo.dart | exportBackup / inspectBackup / restoreBackup、规范化本机数据比较 |
| lib/data/files/backup_file_store.dart | 可注入 BackupFileStore，平台 pick / save 与分块限额 |
| lib/state/backup_controller.dart | busy、预览、取消、错误、提交与恢复后刷新 |
| lib/features/settings/backup_section.dart | 导出 / 恢复按钮、预览、确认与结果 |
| test/fixtures/backup/ | 固定 v1、含计划 v2、带设置 v2 与坏文件 |

## Task 1：事务、v4 与播种标记

**Modify:** `lib/data/db/{sql_executor,sqflite_executor,ffi_executor,schema,migrations}.dart`、`lib/data/repositories/exercise_repo.dart`。
**Create:** `lib/data/db/transaction_executor.dart`、`test/data/transaction_test.dart`。
**Test:** `test/data/migrations_test.dart`、`test/data/exercise_repo_test.dart`。

新增接缝：

```dart
Future<T> transaction<T>(Future<T> Function(SqlExecutor tx) action);
```

- [ ] 先添加真实 FFI 用例，调用 transaction 后插入一条动作再抛 StateError，断言动作表为空；运行时应因接口缺失编译失败。
- [ ] 在两个执行器上用 `_db.transaction((tx) => action(TransactionExecutor(tx)))` 实现；作用域执行器复用 splitSqlStatements，拒绝嵌套事务。
- [ ] 追加 v4 的 split_template / template_exercise / 索引，schemaVersion 改为 4。
- [ ] 增加 v3 旧库升级测试，升级前计划表不存在、升级后存在且原训练记录不变。
- [ ] 播种在事务中检查 seed_initialized 与动作计数；已有动作只补标记，新库完成 52 条插入后写标记。空库已有标记时不播种。
- [ ] 执行：`flutter test test/data/transaction_test.dart test/data/migrations_test.dart test/data/exercise_repo_test.dart`，期望全部通过。

## Task 2：备份协议与字节编解码

**Create:** `lib/domain/backup.dart`、`lib/domain/backup_codec.dart`、`test/domain/backup_test.dart`、`test/domain/backup_codec_test.dart`、`test/fixtures/backup/*.json`。

接口：

```dart
BackupFile validateBackup(Object? input);
BackupFile decodeBackup(List<int> bytes);
List<int> encodeBackup(BackupFile backup);
```

BackupFile 构造仅通过校验入口，持有递归不可变的 Map / List；以 toJson 导出完整 camelCase 协议。保留六个实体数组及可选 settings 是否存在的区别。

- [ ] 先写 v1 缺计划字段、旧 v2 含计划、当前 v2 含设置的 fixture 与读写测试；运行时应因模块缺失失败。
- [ ] 明确字段类型表，逐项构建规范化对象；必需 null 字段不能省略，v1 兼容项除外。
- [ ] 校验唯一 ID / 设置键、所有父子引用与非空 templateId；限制最多一个活动训练。
- [ ] 实现非负整数、有限重量、DateTime 上界和数量限制；拒绝未来版本与 schema。
- [ ] UTF-8 严格解码、只剥开头 BOM；JSON 失败转换成中文 BackupValidationException；导出和导入均检查 20 MiB。
- [ ] 对每种拒绝原因、空数组、未完成占位组、空训练和不可变性写有区分力的断言；执行 `flutter test test/domain/backup_test.dart test/domain/backup_codec_test.dart`。

## Task 3：一致导出与事务恢复

**Create:** `lib/data/repositories/backup_repo.dart`、`test/data/backup_repo_test.dart`。

接口：

```dart
Future<BackupFile> exportBackup(SqlExecutor exec, {required int exportedAt});
Future<BackupPreview> inspectBackup(SqlExecutor exec, BackupFile incoming);
Future<void> restoreBackup(SqlExecutor exec, BackupPreview preview);
```

BackupPreview 含校验后的 incoming 与本机规范 JSON 字符串。规范内容只包含固定顺序的业务表和设置；实体按 rowid ASC、设置按 key，忽略 exportedAt。

- [ ] 先写导出→恢复→再导出的逐字段比较测试，含同毫秒逆序 ID、计划引用、自定义动作、未完成组及 settings；应因模块缺失失败。
- [ ] 固定表 / 字段映射，布尔在 SQLite 0/1 与 JSON bool 间转换；在一个事务内导出全部表。
- [ ] inspectBackup 校验输入并保存本机数据快照；restoreBackup 再校验 incoming，在事务起点比较本机快照，不一致则拒绝并要求重新预览。
- [ ] 按规格顺序删除 / 插入；settings 缺失保留、存在替换；末尾写 seed_initialized，执行 foreign_key_check 后提交。
- [ ] 恢复空备份后再次播种 / 重启，不出现 52 条额外动作；schema_version 仍为 4。
- [ ] 使用委托故障执行器在删除后、插入时、settings 后抛同一原始异常；逐表比较回滚前后数据，确认异常身份未丢失。
- [ ] `flutter test test/data/backup_repo_test.dart` 全绿后，临时移除 transaction 包装，确认回滚测试失败并还原。

## Task 4：文件入口与取消

**Modify:** `pubspec.yaml`、`pubspec.lock`。
**Create:** `lib/data/files/backup_file_store.dart`、`test/data/backup_file_store_test.dart`。

接口：

```dart
abstract interface class BackupFileStore {
  Future<PickedBackup?> pick();
  Future<bool> save(String name, List<int> bytes);
}
```

PickedBackup 保存 name 与 bytes；null / false 代表取消。实际平台插件被薄适配器包住，可注入读取流与保存回调，测试不冒充系统文件界面。

- [ ] 锁定 `file_picker: 13.1.0`，解析依赖并检查当前 SDK / AGP 兼容性；不升级其他无关依赖。
- [ ] 用 file_picker 13 的 pickFile / saveFile；读取使用 lengthSync / length 预检和 readAsByteStream 累计检查，超过 20 MiB 停止。
- [ ] 系统文件返回 null 视作取消；异常翻译为中文，保存文件名与文件内容使用同一个时刻。
- [ ] 测试已知长度超限、未知长度中途超限、读错误、取消与保存错误；`flutter test test/data/backup_file_store_test.dart` 全绿。

## Task 5：恢复编排与旧内存清理

**Create:** `lib/state/backup_controller.dart`、`test/state/backup_controller_test.dart`。
**Modify:** `lib/state/active_session_controller.dart`。

- [ ] 先写重复点击只执行一次、取消不恢复、未预览不能确认、成功触发刷新一次、失败不触发刷新测试。
- [ ] controller 接受 SqlExecutor、BackupFileStore 和提交后的刷新回调；所有 Future 的 busy 用 finally 清理。
- [ ] 校验后才能产生预览；选择新文件或取消时清除旧预览；确认恢复只能使用当前预览对象。
- [ ] 新增活动训练重新载入方法：先清 session / exercises / currentIndex，再 resume；测试恢复成无活动训练时不残留旧 session。
- [ ] 提交后刷新回调失败时明确显示「数据已恢复，界面刷新失败，请重新打开应用」，不声称已提交事务回滚。
- [ ] `flutter test test/state/backup_controller_test.dart test/state/active_session_controller_test.dart` 全绿。

## Task 6：设置入口与应用装配

**Create:** `lib/features/settings/backup_section.dart`、`test/widget/backup_section_test.dart`。
**Modify:** `lib/features/settings/settings_page.dart`、`lib/app/providers.dart`。

- [ ] 写实际按钮点击与预览文案断言，包含本机 / 文件场数、活动训练、空备份提示；取消后写库次数仍为 0。
- [ ] 设置页在有 BackupController provider 时显示备份区，保持旧主题测试环境可单独装配。
- [ ] 预览对话框只在明确点击「替换并恢复」后提交；返回 / 点击外部等同取消，写库阶段禁用退出与重复提交。
- [ ] AppBootstrap 装配 controller，恢复提交后重载活动训练与主题，以 revision key 更新应用子树并导航首页；router 实例不重建。
- [ ] `flutter test test/widget/backup_section_test.dart test/app/router_test.dart test/widget/viewport_test.dart` 全绿，核对窄屏和大字号。

## Task 7：发布构建与真实文件往返

**Modify:** `scripts/browser_smoke.mjs`、`scripts/android_acceptance.mjs`；增加专用备份走查脚本保存证据。

- [ ] `dart format lib test`、`flutter analyze`、`flutter test --reporter expanded` 全部通过；记录最终数量。
- [ ] `flutter build web --no-pub`，Chrome 实际导出下载的 JSON，再上传到隔离空库；检查历史、进步和原字段，坏文件不改变数据。
- [ ] 更新原首次建库检查为 schema 4 / 8 张应用表；不改写上一期 schema 3 的历史证据。
- [ ] `GYM_ACCEPTANCE_BUILD=1` 构建独立 debug，在用户已授权设备上通过系统文件界面导出 / 恢复 / 取消 / 坏文件走查。
- [ ] 独立包清库测试后恢复 v1 和含非空计划的 v2，逐字段核对；不对主包清库。
- [ ] 卸载独立包，重建默认 release，验证包名与 SHA-256，必要时保留数据更新主应用。

## Task 8：文档、变异证据与提交

**Modify:** 本计划、Phase 3A 规格、README、环境笔记；只按实际回填。

- [ ] 记录范围调整：v4 的计划存储提前，计划界面仍未实现；当前备份能力和运行方式写入 README。
- [ ] 记录事务、引用、rowid、取消检查的变异实际失败信息；产品代码随后恢复。
- [ ] 对照规格所有完成条件，自查没有仅构建通过却写成真机通过的项目。
- [ ] `git diff --check`，检查最终差异；按明确文件清单分次提交，不使用 git add -A。
- [ ] 本期交付后转入 Phase 3B 的独立设计。

## 执行记录

2026-10-15：用户确认推荐设计。已完成规格自查；正在开始 Task 1。每项完成后记录测试命令与结果。
