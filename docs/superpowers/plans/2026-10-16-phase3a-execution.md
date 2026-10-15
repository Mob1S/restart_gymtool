# Phase 3A 接续执行结果

执行日期：2026-10-16（Asia/Shanghai）。

**功能、自动检查、Web 文件往返与 Android 构建已完成。Android 真机未连接，A1–A9 文件验收未执行；本期不能标为全部验收完成。**

## 已交付

- 设置页新增「数据备份」：导出、选文件、预览、取消与明确替换确认；显示本机与文件场数、计划数、活动训练和空备份提示。
- 文件层使用 file_picker 13.1.0，长度预检和分块累计限制 20 MiB；Web 的 null 返回正确解释为请求下载，原生 null 为取消。
- controller 阻止重复提交和失效预览，所有异常释放 busy；事务失败与提交后刷新失败分开报告。选择取消后不会复活上一份备份。
- 恢复后清除旧训练内存、重新载入活动训练及主题，通过 revision 刷新页面并回首页，GoRouter 保持同一实例。
- 核心校验修正为逐条解析前检查全部数组总数。补齐嵌套事务、播种失败、同位置排序、标记缺失回滚、真实文件库关闭重开等测试。
- 未改动已发布 v1–v3 迁移；v4 仅增加计划存储。未增加 CSV、手动补记或计划管理界面。

## 自动检查

证据根目录：`build/acceptance/phase3a-2026-10-16/`。

| 检查 | 实际结果 | 证据 |
|---|---|---|
| 格式 | 100 个 Dart 文件，0 个待格式化 | `format.txt` |
| 静态分析 | No issues found | `analyze.txt` |
| 全量测试 | **304 / 304**，含原 225 条及本期 79 条 | `tests.txt` |
| Web 发布构建 | 成功 | `build-web.txt` |
| 独立 Android debug | 成功，`.acceptance` 包 | `build-acceptance-debug.txt` |
| 默认 Android debug | 成功，主包名 | `build-debug.txt` |
| 默认 Android release | 成功，主包名 | `build-release.txt` |
| APK 包名、大小、哈希、权限 | 三份产物核对通过；不含管理全部文件权限 | `apks.json` |

本轮新增 47 条：协议边界 13、基础事务 / 播种 3、仓储边界 4、文件层 10、controller 9、界面 8。加上交接时 257 条共 304 条。

### 变异检查

`node scripts/backup_mutation_check.mjs` 逐项临时改写，finally 恢复原文件字节。8 项均出现断言失败（exit 1），不是编译或工具失败；恢复后全量测试通过。

| 故意破坏 | 真实检出结果 |
|---|---|
| 恢复跳过事务 | 注入错误后，逐表内容与恢复前不同 |
| 删除组引用检查 | 孤儿组未抛出预期校验异常 |
| 删除计划引用检查 | 不存在的 templateId 未抛出预期异常 |
| 删除实体 rowid 排序 | 预期 `[z, a, pending]`，实际 `[pending, a, z]` |
| 删除本机预览快照比较 | 同场数备注修改后的恢复未按预期拒绝 |
| 原生取消保存当成功 | 预期 canceled，实际 saved |
| Web null 当取消 | 预期 downloadRequested，实际 canceled |
| 选择新文件不清旧预览 | 预期 null，实际仍为 BackupPreview |

本轮逐项输出在 `mutations/*.txt`，汇总在 `mutations/results.json`。脚本已改为后续每次生成独立 `build/acceptance/backup-mutations-<UTC时间>/`，避免覆盖本轮证据。

## Chrome 发布构建实际操作

备份证据：`build/acceptance/browser-backup-2026-10-15T18-33-10-005Z/`，**6 / 6，通过且 errors 为空**。目录时间为 UTC，对应本地 2026-10-16。

1. 通过 UI 记录 `20 kg × 8`、结束、选择深色主题、导出；等待 Chrome 下载完成事件后读取真实 JSON。
2. 在另一隔离 origin 的空 SQLite / IndexedDB 中上传下载文件，预览取消一次，确认空库未变，再恢复。
3. 历史显示容量 160，详情与进步一致；刷新后再次导出，全部 data 字段及偏好与原下载文件相同。
4. 坏 JSON、错误协议、孤儿引用分别从上传入口拒绝；每次失败后重导出 data 均未变化。
5. 旧 v1 / v2 逐字段核对，保留计划、归档动作、活动训练、占位组，以及 `restSeconds=75`、`restStartedAt=1700000070000`；旧文件缺 settings 时保留本机深色。
6. 空备份显示清空警告和进行中训练提示；恢复后无继续卡片，刷新后动作库仍为空，不重新播种。

原训练回归：`build/acceptance/browser-2026-10-15T18-30-41-759Z/`，**7 / 7，通过且 errors 为空**，包括四组 `50 × 8` 的容量 1600、e1RM 62、历史详情、三卡滑动和不存在动作深链。

首轮备份驱动在恢复活动训练后仍等待「开始训练」，实际按钮是「开始新训练」，因此超时。已修正驱动等待条件并重跑；没有为此更改产品行为。最终一轮在补入非空休息值后再次通过。

## Android 产物与未完成项

交付：`build/app/outputs/flutter-apk/app-release.apk`。

- 包名：`com.mobis.gym_tracker`，versionName `1.0.0`，versionCode `1`。
- 大小：**68,132,333 字节**。
- SHA-256：`68A779D5D1E1740DE8946E0110DDB44BFFACFC6649136021F186067B045124D4`。
- 独立验收包：`build/acceptance/phase3a-2026-10-16/app-acceptance-debug.apk`，包名 `com.mobis.gym_tracker.acceptance`。
- 默认 debug 已重建为主包名，避免同名 APK 混淆。

ADB 在默认后端和重启为 LIBUSB 后均未列出设备；最后连接检查存于 `adb-devices.txt`。本轮没有安装、清库或卸载手机上的任何应用，没有更改主应用的训练记录。

**尚需完成**：[实施计划 §7.3](./2026-10-15-phase3a-backup-and-restore.md) 的 A1–A9：系统选择 / 保存 / 取消、独立空库恢复、坏文件、v1 / v2、重启与偏好检查。只对本轮独立包执行清库；通过后卸载独立包并补证据。Phase 1–2 的旧真机结果不能替代本期文件功能验收。

本地证据位于被 Git 忽略的 `build/`，清理前如需长期保留，应归档上述目录。

## 本地提交

沿用 master，未推送远程。提交均使用明确文件清单：

- `bac2a59`：上一期验收成果与排序测试。
- `4a70556`：schema v4、事务、协议、仓储与边界测试。
- `52185f4`：文件层、controller、依赖与测试。
- `eb3ced0`：设置入口、恢复刷新与真实装配界面测试。
- 最后单独提交验收驱动与本轮文档；用户 `.claude/settings.local.json` 和 `.tmp/` 未纳入。
