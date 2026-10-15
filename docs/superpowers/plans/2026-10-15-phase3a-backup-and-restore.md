# Phase 3A Backup and Restore Implementation Plan

> **当前执行状态（2026-10-16）**：用户已要求接续并完成工作。Task 0–6 的实现和测试已完成；304 条测试、8 项变异、Web 构建与真实浏览器文件往返均通过。Android 独立 debug、默认 debug / release 均已构建，包名与哈希已核对。详情见[执行结果](./2026-10-16-phase3a-execution.md)。真机未连接，文件界面验收仍待完成，不能将本期标为全部验收通过。
>
> **For agentic workers:** 从已有实现接续，已完成项不重写；用户此前已确认推荐设计。复选框只记录实际完成。先读[当前状态交接](./2026-10-15-current-state.md)。

**Goal:** 提供 Android / Web 可用的 JSON 导出与完整恢复，兼容旧 v1 / v2；坏文件不写库，写入异常全量回滚。

**Architecture:** 纯 Dart 协议与校验 → SQL 仓储的真实事务 → 可注入文件接口 → controller → 现有设置页。提前增加计划存储，不添加计划界面。

**Tech Stack:** Flutter 3.47.6、Dart 3.13.5、sqflite / FFI / wasm、file_picker 13.1.0、Node 24 / Chrome / ADB。

## 当前基线与交付顺序

当前格式和静态检查通过，**304 条测试通过**（相对 257 条交接基线增加 47 条）。协议、事务、仓储、文件接口、controller 与 UI 均已实现；Web 发布构建及真实文件往返通过。Android 独立 debug、默认 debug / release 均构建成功，真机文件验收因无设备未执行。

| 任务 | 当前状态 | 依赖 | 交付判据 |
|---|---|---|---|
| 0 工作区与核心检查补齐 | 完成 | 当前工作区 | 不丢改动、格式通过、边界测试补齐 |
| 1 事务 / v4 / 播种 | 核心与 FFI 测试已完成 | 0 | Android / Web 的事务仍随任务 7 验证 |
| 2 协议与编解码 | 完成，含边界及变异 | 0 | 35 条协议测试 |
| 3 导出 / 恢复仓储 | 完成，含边界及变异 | 1、2 | 10 条仓储测试；Web 往返通过，真机待验 |
| 4 文件适配 | 完成 | 2 | 10 条文件测试，Web 下载上传实测 |
| 5 恢复编排 | 完成 | 3、4 | 9 条 controller 测试，含提交前后失败 |
| 6 设置入口 / 应用装配 | 完成 | 5 | 8 条界面测试，包含真实 AppBootstrap 刷新 |
| 7 浏览器 / 真机 / 构建 | Web 与构建完成、真机待连接 | 6 | 真机 A1–A9 未运行 |
| 8 收尾与提交 | 结果已回填、本地分组提交 | 7 | 如实保留真机待验状态 |

本轮已按 **0 → 4 → 5 → 6 → 7 → 8** 接续，任务 1–3 在任务 0 补查。现在只剩任务 7 的真机 A1–A9；后续范围没有提前实施。

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

## Task 0：保留现场、清理格式与补核心缺口

**Existing:** `lib/domain/backup.dart`、`lib/domain/backup_codec.dart`、`lib/data/repositories/backup_repo.dart`、`lib/data/db/transaction_executor.dart`。
**Modify tests:** `test/data/backup_foundation_test.dart`、`test/domain/backup_test.dart`、`test/data/backup_repo_test.dart`。

- [x] 读取当前状态交接，运行 `git status --short` 和 `git diff --stat`。区分用户改动、Phase 1–2 收尾和 Phase 3A；不执行 reset / clean / add -A。
- [x] 确认上一期 release APK 未被误当本期包，手机不安装当前尚无入口的半成品。
- [x] 格式化下列 7 个文件，核对差异只是格式；不得对用户配置或其他目录批量改写。

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
. .\scripts\env.ps1
dart format lib/data/repositories/backup_repo.dart lib/data/repositories/exercise_repo.dart lib/domain/backup.dart lib/domain/backup_codec.dart test/data/backup_foundation_test.dart test/data/backup_repo_test.dart test/domain/backup_test.dart
dart format --output=none --set-exit-if-changed lib test
```

第二条命令预期 exit 0。整理时的只读格式检查 exit 1，未写入文件。

- [x] 在现有测试中补下表有判别力的缺口；先确认新测试能检出对应错误，再保留正确实现。

| 测试文件 | 增补用例 | 必须断言 |
|---|---|---|
| backup_foundation_test | 事务作用域内再次开事务 | 明确失败，外层已写记录回滚，不等待死锁 |
| backup_foundation_test | 存量已有动作但无 seed_initialized | 只补标记，不再插入 52 动作 |
| backup_foundation_test | 播种中途写入失败 | 动作与标记同回滚，不留下半份预置库 |
| backup_test | 总数组长度 100,001 | 在逐条处理前拒绝；不只测重复 ID |
| backup_test | 根为 null / 数组，空白 ID、错误 nullable 类型 | 中文错误指向正确路径 |
| backup_test | 负 position / reps / restSeconds、分数时间戳、非法布尔 | 各字段规则实际生效 |
| backup_test | 空备份、合法零重量和零次占位、空训练 | 不把备份合法数据按 CSV 导入规则误拒绝 |
| backup_test | 缺失 settings 与空 settings 数组 | 两者有区别，前者保留偏好、后者清空偏好 |
| backup_repo_test | 同时间戳、逆字典序 ID、并列 position | 导出与恢复均依赖 rowid / 数组顺序 |
| backup_repo_test | schema_version=4 与来源 schema=1 | 恢复旧文件后本机结构号仍为 4 |
| backup_repo_test | 原 seed 标记缺失，在写新标记之后注入异常 | 回滚后标记仍缺失；不能用「原本就是 1」的情况证明它回滚了 |
| backup_repo_test | 恢复空数据，关闭再打开文件型测试库 | 再播种后仍为空，验证不止一次函数调用 |

- [x] 保存基线日志并执行以下命令；当前 257 条全部仍绿，新用例按实际增加，不以凑数量为目标。

```powershell
flutter analyze --no-pub
flutter test --no-pub test/data/backup_foundation_test.dart test/domain/backup_test.dart test/data/backup_repo_test.dart --reporter expanded
flutter test --no-pub --reporter expanded
```

## Task 1：事务、v4 与播种标记

**Modify:** `lib/data/db/{sql_executor,sqflite_executor,ffi_executor,schema,migrations}.dart`、`lib/data/repositories/exercise_repo.dart`。
**Created:** `lib/data/db/transaction_executor.dart`、`test/data/backup_foundation_test.dart`。
**Test:** `test/data/migrations_test.dart`、`test/data/exercise_repo_test.dart`。

新增接缝：

```dart
Future<T> transaction<T>(Future<T> Function(SqlExecutor tx) action);
```

- [x] 先添加真实 FFI 用例，因 transaction 接口缺失实际编译失败。
- [x] 在两个执行器上用 `_db.transaction((tx) => action(TransactionExecutor(tx)))` 实现；作用域执行器复用 splitSqlStatements，拒绝嵌套事务。
- [x] 追加 v4 的 split_template / template_exercise / 索引，schemaVersion 改为 4。
- [x] 增加 v3 旧库升级测试，升级前计划表不存在、升级后存在且原训练记录不变。
- [x] 播种在事务中检查 seed_initialized 与动作计数；已有动作只补标记，新库完成 52 条插入后写标记。空库已有标记时不播种。
- [x] `flutter test test/data/backup_foundation_test.dart test/data/migrations_test.dart test/data/exercise_repo_test.dart` 实际 21 条通过。

## Task 2：备份协议与字节编解码

**Created:** `lib/domain/backup.dart`、`lib/domain/backup_codec.dart`、`test/domain/backup_test.dart`、`test/fixtures/backup/{legacy-v1,legacy-v2,current-v2}.json`。编解码测试已合入 backup_test，不新建重复测试文件。

接口：

```dart
BackupFile validateBackup(Object? input);
BackupFile decodeBackup(List<int> bytes);
List<int> encodeBackup(BackupFile backup);
```

BackupFile 构造仅通过校验入口，持有递归不可变的 Map / List；以 toJson 导出完整 camelCase 协议。保留六个实体数组及可选 settings 是否存在的区别。

- [x] 先写三份 fixture 与测试，因模块缺失实际失败。
- [x] 明确字段类型表，逐项构建规范化对象；必需 null 字段不能省略，v1 兼容项除外。
- [x] 校验唯一 ID / 设置键、所有父子引用与非空 templateId；限制最多一个活动训练。
- [x] 实现非负整数、有限重量、DateTime 上界和数量限制；拒绝未来版本与 schema。
- [x] UTF-8 严格解码、只剥开头 BOM；JSON 失败转换成中文 BackupValidationException；导出和导入均检查 20 MiB。
- [x] `flutter test test/domain/backup_test.dart` 22 条通过。
- [x] 按 Task 0 补齐仍未实际覆盖的边界，不将实现存在视作测试完成。

## Task 3：一致导出与事务恢复

**Create:** `lib/data/repositories/backup_repo.dart`、`test/data/backup_repo_test.dart`。

接口：

```dart
Future<BackupFile> exportBackup(SqlExecutor exec, {required int exportedAt});
Future<BackupPreview> inspectBackup(SqlExecutor exec, BackupFile incoming);
Future<void> restoreBackup(SqlExecutor exec, BackupPreview preview);
```

BackupPreview 含校验后的 incoming 与本机规范 JSON 字符串。规范内容只包含固定顺序的业务表和设置；实体按 rowid ASC、设置按 key，忽略 exportedAt。

- [x] 先写导出→恢复→再导出的逐字段比较测试，含同毫秒逆序 ID、计划引用、自定义动作、未完成组及 settings；实际因模块缺失失败。
- [x] 固定表 / 字段映射，布尔在 SQLite 0/1 与 JSON bool 间转换；在一个事务内导出全部表。
- [x] inspectBackup 校验输入并保存本机数据快照；restoreBackup 再校验 incoming，在事务起点比较本机快照，不一致则拒绝并要求重新预览。
- [x] 按规格顺序删除 / 插入；settings 缺失保留、存在替换；末尾写 seed_initialized，执行 foreign_key_check 后提交。
- [x] 恢复空备份后再次调用播种仍为空，schema_version 为 4；真实文件型库重开与平台重启留 Task 0 / 7 验证。
- [x] 在删除后、插入时、settings 后抛同一原始异常；逐表比较回滚前后数据，异常身份保留。
- [x] `flutter test test/data/backup_repo_test.dart` 6 条通过。
- [x] 按后文变异矩阵执行移除事务等破坏，记录真实失败并还原。

## Task 4：文件入口与取消

**Modify:** `pubspec.yaml`、`pubspec.lock`。
**Create:** `lib/data/files/backup_file_store.dart`、`test/data/backup_file_store_test.dart`。

接口：

```dart
enum BackupSaveResult { saved, downloadRequested, canceled }

abstract interface class BackupFileStore {
  Future<PickedBackup?> pick();
  Future<BackupSaveResult> save(String name, List<int> bytes);
}
```

PickedBackup 保存 name 与 bytes；pick 返回 null 代表取消。保存结果必须区分原生保存、Web 下载请求和取消。实际平台插件被薄适配器包住，可注入读取流与保存回调，测试不冒充系统文件界面。

- [x] 锁定 `file_picker: 13.1.0` 并成功解析，新增 8 个包，无无关依赖升级；SDK 声明满足当前 Flutter / Dart。
- [x] 在后续 Android / Web 构建中验证插件与 AGP 9.1.0 的实际兼容性，不以依赖解析成功代替编译结果。
- [x] 用 file_picker 13 的 pickFile / saveFile；读取使用 lengthSync / length 预检和 readAsByteStream 累计检查，超过 20 MiB 停止。
- [x] pick 返回 null 视作取消；save 在原生返回 null 才是取消，Web 无异常时返回 downloadRequested。异常翻译为中文，文件名与内容使用同一个时刻。
- [x] 测试已知长度超限、未知长度中途超限、读错误、取消与保存错误；`flutter test test/data/backup_file_store_test.dart` 全绿。

## Task 5：恢复编排与旧内存清理

**Create:** `lib/state/backup_controller.dart`、`test/state/backup_controller_test.dart`。
**Reuse:** `lib/state/active_session_controller.dart` 的现有 `reset()` 与 `resume()`；不改变旧 resume 语义。

- [x] 先写重复点击只执行一次、取消不恢复、未预览不能确认、成功触发刷新一次、失败不触发刷新测试。
- [x] controller 接受 SqlExecutor、BackupFileStore 和提交后的刷新回调；所有 Future 的 busy 用 finally 清理。
- [x] 校验后才能产生预览；选择新文件或取消时清除旧预览；确认恢复只能使用当前预览对象。
- [x] 恢复后的回调先调用现有 reset，再 resume；测试恢复成无活动训练时不残留旧 session，不重复实现已有清理方法。
- [x] 提交后刷新回调失败时明确显示「数据已恢复，界面刷新失败，请重新打开应用」，不声称已提交事务回滚。
- [x] `flutter test test/state/backup_controller_test.dart test/state/active_session_controller_test.dart` 全绿。

## Task 6：设置入口与应用装配

**Create:** `lib/features/settings/backup_section.dart`、`test/widget/backup_section_test.dart`。
**Modify:** `lib/features/settings/settings_page.dart`、`lib/app/providers.dart`、`lib/app/app_shell.dart`。

- [x] 写实际按钮点击与预览文案断言，包含本机 / 文件场数、活动训练、空备份提示；取消后写库次数仍为 0。
- [x] 设置页在有 BackupController provider 时显示备份区，保持旧主题测试环境可单独装配。
- [x] 预览对话框只在明确点击「替换并恢复」后提交；返回 / 点击外部等同取消，写库阶段禁用退出与重复提交。
- [x] AppBootstrap 装配 controller，恢复提交后重载活动训练与主题，以 revision key 更新 AppShell 下的页面子树并导航首页；不重建 router 或整个 MaterialApp。
- [x] `flutter test test/widget/backup_section_test.dart test/app/router_test.dart test/widget/viewport_test.dart` 全绿，核对窄屏和大字号。

## Task 7：发布构建与真实文件往返

**Modify:** `scripts/browser_smoke.mjs`、`scripts/android_acceptance.mjs`；增加专用备份走查脚本保存证据。

- [x] `dart format lib test`、`flutter analyze`、`flutter test --reporter expanded` 全部通过；最终 304 条。
- [x] `flutter build web --no-pub`，Chrome 实际导出下载的 JSON，再上传到隔离空库；检查历史、进步和原字段，坏文件不改变数据。
- [x] 更新原首次建库检查为 schema 4 / 8 张应用表；不改写上一期 schema 3 的历史证据。
- [x] `GYM_ACCEPTANCE_BUILD=1` 构建独立 debug，并另存本轮证据目录。
- [ ] 在连接并授权的设备上通过系统文件界面导出 / 恢复 / 取消 / 坏文件走查；本轮未连接设备。
- [ ] 独立包清库测试后恢复 v1 和含非空计划的 v2，逐字段核对；不对主包清库。
- [x] 重建默认 debug / release，验证主包名和 SHA-256；详见执行结果。
- [ ] 真机验收完成后卸载独立包；本轮尚未安装，亦未更新主应用。

## Task 8：文档、变异证据与提交

**Modify:** 本计划、Phase 3A 规格、README、环境笔记；只按实际回填。

- [x] 记录范围调整：v4 的计划存储提前，计划界面仍未实现；当前备份能力和运行方式写入 README。
- [x] 记录事务、引用、rowid、取消等 8 项变异实际失败信息；产品代码随后恢复。
- [x] 对照规格所有完成条件，自查没有仅构建通过却写成真机通过的项目；真机明确待验。
- [x] `git diff --check`，检查最终差异；按明确文件清单分次提交，不使用 git add -A。用户配置与 `.tmp/` 保留在提交之外。
- [ ] 本期交付后转入 Phase 3B 的独立设计。

## 执行记录

2026-10-15：用户确认推荐设计；已提交规格与初版计划（a70e692）。随后完成 Task 1–3 的核心及 32 条新增测试，下载锁定文件依赖。

历史记录（2026-10-15）：同日用户将当前任务收窄为「整理情况、写详细计划」。已停止功能实现；只读复核得到静态检查通过、257 条测试通过、7 个文件待格式化。完整文件与 Git 现场见[交接说明](./2026-10-15-current-state.md)。2026-10-16 用户再次要求实施，已完成下列功能步骤；最新结果见本文件开头与执行结果。

## Task 4 细化：文件层的具体实现与验证

### 4.1 已确认的平台差异

本地依赖源码 `file_picker_web-4.1.0/lib/src/file_picker_web.dart` 的 saveFile 在点击 Blob 下载后返回 null；这是成功触发下载，不是取消。Android 的 null 才可解释为取消。该差异必须在文件适配器内消化，controller 不直接判断 Uri。

### 4.2 待创建文件的完整接口与基础实现

保存到 `lib/data/files/backup_file_store.dart`。下面的代码是后续实施起点，本次没有写入应用目录：

```dart
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../domain/backup.dart';

enum BackupSaveResult { saved, downloadRequested, canceled }

class PickedBackup {
  final String name;
  final List<int> bytes;
  PickedBackup(this.name, List<int> bytes)
      : bytes = List<int>.unmodifiable(bytes);
}

abstract interface class BackupFileStore {
  Future<PickedBackup?> pick();
  Future<BackupSaveResult> save(String name, List<int> bytes);
}

typedef SaveBackupBytes = Future<Uri?> Function(String name, Uint8List bytes);

Future<PickedBackup> readBoundedBackup(
  String name,
  Stream<List<int>> stream, {
  int? reportedLength,
}) async {
  void check(int size) {
    if (size > maxBackupBytes) {
      throw const BackupValidationException('文件超过 20 MiB，未读取备份');
    }
  }
  if (reportedLength != null) check(reportedLength);
  final builder = BytesBuilder(copy: false);
  var received = 0;
  await for (final chunk in stream) {
    received += chunk.length;
    check(received);
    builder.add(chunk);
  }
  return PickedBackup(name, builder.takeBytes());
}

class PlatformBackupFileStore implements BackupFileStore {
  final Future<PlatformFile?> Function() _choose;
  final SaveBackupBytes _write;
  final bool _web;

  PlatformBackupFileStore({
    Future<PlatformFile?> Function()? choose,
    SaveBackupBytes? write,
    bool? web,
  }) : _choose = choose ?? (() => FilePicker.pickFile(type: FileType.any)),
       _write = write ?? ((name, bytes) => FilePicker.saveFile(
         fileName: name,
         bytes: bytes,
         mimeType: 'application/json',
         dialogTitle: '保存备份',
       )),
       _web = web ?? kIsWeb;

  @override
  Future<PickedBackup?> pick() async {
    try {
      final file = await _choose();
      if (file == null) return null;
      final length = file.lengthSync() ?? await file.length();
      return await readBoundedBackup(
        file.name, file.readAsByteStream(), reportedLength: length,
      );
    } on BackupValidationException {
      rethrow;
    } catch (_) {
      throw const BackupValidationException('无法读取所选文件，请检查文件是否可访问');
    }
  }

  @override
  Future<BackupSaveResult> save(String name, List<int> bytes) async {
    if (bytes.length > maxBackupBytes) {
      throw const BackupValidationException('备份超过 20 MiB，未保存文件');
    }
    try {
      final uri = await _write(name, Uint8List.fromList(bytes));
      if (_web) return BackupSaveResult.downloadRequested;
      return uri == null ? BackupSaveResult.canceled : BackupSaveResult.saved;
    } catch (_) {
      throw const BackupValidationException('无法保存备份，请检查目标位置后重试');
    }
  }
}
```

不依赖 `PlatformFile.path`，不把 Android content URI 或 Web 路径当成本机文件路径。选择器使用 any，让被文件管理器标成 text/plain 的备份也能选择；真正的格式限制由协议校验决定。

### 4.3 测试作业单

在 `test/data/backup_file_store_test.dart` 写以下用例，先运行确认缺失实现，再落文件层代码：

| 输入 / 操作 | 验收断言 |
|---|---|
| choose 返回 null | pick 返回 null，无读取、无错误 |
| reportedLength = 20 MiB + 1 | 不监听流，直接拒绝 |
| reportedLength 为 null，前后两块累计越限 | 越限处停止，不继续消费后续块 |
| 流恰好 20 MiB | 接受；不出现 off-by-one |
| 已知长度为 0 | 正常读完；后续 JSON 层报告空文件，不把它当取消 |
| 读取中抛异常 | 中文读文件错误，controller busy 可恢复 |
| write 返回 Uri、web=false | saved |
| write 返回 null、web=false | canceled |
| write 返回 null、web=true | downloadRequested，不能当 canceled |
| write 抛异常 | 中文保存错误，无「导出成功」提示 |

通过命令：`flutter test --no-pub test/data/backup_file_store_test.dart --reporter expanded`。

## Task 5 细化：controller 状态、接口与测试

在 `lib/state/backup_controller.dart` 使用下列固定命名，后续页面与测试保持一致：

BackupController 继承 ChangeNotifier；构造参数为 `required SqlExecutor exec`、`required BackupFileStore files`、`required Future<void> Function() onRestored` 和可选 `int Function()? now`（默认当前毫秒时间戳）。公开接口如下：

```dart
enum BackupRestoreResult { restored, refreshFailed, notRestored }

abstract interface class BackupActions {
  bool get busy;
  bool get restoring;
  int get revision;
  BackupPreview? get preview;
  String? get fileName;
  String? get message;
  Future<BackupSaveResult?> exportBackupFile();
  Future<bool> selectBackupFile();
  Future<BackupRestoreResult> confirmRestore();
  void cancelPreview();
}
```

这里的 BackupActions 是接口约定；若没有第二个实现，不必额外创建该抽象类型，直接在 BackupController 提供同样的签名即可。

状态字段由 controller 内部修改，页面不能直接替换 preview。恢复按钮只消费当前 preview；文件重新选择时清除旧 preview，防止 A 文件预览之后选 B 却恢复 A。

| 操作 | 步骤 | 最终状态 |
|---|---|---|
| exportBackupFile | guard busy → 固定 now → exportBackup → encodeBackup → save | canceled 静默；saved 报已保存；downloadRequested 报已请求下载；finally 清 busy |
| selectBackupFile | guard busy → 清旧预览 / 消息 → pick → decodeBackup → inspectBackup | null 静默；成功保存 fileName 与 preview；finally 清 busy |
| cancelPreview | restoring 时忽略；其他状态清 preview / fileName | 回到 idle，不写库 |
| confirmRestore | guard busy / preview → 标记 restoring → restoreBackup | 事务失败不刷新，提示数据未改动并清旧预览 |
| 事务成功 | 清 preview，revision 增加一次 → await onRestored | restored；正确场数提示 |
| onRestored 失败 | 事务已经提交，禁止再说已回滚 | refreshFailed；显示「数据已恢复，界面刷新失败，请重新打开应用」 |

文件名实现放在 `backup_codec.dart` 或文件层同一处：`gym-backup-YYYY-MM-DD-HHmmss.json`，使用传给 exportBackup 的同一个 now，按本地时区格式化。测试用固定本地 DateTime，不依赖测试当天时间。

必须使用 Completer 控制时序，验证两次并发点击只进入一次文件选择 / 保存 / 恢复；不要只在同步函数里检查 busy。测试清单：

1. 导出内容中 exportedAt 与文件名对应同一个固定时刻。
2. Web downloadRequested 产生正确文案，原生取消保持无消息。
3. pick / save / decode / inspect / restore 任一步失败，busy 和 restoring 均被 finally 清掉。
4. select 成功后再次选择并取消，旧 preview 消失。
5. 未选择文件时 confirmRestore 不调用写库。
6. confirm 事务失败，数据库保持旧值，onRestored 调用数为 0。
7. confirm 成功，onRestored 调用一次，revision 只增加一次，preview 清空。
8. onRestored 抛错，数据库已为新值、结果为 refreshFailed，不能声称「原数据未变」。
9. 预览后本机数据变化，restore 拒绝，要求重新预览。

通过命令：`flutter test --no-pub test/state/backup_controller_test.dart test/state/active_session_controller_test.dart --reporter expanded`。

## Task 6 细化：界面与刷新接入

### 6.1 文件与职责

- `backup_section.dart`：导出 / 恢复按钮、操作进度、预览入口与结果提示。
- 若对话框状态使文件过大，另建 `backup_preview_dialog.dart`，只负责预览和确认，使用传入的 controller，不访问数据库。
- `settings_page.dart`：在外观卡片下加入备份区，沿用已有间距和颜色，不改主题控件。
- `providers.dart`：创建 PlatformBackupFileStore 和 BackupController，注入同一个 SqlExecutor；提交后回调按下列顺序执行。
- `app_shell.dart`：订阅 controller.revision，以 `ValueKey((location, revision))` 更新 body 页面子树，router 实例保持一次创建。

提交后刷新顺序：

```dart
session.reset();
await session.resume();
await theme.load();
router.go('/');
```

revision 触发的是页面内容重建，不是 MaterialApp 重建。根 Navigator 上的对话框必须能正常关闭；消息通过仍有效的 ScaffoldMessenger 显示，不能在已销毁的设置页 context 上调用。

### 6.2 预览内容与确认规则

预览必须显示：文件名、导出时间、格式版本、训练总场数 / 已完成场数、动作 / 组 / 计划数量、本机将被替换的总场数。已有活动训练与空备份的额外提示按规格原文显示。

「取消」只是关预览；「替换并恢复」才调 confirmRestore。写入期间 PopScope 禁止返回，取消 / 确认按钮禁用，弹窗外不可关闭；写入前返回等同取消。成功或 refreshFailed 后关闭弹窗，失败后允许用户重新选文件。

### 6.3 界面测试矩阵

| 检查 | 必须证明的行为 |
|---|---|
| 点击真实导出按钮 | 文件 store.save 收到可解析 JSON，不是测试直接调用 controller |
| 点击真实恢复按钮 | 显示源与本机计数，未确认前数据库完全没变 |
| 取消 / 系统返回 | 不执行 restore，旧活动训练与主题不变 |
| 旧 v2 含计划 | 预览显示计划数量，不能隐藏 / 丢弃 |
| 空备份 | 确认前明确告知将清空训练 |
| 写库中连点 / 返回 | 只有一个恢复事务，busy 不被提前清掉 |
| 恢复为无活动训练 | 原旧 session / exercises 清空，首页无继续卡片 |
| 恢复为有活动训练 | 正确继续入口，组数和数值正确 |
| 偏好变化 | 新主题立即生效 |
| 历史 / 进步已打开过 | 恢复后再次进入显示新库记录，无缓存残留 |
| 320×480 / 横屏 / 大字号 | 所有提示可滚动、确认按钮可到达，无溢出 |

原主题测试仅装配主题 provider，备份区应允许缺少可选 BackupController 的独立测试上下文，不能因此让原页面崩溃。

通过命令：

```powershell
flutter test --no-pub test/widget/backup_section_test.dart test/app/router_test.dart test/widget/viewport_test.dart --reporter expanded
flutter analyze --no-pub
flutter test --no-pub --reporter expanded
```

## Task 7 细化：真实平台验收作业单

### 7.1 基础回归与构建

- [x] 现有分层规则、训练旅程与旧 225 条测试仍全绿；最终全量 304 条。
- [x] `flutter build web --no-pub` 成功。
- [x] 默认 Android debug / release 编译成功，实际包名核对为 `com.mobis.gym_tracker`。

所有日志存入新目录 `build/acceptance/phase3a-<执行时间>/`，不覆盖上一期浏览器、Android 与 tests.txt 证据。

### 7.2 Chrome 文件往返

新建 `scripts/browser_backup_smoke.mjs`，复用现有驱动中的 HTTP / CDP / 截图思路，不加入数据库后门：

1. 从实际 UI 创建一场训练，完成组并结束；留下一条可核算的容量，例如 20 × 8 = 160。
2. 用 `Browser.setDownloadBehavior` 配置隔离下载目录与事件，点导出，等 downloadProgress=completed 后读取真正下载的文件；不能从函数返回值伪造文件。
3. JSON 中 format/version/schema、原次数、容量输入值正确。记录导出前 data 作为逐字段基准。
4. 开启第二个干净 profile / origin，先截图证明空历史，再从设置页选择下载文件。通过 Page.fileChooserOpened 的 backendNodeId 调用 DOM.setFileInputFiles，走真实上传入口。
5. 先取消一次确认，证明旧库仍为空；再选择、确认恢复。
6. 核对历史、详情、进步、主题与活动训练；刷新页面后再次导出，比较 data，忽略 exportedAt。
7. 分别上传坏 JSON、错误协议和孤儿引用 fixture；断言中文错误、无 runtime exception，导出 data 与失败前一致。
8. 保存 screenshots、语义树、下载文件和 results.json；只有实际运行通过才勾选。

除下载 / 上传事件外，主流程必须真的点击按钮，不能直接调用页面内部方法。

### 7.3 Android 独立包

开始前核对 `adb devices -l`；若已断开，等待连接期间先完成其他本地项，不把连接缺失记为通过。ADB 的 WinUSB / LIBUSB 环境说明见环境笔记。

```powershell
. .\scripts\env.ps1
$env:GYM_ACCEPTANCE_BUILD = '1'
flutter build apk --debug --no-pub
Copy-Item -LiteralPath build\app\outputs\flutter-apk\app-debug.apk -Destination build\acceptance\app-phase3a-acceptance-debug.apk
adb install --user 0 -r build\acceptance\app-phase3a-acceptance-debug.apk
$env:GYM_ACCEPTANCE_PACKAGE = 'com.mobis.gym_tracker.acceptance'
node scripts/android_acceptance.mjs start
```

先更新驱动的新库断言：应用表为 `app_meta, app_setting, exercise, session, session_exercise, set_entry, split_template, template_exercise`；schema 4，首次 52 个动作，0 场训练。排除 Android 自动建的 android_metadata。旧 schema 3 验收报告保留原样。

fixture 放到手机公共 Download，只使用独立包的系统文件选择器导入：

```powershell
adb push test\fixtures\backup\legacy-v1.json /sdcard/Download/gym-acceptance-legacy-v1.json
adb push test\fixtures\backup\legacy-v2.json /sdcard/Download/gym-acceptance-legacy-v2.json
adb push test\fixtures\backup\current-v2.json /sdcard/Download/gym-acceptance-current-v2.json
```

坏文件也各准备一个真实 fixture。给用户手机主应用不执行 pm clear、不导入测试文件、不替换数据库。

| 编号 | 手机实际操作 | 通过标准 |
|---|---|---|
| A1 | 新独立包启动 / 选动作 | v4 / 8 表 / 52 动作正常 |
| A2 | 通过 UI 恢复 legacy-v2 | 非空计划、归档动作、活动训练和占位组保留 |
| A3 | 导出到系统文件位置 | 文件非空，真实可读，data 与 DB 逐字段一致 |
| A4 | 只清独立包数据后恢复导出文件 | 预览与确认正常，记录完整找回 |
| A5 | 结束 / 重启 / 继续训练 | 数据持久化，原始值与继续组位置正确 |
| A6 | 恢复 current-v2 空数据 / 深色偏好 | 空训练库不再播种，主题保留，重启仍一致 |
| A7 | 恢复 legacy-v1 | 缺计划字段正常兼容，偏好遵守保留规则 |
| A8 | 坏 JSON / 错协议 / 孤儿引用各一次 | 每次恢复失败后导出 data 与失败前一致 |
| A9 | 取消选文件、取消保存、取消确认 | 均不写库，按钮恢复可点 |

逐字段比对只读取独立 debug 包的数据库，可用 run-as 复制 db / wal / shm，再用 Node 24 的 sqlite 检查。操作前先静止写入，禁止把主应用升级为 debuggable 来取数。

清理与默认产物恢复：

```powershell
adb uninstall --user 0 com.mobis.gym_tracker.acceptance
Remove-Item Env:GYM_ACCEPTANCE_BUILD, Env:GYM_ACCEPTANCE_PACKAGE
flutter build apk --debug --no-pub
flutter build apk --release --no-pub
Get-FileHash -Algorithm SHA256 build\app\outputs\flutter-apk\app-release.apk
```

明确允许清理的只有本次创建的独立验收包；主应用保留原数据。默认产物构建后用 aapt dump badging 检查包名，防止把 `.acceptance` APK 当交付包。

## Task 8 细化：变异、审查、提交与完成定义

### 8.1 变异验证矩阵

每次只改一处，临时备份文件原文，在 finally 中恢复；当前大量源码未提交，**不能用 git restore / checkout 来恢复变异**。记录测试名称、Expected / Actual 或原始错误；恢复后重跑对应测试。

| 变异 | 必须失败的检查 |
|---|---|
| 恢复不经 transaction，直接执行删除 / 插入 | 三处故障注入中的至少一条逐表比较失败 |
| 不检查 set 的 sessionExerciseId 引用 | orphan set 校验测试失败；禁止依赖写库时才触发外键 |
| 不检查 session.templateId | 旧计划引用错误测试失败 |
| 实体导出改为 id 排序 | 同毫秒 / 逆字典序固定 fixture 的顺序断言失败 |
| 删除本机预览快照比较 | 同场数备注变化后恢复应拒绝的测试失败 |
| Web null 也当取消 | 文件层 + controller 下载结果测试失败 |
| 取消选文件仍保留旧 preview | 选择 A 后取消 B 的测试失败 |

### 8.2 代码与提交审查

1. 新增源文件没有超出已确认范围；计划表只存取，不引入轮转或管理 UI。
2. v1–v3 迁移内容未被改写；schema 上限、驱动和新测试均与 v4 一致。
3. domain 无 Flutter / IO；SQL 不进入 state / features / ui。
4. 文件界面没有存储路径假设、管理全部文件权限或生产验收后门。
5. 事务外不预先删除记录；提交后刷新失败不谎称回滚。
6. 测试、格式、构建、真实平台验收的证据分别记录，不相互替代。
7. 使用明确文件清单提交：先核心 + 测试，再文件与 controller，再界面，再验收文档。上一期未提交成果单独整理，用户文件始终排除。
8. 最后运行 `git diff --check` 与相关回归，写清 release APK 大小、哈希与包名。

### 8.3 本期完成表

| 条件 | 当前 |
|---|---|
| 协议与仓储核心可测 | 已完成 |
| 核心边界与变异检查补齐 | 完成，8 项变异实际检出 |
| Android 保存真实文件并能恢复到空独立库 | 待设备连接；A1–A9 未执行 |
| v1 / v2 含计划和偏好按规则完整恢复 | FFI 与真实 Web 完成，Android 待验 |
| 坏文件不写，写入中途失败全回滚 | FFI 故障回滚与 Web 文件入口完成，Android 待验 |
| 同毫秒、活动训练、占位组、休息值保持 | FFI 与 Web 完成，含非空休息值 |
| 恢复无需重启、取消与失败后可继续使用 | 界面测试与 Web 实测通过 |
| 格式 / 静态 / 全量测试 | 全部通过，304 条测试 |
| Web 下载上传真实往返 | 6 项通过，errors 为空 |
| 默认 release APK 与最终报告 | 已产出，见 2026-10-16 执行结果 |

## 后续路线：Phase 3B 与 Phase 4

这部分记录顺序和已知要求，不与 3A 混成一份无法独立验收的实现任务。恢复实施后先完成 3A；下一段再形成独立规格 / 计划。

### Phase 3B：CSV 与手动补记

- 解析器仅依赖 Dart，Strong / Hevy / 训记按旧总纲已有列名映射；不凭模糊字段猜来源。
- 处理 BOM、CRLF、引号与逗号、空行和重复表头；日期越界拒绝，时区和只有日期时的中午规则写入规格。
- 公斤 / 磅 / 自重规则明确，保留磅换算行数；失败信息带真实文件行号。
- CSV 与手动补记输出同一种中间训练结构，共用一个 import_repo 整批事务。
- 动作匹配带批内缓存，避免同一动作导成多份；新动作数量预览可见。
- 必须经过预览：场数、日期范围、动作、新建动作、单位换算、坏行原因；全坏文件不给确认按钮。
- 导入组 `is_completed=1`、`completed_at=finishedAt`；休息数据保持 null，不伪造。
- 空训练与无有效组训练在 CSV / 补记写入前拒绝；不改变备份可含空训练的契约。
- 导入后从真实历史、进步与下一次预填验证；重复导入策略在独立设计中明确后再实现。

### Phase 4：计划、轮转与记录删除

- 复用已经提前创建的两张计划表；后续确需结构变动只追加新迁移，不改 v4。
- 计划管理与轮转、删除记录各自拆可验收任务；先处理已有导入计划，不能清掉重建。
- 轮转依据最近已完成且关联计划的训练推导，不另存容易失真的轮转游标。
- 删除计划时处理 session.template_id 的引用；删除记录的确认、事务、空态与历史 / 进步刷新一起验证。
- 备份必须跟随这些变动保持旧文件可读和完整往返；不得把此前导出的文件作废。
