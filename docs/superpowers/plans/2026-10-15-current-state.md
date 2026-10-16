# 项目现状与接续说明

> **2026-10-16 用户最新开发约定（优先于下文旧验收要求）**：不再单独构建验收包，之后直接生成 `com.mobis.gym_tracker` 主包并覆盖更新，在主包中新增 / 补记 / 删除开发测试记录。通过软件界面清理测试记录，不把“可测试”推断成自动清空整个动作库。用户反馈的「推日 / 我的推胸」来自此前独立包中的兼容性样例；当前按计划开训链路与原动作库完整性重新复核。

> **本轮复核已完成**：52 动作库在计划新建 / 编辑 / 开训 / 删除后逐字段不变；旧样例能载入动作并记组。已补动作库完整替换提示，337 条测试和 14 项真实浏览器检查通过，Web / Android 主包构建成功。ADB 无设备，手机尚未覆盖。当前 APK 哈希与证据见 [复核记录](./2026-10-16-plan-start-and-test-isolation.md)。

> **2026-10-16 最新接续**：用户已要求「开始实现」。Phase 3B 与 Phase 4 的功能已接入，自动化和真实浏览器检查通过，Android debug / release 构建成功；真机矩阵仍待连接设备。最新结果、安装包与未完成验收项见 [Phase 3B / Phase 4 执行记录](./2026-10-16-phase3b-phase4-execution.md)。下方 Phase 3A 及更早记录保留为历史，不能继续当作当前待开发清单。

> **图标更新**：用户随后要求更换图标并复验，最终选择原哑铃轮廓、中央直杆、去掉对勾。最新 APK 和验证证据见 [图标与复验记录](./2026-10-16-icon-and-retest.md)；功能实现与真机待验范围沿用上方执行记录。

> **真机接续**：已连接荣耀 Magic6 Pro 并完成独立包启动、v4 新库、真实导出、旧 v2 逐字段恢复、取消预览、旧计划与归档标记检查。之后 ADB 断开，用户暂不方便重新开启调试；完整验收未完成。先看 [真机记录与断点](./2026-10-16-android-device-acceptance.md)，设备恢复后从中断步骤继续，勿清主包。默认 debug 已重新构建为主包；release 未改变。

## 2026-10-16 Phase 3A 历史执行结果

用户已要求读取计划并完成工作，本轮已恢复实施。下面旧记录中的「只整理、不继续实现」不再是当前指令。

- **Phase 3A 功能已接通**：设置页提供导出、选择备份、计数预览、整库替换确认；Android / Web 文件接口、有限流式读取、取消、重复提交保护、恢复后刷新均已实现。
- **核心补查完成**：总记录数改为处理任何记录前预检全部数组；新增嵌套事务、播种失败、标记缺失回滚、文件库重开、同位置排序等边界测试。7 个旧文件的格式问题已修正。
- **验证**：格式通过、静态检查无问题、完整 **304 条测试通过**；8 个故意破坏检查均实际失败，产品代码随后还原。Web 发布构建通过。
- **真实浏览器**：备份验收 6/6、原训练流程 7/7，均无运行时错误。真实下载 → 独立 origin 空库上传 → 取消 / 确认 → 刷新重导出逐字段一致；旧 v1 / v2、计划、归档动作、活动训练、占位组、非空休息值、空备份和坏文件均验证。
- **Android**：独立 debug、默认 debug / release 均构建成功且包名核对通过。release 为 68,132,333 字节，SHA-256 `68A779D5D1E1740DE8946E0110DDB44BFFACFC6649136021F186067B045124D4`。ADB 在默认与 LIBUSB 配置下均无设备，尚未安装或操作本轮任何包；手机主应用与训练数据未改动。真机文件往返仍待设备连接。
- **范围**：CSV / 手动补记（Phase 3B）和计划界面（Phase 4）未实施。
- **Git**：沿用 `master`，按明确清单分别提交旧验收成果、备份核心、文件 / controller、界面和验收文档；`.claude/settings.local.json` 与 `.tmp/` 未修改、未纳入提交。未推送远程。

本轮检查日志：`build/acceptance/phase3a-2026-10-16/`。最终备份浏览器证据：`build/acceptance/browser-backup-2026-10-15T18-33-10-005Z/`；训练回归：`build/acceptance/browser-2026-10-15T18-30-41-759Z/`。目录名中的时间为 UTC，实际本地执行日期为 2026-10-16。

下一步只需按实施计划 §7.3 在连接并授权的设备上完成 `.acceptance` 包的 A1–A9；不要重新实现文件层或清空主应用。完整结果见 [本轮执行记录](./2026-10-16-phase3a-execution.md)。

## 2026-10-15 历史交接（以下为当时状态）

**整理日期：2026-10-15（Asia/Shanghai）。**

**当前指令：用户要求「把现在的情况整理一下然后写一份详细的计划就行了」。功能实现已停在下面记录的位置；本次仅整理文档和检查现有源码，不继续接界面、构建新版或操作手机。**

详细接续步骤见 [Phase 3A 实施计划](./2026-10-15-phase3a-backup-and-restore.md)；产品契约见[已确认的 Phase 3A 设计](../specs/2026-10-15-flutter-gym-tracker-phase3a-design.md)。

## 1. 一句话结论

Phase 1、Phase 2 已验收完成；Phase 3A 的数据库与备份协议核心已实现并通过测试，尚未形成可供用户操作的备份功能。下一次应先补测试与格式，再从文件接口继续，不要重写已经通过的核心。

## 2. 各阶段状态

| 阶段 | 当前情况 | 证据 / 下一步 |
|---|---|---|
| Phase 1：记录训练 | 完成定义 8/8，含真机强杀、熄屏、常亮、首次建库 | [收尾记录](./2026-10-15-plan-completion.md) |
| Phase 2：历史与进步 | 完成定义 8/8，含浏览器实际操作、真机数值与深链 | 同上；当时完整基线 225 条测试 |
| Phase 3A：JSON 备份恢复 | 核心已实现；文件适配 / controller / UI / 文件往返验收未实现 | 本文 §3–6 与详细实施计划 |
| Phase 3B：CSV 与补记 | 尚未开始，未形成独立规格 | 在 3A 真正交付后，接 Strong / Hevy / 训记和手动补记录 |
| Phase 4：计划管理、轮转与删除 | 尚未实现界面或业务；两张计划表已提前到 3A 核心代码 | 这是为保留旧 v2 备份里的计划，已经用户确认 |

不以「完成了 3 个任务」换算整个 Phase 3A 的百分比；文件、事务和真机验收的工作量并不相同。

## 3. 本次已经实现的内容

### 3.1 事务与 schema v4

- `SqlExecutor` 新增 `transaction<T>(Future<T> Function(SqlExecutor tx) action)`。
- Android `SqfliteExecutor` 和 FFI / Web `FfiExecutor` 均接到底层 transaction；`TransactionExecutor` 只适配事务对象，禁止嵌套事务。
- v1–v3 迁移语句未改；追加 v4 的 `split_template`、`template_exercise` 和索引，源码 `schemaVersion` 现为 **4**。
- 播种过程在事务内完成，成功后写 `app_meta.seed_initialized=1`。恢复合法空库后重启不再自动塞回 52 个动作。
- 真实 FFI 测试已验证事务失败回滚、原异常保留、v3 → v4 训练保留、播种标记与幂等性。

### 3.2 协议与编解码

- 固定 format 为 `gym-tracker-backup`；支持 v1 / v2；拒绝未来格式与不支持的来源 schema。
- 旧 v1 缺失的计划数组、templateId 按空 / null 兼容。
- 旧 v2 的非空计划、自定义与归档动作、活动训练、未完成占位组均保留。
- settings 扩展存在时恢复偏好，不存在时保留本机偏好。
- 数据经过字段、重复 ID / 设置键、引用、数值范围和至多一场活动训练校验；规范化后的嵌套集合不可变。
- UTF-8、BOM、JSON、20 MiB 文件上限及 100,000 条总记录限制已有实现。
- 三份固定 fixture 已落盘；协议测试 **22 条通过**。记录数极值等补充测试仍列为待办，不把「代码有检查」写成「每个边界已实测」。

### 3.3 仓储导出与恢复

- 一个事务读取一致的完整快照；各实体表按 `rowid ASC`，设置按 key 排序。
- 预览保存本机规范 JSON；写入事务起点重读比较，同样场数下的备注变化也能识别，要求重新预览。
- 按外键顺序删除 / 插入，条件替换 settings，写本机播种标记，执行外键检查。
- 逐字段往返保留计划和同毫秒训练顺序。
- 三个故障注入点（删除后、插入中、设置写入后）均验证业务表、偏好与元数据完整回滚，且保留原异常。
- 仓储测试 **6 条通过**；移除事务、引用检查等变异验证尚未执行。

### 3.4 文件依赖

已联网成功解析和下载，`pubspec.yaml` 固定 `file_picker: 13.1.0`，`pubspec.lock` 固定了 8 个新增包：

| 包 | 锁定版本 |
|---|---|
| file_picker | 13.1.0 |
| android_file_picker | 2.1.1 |
| file_picker_platform_interface | 4.2.0 |
| file_picker_web | 4.1.0 |
| file_picker_darwin | 2.3.2 |
| file_picker_linux | 2.0.2 |
| windows_file_picker | 2.0.1 |
| cross_file | 0.3.5+5 |

这仅表示依赖已准备好；当前没有 `lib/data/files/backup_file_store.dart`，也没有实际调用文件选择器。

## 4. 尚未实现或验证的内容

| 内容 | 状态 |
|---|---|
| 文件选择 / 有限流式读取 / 原生保存 / Web 下载适配 | 未实现 |
| BackupController、重复提交与取消、提交后刷新错误区分 | 未实现 |
| 设置页备份入口、预览、整库替换确认 | 未实现 |
| 恢复后清除旧活动训练内存、重读主题、刷新历史 / 进步 | 未接入 |
| 边界测试补充与计划要求的变异验证 | 待做 |
| 新增文件的统一格式化 | 7 个文件待格式化，见 §5 |
| Phase 3A Web / APK 发布构建 | 未做 |
| Phase 3A 浏览器实际下载 / 上传往返 | 未做 |
| Phase 3A Android 系统文件界面与坏文件验收 | 未做 |
| 本期代码审查、分组提交与交付报告 | 未做 |

## 5. 最新检查基线

整理时对当前源码（包含新增依赖）重新执行，未修改功能代码：

| 检查 | 结果 | 日志 |
|---|---|---|
| `flutter analyze --no-pub` | 通过，No issues found | `build/acceptance/phase3a-planning-analyze.txt` |
| `flutter test --no-pub --reporter expanded` | **257 条全部通过**（原 225 + 新增 32） | `build/acceptance/phase3a-planning-tests.txt` |
| `dart format --output=none --set-exit-if-changed lib test` | exit 1，7 个文件需要格式化；这是不写文件的检查 | `build/acceptance/phase3a-planning-format.txt` |

新增测试：`backup_foundation_test.dart` 4 条、`backup_test.dart` 22 条、`backup_repo_test.dart` 6 条。

待格式化的准确文件：

1. `lib/data/repositories/backup_repo.dart`
2. `lib/data/repositories/exercise_repo.dart`
3. `lib/domain/backup.dart`
4. `lib/domain/backup_codec.dart`
5. `test/data/backup_foundation_test.dart`
6. `test/data/backup_repo_test.dart`
7. `test/domain/backup_test.dart`

## 6. 接手时最需要注意的事实

### 6.1 Web 成功保存返回 null

已只读核对下载到缓存里的 `file_picker_web 4.1.0`：`saveFile` 创建 Blob、点击 download 链接、释放 URL，然后 **return null**。因此不能把 `uri == null` 在所有平台都解释为取消。

后续文件接口改用明确结果 `saved / downloadRequested / canceled`；Web 调用没有抛异常时只报告「已请求下载备份」，原生返回 null 才作为取消。详细计划已有具体实现代码与测试要求。

本机来源：`.tooling/pub-cache/hosted/pub.dev/file_picker_web-4.1.0/lib/src/file_picker_web.dart` 的 saveFile。

### 6.2 活动训练 resume 不会清掉旧内存

现有 `ActiveSessionController.resume()` 在没有活动训练时返回 false，保留原状态；这个行为有既有测试。恢复新数据库后必须先调用现有 `reset()`，再 `resume()`。不应修改所有 resume 调用的既有语义。

### 6.3 不重建 GoRouter

恢复刷新不应新建 router 或整棵 MaterialApp，以免丢失导航状态、关闭中的恢复弹窗或消息提示。沿用单例 router，刷新活动训练与主题，以 revision 更新 AppShell 下的页面子树。

### 6.4 旧验收脚本仍按 schema v3 断言

`scripts/android_acceptance.mjs` 的 fresh-database 仍期待 6 张应用表、schema 3。下一次用于新包之前应改为 8 张应用表、schema 4，并保持上一期历史证据不变。现有 release APK 对应旧基线，不能拿新脚本断言旧 APK。

### 6.5 迁移和 schema 号的边界

v4 目前已在源码中，不代表手机已升级。新包首次运行会迁移到 v4。旧 v3 迁移的 ALTER 与写版本号之间无事务，这是此前明确记录的历史限制，本次没有顺便修改它。

协议校验器当前支持来源 schema 最大值 4，迁移常量也是 4；后续增加 schema 时要同步复核协议接受范围，不能只改一个常量。

### 6.6 手机和 APK 状态

上次真机验收设备为荣耀 Magic6 Pro / Android 16；主应用保留原数据，新增了一组容量 160 与四组容量 1600 两场验收训练，原空训练经允许结束。临时包已卸载。

当前 `build/app/outputs/flutter-apk/app-release.apk` 仍是 **Phase 1–2 已验收包**，67,645,108 字节，SHA-256 `A4E0A326C9A698AF4A03503B27A0A580549A329AD32F3726DCAFE7132225D709`。Phase 3A 没有构建或安装到手机；本次整理也未重新检查设备连接状态。

## 7. Git 与文件保护

- 当前分支为 `master`。
- 最近提交 `a70e692`：只提交了 Phase 3A 规格和第一版实施计划。
- Phase 3A 核心源码、测试、fixture、依赖改动仍在工作区，未提交。
- Phase 1–2 收尾的 README、验收文档、驱动、排序测试与独立包配置也仍有未提交改动。
- `.claude/settings.local.json`、`.tmp/` 是此前就存在的用户改动，不属于本期交付；未改动它们。
- 不要 `git reset --hard a70e692`、不要 `git clean`、不要 `git add -A`；这些会丢掉或混入前述成果和用户文件。
- 本次整理之后规格 / 计划会相对 a70e692 有文档差异，属于当前状态交接内容。

## 8. 下一次的起点

1. 先读本文件与 Phase 3A 规格。
2. 按详细计划的 Task 0 保留工作区、修正格式并补有价值的核心边界测试。
3. 从 Task 4 文件层开始接功能，特别处理 Web 的 null 返回。
4. 然后完成 controller、设置入口、刷新、真实浏览器和独立 Android 包验收。
5. 全部完成后再进入 Phase 3B；没有后续实施指令时，保持当前仅整理计划的状态。
