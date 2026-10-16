# 健身记录 · gym_tracker

Flutter 本地健身记录工具：按组记录重量和次数、正计时休息、恢复未结束的训练、查看训练历史与动作走势。数据写入设备 SQLite；Web 预览使用 SQLite wasm 和 IndexedDB，与手机数据隔离。

## 当前范围

- Phase 1：训练记录、动作选择、训练恢复、训练总结、主题三态。
- Phase 2：历史列表与详情、动作进步列表、最大重量 / 估算 1RM / 总容量三张走势卡。
- Phase 3A：JSON 备份恢复已接入设置页，支持旧 v1 / v2、预览确认、事务恢复与即时刷新；Web 真实文件往返通过，Android 真机文件验收待设备连接。
- Phase 3B：Strong / Hevy / 训记 CSV 预览追加、动作匹配、疑似重复提示、坏行确认，以及手动补记。
- Phase 4：训练计划清单与排序、自动轮转、临时选择计划、训练删除、动作移除与保留已记组。数据库仍为 v4，备份仍为 v2。

开发栈：Flutter 3.47.6 / Dart 3.13.5。2026-10-15：Phase 1、Phase 2 已完成；静态检查、225 条测试、7 项浏览器走查及荣耀 Magic6 Pro 真机验收均通过。结果与证据见[完成度复核](docs/superpowers/plans/2026-10-15-plan-completion.md)。

2026-10-16：Phase 3A 格式与静态检查通过、**304 条测试全绿**、8 项变异守卫通过；备份浏览器验收 6/6、原训练浏览器回归 7/7。Android debug / release 与独立验收包均构建成功，真机 A1–A9 尚未执行。完整证据与 APK 哈希见[本轮执行结果](docs/superpowers/plans/2026-10-16-phase3a-execution.md)；接续见[当前状态交接](docs/superpowers/plans/2026-10-15-current-state.md)和[详细实施计划](docs/superpowers/plans/2026-10-15-phase3a-backup-and-restore.md)。

## 训练操作效率

2026-10-16 新增六项训练现场操作，数据库升至 **v5**，导出备份升至 **v3**：

- 「本场已记 N 组」可修改当前训练已完成组的重量与实际次数，包含替换后保留的旧动作；已结束训练仍只读。
- 休息页「误点完成？撤销」可回到刚才那一组，清除下一组占位及准备重量。开始下一组、结束、替换或超过休息闸门后不能撤销。
- 休息时可调整并保存下一组重量，拖动松手后保存；开始前等待保存完成。次数在实际完成后确认，不在休息时设目标次数。
- 「动作设置」为每个动作保存 0.5 / 1 / 1.25 / 2.5 / 5 kg 调重幅度，默认 2.5 kg；加减基于原重量，21.3 + 2.5 = 23.8。
- 选择器支持收藏、最近实际练过的 10 个动作、全库搜索及批量勾选。「添加 N 个动作」按选择顺序提交；取消不新增，已点的收藏会保留。计划仍可分批加入重复动作。
- 「替换当前动作」仅影响本场训练；未练时直接换，已练时保留成绩并接上新的独立动作。器械备忘按动作长期保存，最多 500 个 Unicode 字符，支持多行、查看全文和清空。

本轮验证、产物哈希与待真机项见[训练效率实施记录](docs/superpowers/plans/2026-10-16-workout-efficiency-execution.md)。

## 备份与恢复

设置 → 数据备份 →「导出备份」保存 JSON；「从备份恢复」选择文件并核对预览后，点击「替换并恢复」。恢复会替换本机训练、动作和计划数据；有偏好字段时也替换偏好。建议先导出本机数据。取消不写库，坏文件在写入前拒绝，写入失败整批回滚。

新导出为 v3 / schema v5，包含收藏、调重幅度、器械备忘和活动训练准备重量。继续接受旧 v1 / v2；恢复旧备份会将动作偏好清空为默认，旧文件缺少 settings 时保留原主题。旧版应用不能读取 v3，升级前可保留原 v2 文件。

单份文件上限 20 MiB、总记录上限 100,000（含动作偏好行）。保留活动训练、未完成组、归档动作、计划与原始休息值。Web 显示「已请求下载备份」，请到浏览器下载记录确认文件。

## 追加记录、计划与删除

设置 →「从 CSV 追加记录」选择 UTF-8 文件，先核对单位、日期、动作匹配、重复提示和坏行，再追加所选训练。支持约定表头：Strong 的 Date / Exercise Name / Weight / Reps；Hevy 的 start_time / exercise_title / weight_kg / reps；训记的 日期 / 动作名称 / 重量(kg) / 次数。Strong 裸数字可选 kg / lb，磅按 0.45359237 换算。无时区数据按本机时区，只有日期按中午 12:00；没有结束时间的 CSV 显示 0 秒占位，并在详情注明时长未知。

「手动补记录」填写实际起止日期时间，选择已有动作或加入新动作草稿，编辑各组后预览确认。两种方式均只追加历史，不替换备份、不结束当前训练。疑似重复默认不选中；同重量同次数的连续组会保留。导入失败整批回滚，追加后仍须满足备份容量上限。

设置 →「训练计划」新建、改名、排序并保存动作清单，可重复选同一动作，也可保存空计划。计划只存清单；开训重量和次数沿用上次成绩。首页从最近一场已结束且关联计划的训练推导下一套；CSV、补记和自由训练不推进计划轮转。「换一个计划」只影响本次开训。编辑计划不改正在进行的训练；删除计划保留训练，只解除关联。

历史详情和记录页可删除指定训练，确认后无法撤销。记录页有多个可继续动作时，可以移除当前动作：选择删掉已记组，或保留组并在本次隐藏该动作；保留状态在重启后仍有效。最后一个可继续动作不能单独移除，整场删除使用独立确认。删除后历史与进步从剩余记录重新计算。

2026-10-16 本轮实现、测试、浏览器证据与待真机项目见[Phase 3B / Phase 4 执行记录](docs/superpowers/plans/2026-10-16-phase3b-phase4-execution.md)。Android 原生文件、设备交互矩阵尚待手机连接；不将 APK 构建成功视为真机验收完成。

最终本机检查：格式通过、静态检查无问题、**334 条测试通过**、25 项真实浏览器场景通过、9 项校验破坏被测试发现，Android debug / release 构建成功。功能源码提交为 `309d8b5`。

图标已按用户反馈改为橙色哑铃配水平直杆，去除中央对勾；Android 与 Web 同步。最新安装包、裁切预览和复验结果见 [图标与复验记录](docs/superpowers/plans/2026-10-16-icon-and-retest.md)。

随后真机已验证独立包启动、v4 新库、真实文件导出、旧 v2 逐字段恢复、取消预览不改库及旧计划 / 归档动作显示。ADB 在验收中途断开，完整矩阵与桌面图标检查尚未完成；用户暂不方便操作手机，保留断点。证据与接续见 [Android 真机验收记录](docs/superpowers/plans/2026-10-16-android-device-acceptance.md)。主应用训练数据未改动。

## 开发与检查（Windows PowerShell）

本机 SDK 和缓存放在 `.tooling/`；每个 shell 先加载环境脚本。若 PowerShell 禁止执行脚本，可先启动仅当前进程放行的 shell：`powershell -NoProfile -ExecutionPolicy Bypass`。

```powershell
. .\scripts\env.ps1
flutter pub get --offline --enforce-lockfile
flutter analyze
flutter test --reporter expanded
flutter run -d chrome
```

首次配置、缓存、Android 工具链与已知环境问题见[环境笔记](docs/superpowers/plans/dev-environment-notes.md)。首次拉取依赖时省略 `--offline`。

## 浏览器走查

需要 Node.js 22+ 和 Chrome；不需要额外安装 npm 包。脚本使用独立浏览器 profile，从空库操作真实页面，保存每一步截图、语义树及最终结果，失败时返回非零退出码。

```powershell
. .\scripts\env.ps1
flutter build web --no-pub
node scripts/browser_smoke.mjs
node scripts/browser_backup_smoke.mjs
node scripts/browser_import_smoke.mjs
node scripts/browser_plans_smoke.mjs
node scripts/browser_workout_efficiency_smoke.mjs
node scripts/import_plans_mutation_check.mjs
```

证据位于 `build/acceptance/browser-*/` 和 `build/acceptance/browser-backup-*/`。备份驱动从 UI 下载真实文件，在另一隔离 origin 上传并逐字段比对，覆盖取消、坏文件、旧格式、空库与重启持久化。Chrome 路径可通过 `CHROME_EXECUTABLE` 环境变量指定。Android 原生文件界面仍需真机验收。

## Android

开发阶段约定（2026-10-16 用户明确）：今后只生成主应用包并覆盖更新，在主包里新增、补记和删除测试记录，不再单独打验收包。日常测试通过界面清理记录；整库恢复是独立操作，会替换动作库、训练与计划。

「推日 / 我的推胸」来自此前独立包中的兼容性样例。已复核正常 52 动作库在计划新建、编辑、开训、删除后逐字段不变，并补足整库恢复的动作数量与替换说明；完整 337 条测试通过。结果及最新主包见 [本轮复核记录](docs/superpowers/plans/2026-10-16-plan-start-and-test-isolation.md)。

```powershell
. .\scripts\env.ps1
flutter build apk --release --no-pub
adb devices -l
adb install -r build\app\outputs\flutter-apk\app-release.apk
adb shell am start -n com.mobis.gym_tracker/.MainActivity
```

应用包名为 `com.mobis.gym_tracker`。用 `install -r` 更新时保留已有训练数据。

真机取证脚本需要 Node.js 24+，提供点击、滑动、截图、强杀重启、熄屏计时、常亮和震动记录检查。它不会安装 APK 或清空数据。多个设备时设置 `ANDROID_SERIAL`；截图前需解锁并让应用处于前台。

```powershell
node scripts/android_acceptance.mjs snapshot home
node scripts/android_acceptance.mjs tap 历史
node scripts/android_acceptance.mjs snapshot history
```

下方独立验收包命令仅保留历史技术参考，已不再是当前交付和验收流程。debug 变体支持 `run-as` 只读取出数据库核对表、52 个动作和 schema 版本。

```powershell
$env:GYM_ACCEPTANCE_BUILD = '1'
flutter build apk --debug --no-pub
adb install --user 0 -r build\app\outputs\flutter-apk\app-debug.apk
$env:GYM_ACCEPTANCE_PACKAGE = 'com.mobis.gym_tracker.acceptance'
node scripts/android_acceptance.mjs start
node scripts/android_acceptance.mjs fresh-database
adb uninstall --user 0 com.mobis.gym_tracker.acceptance
Remove-Item Env:GYM_ACCEPTANCE_BUILD, Env:GYM_ACCEPTANCE_PACKAGE
flutter build apk --debug --no-pub
```

`GYM_ACCEPTANCE_BUILD=1` 仅追加 `.acceptance` 包名后缀；不设置时产物为主应用。独立包验证结束后重建默认 debug，避免误用同名 APK。更多步骤见[真机作业单](docs/superpowers/plans/phase1-acceptance-sheet.md)。

## 计划与验收

- [Phase 1 规格](docs/superpowers/specs/2026-10-08-flutter-gym-tracker-design.md)与[实施计划](docs/superpowers/plans/2026-10-08-phase1-skeleton-and-recording.md)
- [Phase 2 规格](docs/superpowers/specs/2026-10-09-flutter-gym-tracker-phase2-design.md)与[实施计划](docs/superpowers/plans/2026-10-09-phase2-history-and-progress.md)
- [Phase 1 真机验收作业单](docs/superpowers/plans/phase1-acceptance-sheet.md)
- [2026-10-15 完成度复核与收尾](docs/superpowers/plans/2026-10-15-plan-completion.md)
- [当前状态与接续说明](docs/superpowers/plans/2026-10-15-current-state.md)
- [Phase 3A 已确认设计](docs/superpowers/specs/2026-10-15-flutter-gym-tracker-phase3a-design.md)与[详细实施计划](docs/superpowers/plans/2026-10-15-phase3a-backup-and-restore.md)
- [2026-10-16 Phase 3A 执行结果与待验事项](docs/superpowers/plans/2026-10-16-phase3a-execution.md)
- [Phase 3B：CSV 导入与手动补记详细计划](docs/superpowers/plans/2026-10-16-phase3b-record-import.md)
- [Phase 4：计划、轮转与记录删除详细计划](docs/superpowers/plans/2026-10-16-phase4-plans-and-record-management.md)
