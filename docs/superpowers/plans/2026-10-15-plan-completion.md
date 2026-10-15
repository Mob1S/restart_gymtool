# Phase 1–2 验收收尾 Implementation Plan

> **For agentic workers:** 按以下复选项在当前会话逐项执行；以已有 Phase 1、Phase 2 规格为准。

**Goal:** 核实既有计划的实际完成度，补齐浏览器走查、构建和可获得的真机证据。

**Architecture:** 保留 Flutter 应用与 schema v3，复用真实 SQLite 后端。浏览器走查使用 Node 内置 HTTP / WebSocket 与 Chrome DevTools Protocol，直接操作发布构建，证据存入 `build/acceptance/`。

**Tech Stack:** Flutter 3.47.6、Dart 3.13.5、Node.js 24、Chrome、Android ADB。

**结果（2026-10-15）**：Phase 1、Phase 2 完成定义均为 **8/8**。缺失项主要是实际操作验收；本次已补齐，并修正了一条无法检出排序变异的测试。未发现需要修改产品业务逻辑的问题。

## Global Constraints

- 不引入 Phase 3 备份、导入或 Phase 4 计划管理；这两期还没有获批的详细规格和实施计划。
- 不改动已发布迁移，不修改指标公式，不把浏览器结果记成真机结果。
- 保留用户已有的 `.claude/settings.local.json` 和 `.tmp/` 改动。
- 真机只在设备连接并获授权后执行；不清空已有训练数据库。

## Task 1：检查代码与基线

- [x] 对照 Phase 1 / Phase 2 规格、实施计划、仓储、路由和页面测试。
- [x] 用 `flutter pub get --offline --enforce-lockfile` 恢复工作区依赖路径。
- [x] 执行 `flutter analyze` 和 `flutter test --reporter expanded`：静态检查无问题，225 条测试全部通过（含分层、数据、状态、界面、端到端与极端视口）。

## Task 2：完成浏览器走查

**Create:** `scripts/browser_smoke.mjs`（无第三方 Node 依赖）。
**Output:** `build/acceptance/browser-*/`（截图、语义树与结果）。

- [x] `flutter build web --no-pub`，使用正式入口 `lib/main.dart`：构建成功。
- [x] `node scripts/browser_smoke.mjs`，在隔离 Chrome profile 里从空库开始，点击开训练、选动作、完成组、结束、查看总结。
- [x] 从历史列表点进详情再返回；从进步列表点进动作详情并横滑三张卡，核对真实操作产生的组数、容量、e1RM 及口径文案。
- [x] 刷新后复验持久化，并打开不存在的动作深链核对空态。
- [x] 本次浏览器走查未发现需要修改产品代码的问题；脚本已修正刷新后的页面定位。

## Task 3：Android 交付与验收

- [x] `flutter build apk --release --no-pub`：构建成功，67,645,108 字节；SHA-256 `A4E0A326C9A698AF4A03503B27A0A580549A329AD32F3726DCAFE7132225D709`。
- [x] 荣耀 Magic6 Pro 已连接并授权；保留数据安装当前 APK，实际启动并读取前台页面。
- [x] 按 Phase 1 Task 22 与 Phase 2 Task 16 逐项执行并记录；震动以设备系统的实际完成记录取证，不评价主观强弱。
- [x] 独立验收包验证首次建库、预置动作与主题，结束后只卸载临时包，返回主应用。

## Task 3a：补齐排序测试守卫

**Modify:** `test/data/progress_repo_test.dart`，原用例 4。

- [x] 原用例中训练和组的插入顺序相同，删掉 `s.rowid ASC` 仍然通过，未能证明兜底排序。
- [x] 改为先建训练 A / B，再按 B / A 的顺序写组，并将两场 `started_at` 设为同毫秒；正常结果应为 `[20, 30]`。
- [x] 暂时删除 `s.rowid ASC` 后实际失败：`Expected: [20, 30]`、`Actual: [30.0, 20.0]`。已恢复产品 SQL。
- [x] 恢复后 5 条仓储测试通过；`dart format` 无改动，`flutter analyze` 无问题，全量 225 条通过。最终日志：`build/acceptance/analyze.txt`、`build/acceptance/tests.txt`。

## Task 4：回填计划与入口文档

**Modify:** `README.md`、两期计划的当前验收记录、本文件。

- [x] 记录 2026-10-15 实测结果和证据路径，保留 2026-10-09 的历史记录。
- [x] README 写明项目用途、当前范围、运行和验证方法、计划入口。
- [x] `git diff --check` 通过，两份 Node 驱动语法检查通过；最终差异已检查，没有遗留的设备验收阻塞。

## 2026-10-15 实测证据

浏览器完整运行：`build/acceptance/browser-2026-10-15T13-32-09-686Z/results.json`，7 项全部通过，`errors: []`。

| 走查项 | 实测 |
|---|---|
| 空历史 / 空进步 | 两处正确空态，截图 01 / 02 |
| 真实记录一组 | `20 kg × 8`，结束后总结容量 160，截图 03–05 |
| 历史点进与返回 | 行显示 `1 组 · 160 kg`，详情显示相同容量，返回成功，截图 06 / 07 |
| 三张卡与单次训练 | 最大重量、e1RM 25、容量 160；一个点与稀疏文案，截图 08–10 |
| 刷新后持久化 | 重新进入进步页仍为 `20 kg × 8`，截图 11 |
| 规格给定数字 | 实际操作四组 `50 kg × 8`；总结、历史、容量卡均为 1600，e1RM 卡显示 62 与来源组，截图 12–16 |
| 不存在动作的深链 | 正确空态，无运行时异常，截图 17 |

脚本首轮发现的是驱动假设错误：刷新后应用回到首页，不能假定仍在进步页；已改为刷新后再点击进步页验证持久化。此处没有改动产品路由。

真机连接：Windows 识别荣耀 Magic6 Pro，默认 `LIBADBUSB` 看不到通用 WinUSB 接口；仅为 ADB 服务进程设置 `ADB_LIBUSB=1` 后枚举成功，用户已在手机端授权。首次安装返回 `INSTALL_FAILED_ABORTED: User rejected permissions`，按用户要求重试后成功；未清空数据。用户已明确允许结束手机上原有的 0 组训练，再新建验收训练。

### Android 真机

设备：荣耀 Magic6 Pro（BVL-AN16），Android 16；1280 × 2800，density 560。主应用使用上文的 release APK；从零建库和主题检查使用同一份 Dart 代码构建的独立 debug 包 `com.mobis.gym_tracker.acceptance`。

证据目录：`build/acceptance/android-2026-10-15/`。每张截图有同名 `.xml` / `.json` 语义树；`actions.jsonl` 记录实际成功执行的动作。下列编号对应文件名前缀。

| 项目 | 结果 | 证据 |
|---|---|---|
| 保留数据更新 | 旧历史仍有 3 组、容量 1050；原空训练经用户允许结束，仍保留历史 | 01 / 02 |
| 两次点击与数值预填 | 完成组 1 次，开始下组 1 次；50 kg × 8 在第 4 组正确预填 | 07 / 08 / 18 |
| 拖动 / 步进器 | 20 → 拖到 52.5 → 减到 50，实际输入有效 | 12 / 13 |
| 常亮 | 关闭 USB 强制常亮，系统超时 30 秒；无输入 35.485 秒后屏幕仍 Awake，窗口 KEEP_SCREEN_ON 生效 | `keep-awake.json` |
| 震动 | 本应用的 CLICK 效果实际 finished，持续 68–86ms；仅证明硬件反馈执行，不作手感评价 | `haptic-feedback.txt` |
| 休息正计时 / 换动作 | 休息向上数；动作条切换、添加弹层均在记录流程内完成 | 05–08 / 14 |
| 熄屏计时 | 01:06 → 01:46，实际经过 39.911 秒，读数增加 40 秒；系统确认进入睡眠 | `sleep-timer.json` |
| 强杀恢复 | 完成 3 组后强杀，首页显示已记 3 组，继续后第 4 组及重量次数正确 | 15–18 |
| 总结口径 | 一组 `20 × 8 = 160` 且组数不足暂不判断；四组 `50 × 8 = 1600`，原始次数 `8 / 8 / 8 / 8` 与粗略提示正确 | 09 / 19 |
| 结束与重启 | 完成返回首页和重启后均无继续训练卡片 | 20 / 26 |
| 历史行与详情 | 一组实际时长 3 分 06 秒、容量 160；四组行与点进详情均 1600，返回正确 | 10 / 21 / 22 |
| 单次进步 | 一个点、稀疏文案；e1RM 卡来源组可追溯 | 11 |
| e1RM 与容量卡 | `50 × 8` 显示 62、「估算 · 仅供参考」及来源组；容量卡 1600，标「最高」 | 23 / 24 |
| 未练动作深链 | 冷启动不存在动作显示「这个动作还没有记录」 | 25 |
| 首次建库 | schema v3，6 张应用表，52 个动作，0 场训练；排除 Android 自动生成的 `android_metadata` | 27、`fresh-database.json` |
| 空列表与动作排序 | 空历史 / 空进步正确；胸在首位，俯卧撑 → 器械推胸 → 上斜卧推 → 绳索夹胸 | 28 / 29 / 35 |
| 主题与持久化 | 浅色暖白、深色近黑；强杀后深色保留，跟随系统与当前系统深色一致 | 30–33 |
| 清理临时包 | `adb uninstall --user 0 com.mobis.gym_tracker.acceptance` 成功，主应用保持正常首页 | 36 |

主应用留下两场验收训练（一组容量 160、四组容量 1600）。没有清空或删除原训练数据。截图 03 的名称来自早期操作定位，内容实际是旧历史详情，不用它证明新建训练。

截图驱动增加了前台应用语义检查，避免锁屏时拿到过期画面。一次锁屏后的无效截图已重新唤醒并重拍。首次建库驱动最初误将 Android 的系统表算作应用表，已修正过滤并重跑通过；均未修改产品逻辑。

### 交付与范围

- 主应用：`build/app/outputs/flutter-apk/app-release.apk`（与 `build/acceptance/app-release-verified.apk` 同哈希）。
- 临时验收产物另存 `build/acceptance/app-fresh-install-debug.apk` 与 `app-fresh-install-release.apk`，不作为主应用交付包。
- 新增 `scripts/browser_smoke.mjs`、`scripts/android_acceptance.mjs`，可复用本次验证方法。
- `android/app/build.gradle.kts` 仅在 `GYM_ACCEPTANCE_BUILD=1` 时追加 `.acceptance` 后缀；默认包名保持 `com.mobis.gym_tracker`。
- 验收后已重建默认 debug APK，并用 `aapt dump badging` 确认包名为 `com.mobis.gym_tracker`；release APK 的字节数与 SHA-256 再次核对一致。
- Phase 3、Phase 4 仍是后续范围，不能把前两期完成写成整个产品路线图全部完成。

本地证据位于忽略的 `build/` 下；重新清理构建目录前如需长期归档，应一并保存 `build/acceptance/`。
