# Phase 3B / Phase 4 执行记录

执行日期：2026-10-16（Asia/Shanghai）。起点为 `3a34c6c`，原测试基线 304 条。用户在两份详细计划交付后要求「开始实现」，本轮已恢复功能开发。

**结论：两期功能已接入；本机自动化、真实浏览器与 Android 构建已完成，Android 真机验收仍未完成。schema 保持 v4，JSON 备份保持 v2，未新增依赖。**

## 已交付行为

- CSV 支持 Strong、Hevy、训记约定列，严格 UTF-8、引号和物理行号、具体时间分组、公斤 / 磅换算。预览展示动作匹配、归档同名候选、疑似重复、坏行知悉和时长未知，用户选择后追加；文件和手动补记共用仓储。
- 导入只创建已结束、无计划关联的训练，休息值留空，不修改活动训练、偏好和计划。预览快照失效拒绝写入；批次写入、容量复核在同一事务内，失败全部回滚。保存成功与界面刷新失败分别提示。
- 设置提供训练计划列表、草稿编辑、重复动作、空计划、保存、排序和删除。列表按 position / rowid，移动按具体 id；删除计划解除训练关联，保留训练与组。
- 首页提供下一套和本次临时选择；轮转仅依据最近已结束且关联计划的训练，不存游标。活动冲突检查优先，创建训练和首组在一个事务内；编辑计划不改正在练的快照。
- 历史详情和记录页可确认删除指定训练。移除本场动作支持删除组、保留已完成组、取消；保留时删除占位组并取消该动作休息，重启后仍隐藏。最后一可继续动作受双层保护。
- 完整动作列表和可继续列表分离；移除后按 id 选择焦点并同步重量 / 次数。删除其他历史不重置活动训练，删除当前训练才 reset。
- 统一 DataRevision；历史、进步与详情主动监听提交后变化。不能只依赖给 Shell Navigator 换 key，因为其全局键会保留页面状态。

## 原计划完成度映射

原计划中的细粒度步骤包含建议文件拆分、先后顺序和每小步提交命令。本轮按功能链路合并实施，测试文件也做了合并；未逐字执行的原命令不追勾。下面记录实际结果。

| Phase 3B 任务 | 当前结果 | 证据位置 |
|---|---|---|
| 0 统一模型 / 刷新 | 已实现，基线与校验通过 | import_records、data_revision、data_revision_loader；domain / app / widget 测试 |
| 1 CSV 扫描 | 已实现，含真实行号、引号、换行和数量上限 | csv_records；import_pipeline_test |
| 2 三来源映射 | 已实现，含严格日期、单位、分组冲突、fixture 数值 | workout_csv；六份 import fixture |
| 3 匹配 / 重复预览 | 已实现，含选择子集统计、坏行确认、归档匹配 | import_preview；domain / data / widget 测试 |
| 4 事务追加 | 已实现，含故障注入、过期快照、20 MiB 回滚 | import_repo_test；备份回归 |
| 5 编排 | 已实现，含取消迟到文件、单位重解析、双击、刷新失败 | import_controller_test |
| 6 页面 | 已接入文件页 / 手动页 / 设置入口 / 详情备注 | import_and_plans_test；真实浏览器 |
| 7 平台验证 | 自动化、变异和 Web 通过；Android 真机未运行 | 下表与待验收项 |
| 8 收尾 | 本记录、README、原计划状态已更新；明确清单提交 | Git 历史 |

| Phase 4 任务 | 当前结果 | 证据位置 |
|---|---|---|
| 0 基线 / 旧数据 | 已核对，复用真实 legacy-v2 备份和内存 fixture | plans_and_deletion_test；旧备份浏览器 |
| 1 轮转 | 已实现，忽略活动 / 无模板场次、循环到第一套 | plans_and_records_test |
| 2 计划仓储 | 已实现，事务保存 / 移动 / 删除与解除引用 | plans_and_records_test；故障注入 |
| 3 草稿界面 | 已实现，取消不落库、重复动作、冲突保留输入 | plan_controller_test；import_and_plans_test |
| 4 原子开训 | 已实现，冲突优先、预填、临时选择、过期检查 | controller / 仓储测试；浏览器 |
| 5 指定目标删除 | 已实现，确认快照复核、级联、失败回滚 | plans_and_records_test；record_management_controller_test |
| 6 动作可见性 / 焦点 | 已实现，保留组、重启、末项保护、50→20 kg 同步 | remove_exercise_test（state 与 widget）；浏览器 |
| 7 整场删除界面 | 已实现，取消、确认、活动 / 其他历史分别刷新 | widget / controller 测试；浏览器 |
| 8 跨功能 / Web | 已验证旧计划、归档预填、CSV、PR 删除、备份往返 | plans_and_deletion_test；下表 |
| 9 Android / 交付 | debug / release 已构建；真机矩阵待设备 | APK 信息与待验收项 |

## 验证

| 检查 | 实际结果 |
|---|---|
| dart format / flutter analyze --no-pub | 格式通过，静态检查无问题 |
| 原测试基线 | 304 条通过 |
| 本轮全量 | 334 条通过，含开训首屏未载入时禁止完成组的回归 |
| 训练浏览器 | 7/7，无运行时错误 |
| 备份浏览器 | 6/6，真实上传 / 下载、旧格式与重启字段一致 |
| CSV 浏览器 | 4/4，真实选择文件、取消、坏行确认、同日两场、重复默认不选、备份恢复往返 |
| 计划 / 删除浏览器 | 8/8，A/B/C、重复动作、轮转、临时选择、排序、两种动作移除、重启继续、历史与活动删除 |
| 故意破坏检查 | 9/9 被测试捕获；每次还原源文件原始字节 |
| Android debug / release | 构建成功，主包名 com.mobis.gym_tracker |
| Android 真机 | ADB 无设备，未安装、未操作主包或验收包 |

9 项破坏分别为：按天合并、错误磅系数、跳过导入快照复核、跳过备份容量限制、轮转包含活动训练、删计划不解除引用、保留分支删除已完成组、取消末项保护、取消仍移除。日志记录断言失败，未把编译失败当作成功发现。

新增测试集中在 import_pipeline_test、import_repo_test、import_controller_test、plans_and_records_test、plan_controller_test、record_management_controller_test、state / widget 的 remove_exercise_test、import_and_plans_test、plans_and_deletion_test。原 304 条中只有“归档动作显示未知名称”的旧断言按新需求改为保留原名，其他旧回归保留。

最终复核发现并修复了开训首屏的时序问题：RecordPage 等 resume 和编辑数值载入后再开放记录操作，避免快速点击时数值仍为空而漏记。增加延迟载入的界面回归。浏览器驱动同时显式等待动作选择器数据就绪，避免把加载期间发送的输入当成用户已完成搜索。

首轮真实浏览器证据（UTC 目录时间对应当日本地日期）：

- `build/acceptance/browser-2026-10-16T03-00-36-769Z/`
- `build/acceptance/browser-backup-2026-10-16T03-01-54-014Z/`
- `build/acceptance/browser-import-2026-10-16T03-00-36-839Z/`
- `build/acceptance/browser-plans-2026-10-16T03-07-30-818Z/`
- `build/acceptance/import-plan-mutations-2026-10-16T03-01-21-534Z/`

浏览器脚本使用独立 profile / origin、真实 SQLite wasm、真实文件选择和下载。新驱动复用备份驱动的浏览器连接与取证能力，未新增 npm 依赖。证据属于 build，不纳入版本控制。

最终代码复核的四组浏览器证据：

- 训练 7/7：`build/acceptance/browser-2026-10-16T03-18-47-168Z/`。
- 备份 6/6：`build/acceptance/browser-backup-2026-10-16T03-18-47-089Z/`。
- 导入 4/4：`build/acceptance/browser-import-2026-10-16T03-19-24-534Z/`。
- 计划 / 删除 8/8：`build/acceptance/browser-plans-2026-10-16T03-19-16-540Z/`。
- 汇总及 APK 校验：`build/acceptance/phase3b-phase4-final/verification.json`。

## APK

以下大小与哈希对应图标更新前的功能交付包。同一路径后续已重建，当前安装包以 [图标与复验记录](./2026-10-16-icon-and-retest.md) 的大小与哈希为准。

- 默认发布包：`build/app/outputs/flutter-apk/app-release.apk`。
- 字节数：69,377,889。
- SHA-256：`F380C818E80EC4EB20FF9999F828A6ABD3D5E363E1471B66E92CF0928414C7E5`。
- aapt 核对：`com.mobis.gym_tracker`，versionCode 1，versionName 1.0.0，compileSdk 36。
- debug 构建同样成功。没有连接设备，本轮未安装 APK，也未清空真实训练。

## 待完成的设备验收

**后续用户修正（2026-10-16）**：不再单独构建验收包；以下场景在主包覆盖更新后执行，并通过界面新增 / 删除开发测试记录。原独立包说明保留为当时的方案，实际部分真机结果见 [真机记录](./2026-10-16-android-device-acceptance.md)，最新复核与工作方式见 [计划开训复核](./2026-10-16-plan-start-and-test-isolation.md)。

下列项目未执行，不标整期完成。手机连接并允许 USB 调试后，使用 `GYM_ACCEPTANCE_BUILD=1` 构建 `.acceptance` 独立包，只在该包操作。

1. 补 Phase 3A A1–A9：系统保存 / 选择文件、取消、真实备份往返、坏文件与重启。
2. Phase 3B：三来源 CSV 的手机文件选择、取消、坏行与单位确认；手动补记键盘 / 小屏；导入后备份到空验收库恢复；活动训练保留。
3. Phase 4 P1–P6：旧计划恢复、计划编辑排序、轮转、冲突优先、临时选择、正在用的计划改名 / 删除。
4. Phase 4 D1–D5 / B1：动作两个移除分支、强杀继续、焦点数值、整场删除、删除 PR 后三张卡与备份引用完整性。
5. 独立验收完成后卸载该测试包，清理验收环境变量，再重建默认包并更新哈希。主应用数据不作为故障注入对象。

## Git 与接续

未改变 schema / backup version，未装依赖。用户已有 `.claude/settings.local.json` 与 `.tmp/` 保留且排除提交。未推送远程。

功能与测试源码提交：`309d8b5`（feat: add record imports, training plans and targeted deletion）。文档状态与安装包信息另作收尾提交。

下一次接续先看本文件和真机清单，不重复实现已通过的仓储 / 界面。若无设备，继续保持“功能和本机验证完成、真机待验收”，不能以构建成功补写设备通过。
