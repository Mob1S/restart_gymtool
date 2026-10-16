# 训练操作效率实施记录

日期：2026-10-16，Asia/Shanghai。范围依据：同日 `2026-10-16-workout-efficiency.md`，用户随后明确“实施最新的开发计划”并要求继续。

起点 HEAD：`21c41ff`。工具链实测 Flutter 3.47.6 / Dart 3.13.5。原有 `.claude/settings.local.json` 和 `.tmp/` 保留，不纳入提交。未新增第三方依赖。开发时没有连接 Android 设备。

## 实现结果与任务映射

| 任务 | 实现与复核 |
|---|---|
| 1 | 完成、开始、结束、添加均进入事务仓储；并发完成只产生一组；首组与出现项原子建立；提交后刷新失败阻止再次写入 |
| 2 | 完整会话快照保护已完成组更正、有限撤销；跨训练组 ID、过期预览、已结束、隐藏动作、其他动作完成等拒绝路径已测 |
| 3 | 本场组列表、实际重量/次数编辑、撤销说明与确认；保留旧组可继续更正；稳定键和表单语义标签 |
| 4 | 休息只调唯一未完成组重量；串行合并最新输入；开始、切换、离开和变更预览前等待保存；恢复前 flush，generation 阻止晚到回调覆盖新内存 |
| 5 | 只追加 v5 偏好表；v3 导出及严格校验；偏好纳入快照、容量和恢复事务；旧 v1/v2 清空动作偏好并保留缺省主题兼容 |
| 6 | 相对加减、1.25 kg 显示、500 code point 备忘、动作设置；取消、清空、多行 Emoji、同名不同 ID 及独立步长 |
| 7 | 收藏与最近使用、全库搜索、单选兼容；最近由真实完成组时间推导；星标独立点击，48dp 点击区域 |
| 8 | 训练批量添加单事务、计划批量草稿；点击顺序、反选重选、一次去重、分批重复；旧浏览器流程保留断言并增加确认 |
| 9 | 零组与有成绩两种替换、已有目标建立新出现项、源休息取消而其他休息保留；多点故障注入与提交后刷新失败已测 |
| 10 | 选择目标后确认替换；冲突重新选择；贯穿界面流程及旧组修正、成绩归属、原计划不变 |
| 11 | 自动化、真实浏览器、构建、文档和产物核验；真机未执行，断点见下 |

测试文件按实际职责合并，未机械创建计划里的每个拟议文件名：

- `test/data/workout_write_repo_test.dart`：事务完成、批量中途失败、并发。
- `test/data/workout_edit_repo_test.dart`、`workout_efficiency_boundaries_test.dart`：更正、撤销、外来 ID、失败回滚及偏好/最近使用边界。
- `test/data/exercise_preferences_repo_test.dart`、`backup_v3_test.dart`：偏好、旧格式、新格式完整性、容量计数和真实数据库往返。
- `test/data/exercise_replacement_repo_test.dart`：替换分支、独立出现项、多点回滚、保存后刷新失败。
- `test/state/pending_weight_test.dart`、`pending_weight_queue_test.dart`、`batch_add_exercises_test.dart`：输入队列、generation、互斥、重读与通知。
- `test/widget/exercise_picker_test.dart`、既有 `viewport_test.dart`：选择器、收藏、取消、键盘避让及小屏横屏。
- `test/e2e/workout_efficiency_test.dart`：从真实界面按计划开训、两组、调重、更正、偏好、替换、结束并核对数据库和原计划。

实施调整：沿用本聊天和当前代码库；测试集中补足后统一复核，没有为每个任务分别提交中间版本，也未逐任务记录先红后绿证据。最初新增夹具通过缺失 `now` 参数暴露缺失接口；首轮基线与新增文件交错，因此不把当时的编译失败作为原项目失败。最终全量回归覆盖原有用例。

## 验证证据

- 格式：`dart format --output=none --set-exit-if-changed lib test`，日志 `build/efficiency-format-check.log`。
- 静态分析：`flutter analyze --no-pub`，日志 `build/efficiency-analyze-final.log`。
- 全量：`flutter test --reporter expanded`，396 条通过，日志 `build/efficiency-all-tests.log`。
- Web：`flutter build web --no-pub` 成功，包含 wasm dry run；最终重建使用 `--no-wasm-dry-run`，避免反复执行不用于交付的 wasm 兼容检查。日志 `build/efficiency-web-final.log`。
- 备份变异：8/8；导入/计划变异：9/9。保留全部原有守卫，仅适配统一写入锁的新名称。
- 浏览器使用项目原有真实 SQLite wasm 驱动、独立 profile 和 origin；导出实际下载文件再恢复，未调用仓储代替用户操作。

真实浏览器共 **36 项通过**：

| 套件 | 通过 | 证据目录（项目根目录下） |
|---|---:|---|
| 原训练流程 | 7/7 | `build/acceptance/browser-2026-10-16T15-00-13-829Z/` |
| 备份 | 6/6 | `build/acceptance/browser-backup-2026-10-16T14-58-29-504Z/` |
| CSV | 4/4 | `build/acceptance/browser-import-2026-10-16T14-58-29-571Z/` |
| 计划与删除 | 8/8 | `build/acceptance/browser-plans-2026-10-16T14-58-29-526Z/` |
| 新训练效率专项 | 11/11 | `build/acceptance/browser-workout_efficiency-2026-10-16T15-00-13-848Z/` |

备份变异证据：`build/acceptance/backup-mutations-2026-10-16T10-34-46-876Z/`；导入/计划：`build/acceptance/import-plan-mutations-2026-10-16T10-35-27-818Z/`。每个目录有实际结果 JSON、截图或测试日志。

专项通过真实 UI 和导出 JSON 共同覆盖 E01/E02/E03、E05/E06、E08/E10/E11/E13、E15/E16、E20/E21/E22、E26/E29/E30。E04/E07/E09/E12/E14/E17/E18/E19/E23/E24/E25/E27/E28 等由事务、state、widget 与既有回归分层验证。真机专属部分不纳入通过数。

开发中修正的浏览器适配点：搜索先显式聚焦；动作行与“收藏”按钮分开定位；读取嵌套 input/textarea 的可访问标签；返回主页判断使用精确“设置”标签，避免把“动作设置”误认为主页；重新打开训练后按明确动作 chip 选择目标。旧断言均保留。

Android debug 与 release 主包均构建成功；日志 `build/efficiency-debug-final.log`、`build/efficiency-release-final.log`。最终 release 路径和 SHA256 由最终构建日志与下方产物记录共同核对。

## 产物与提交

- 主包：`build/app/outputs/flutter-apk/app-release.apk`（约 66.8 MB）。已用 aapt 核对包名 `com.mobis.gym_tracker`，启动 Activity 为 `.MainActivity`。
- SHA256：`4CEFF314CCB7F788EB385D3748204C936C129854487816B0BD9FDB98583D74B2`。
- 业务修改、测试、README、计划与本执行记录合并为一次明确文件清单提交；不包含构建产物、本地配置或 `.tmp/`。提交可由 `git log -1 -- docs/superpowers/plans/2026-10-16-workout-efficiency-execution.md` 直接定位。

## Android 断点

`adb devices -l` 未发现设备，未安装或操作主应用。A01–A10 及 Android 原生文件导出/恢复、触感、熄屏、强杀恢复均未执行。自动化计时与 Web 通过不替代这些项目。

接续：连接并授权设备，先保留现有数据并导出备份，用主包 `com.mobis.gym_tracker` 的 release APK 执行 `adb install -r` 覆盖更新。按原计划 §7.2 验收；仅经界面删除明确的“效率验收”训练和恢复测试偏好。整库恢复仍是独立替换操作，不用来清理测试数据。
