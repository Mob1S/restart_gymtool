# 训练导航、多天计划与器械重量输入执行记录

日期：2026-10-17（Asia/Shanghai）。用户批准设计与实施计划，并选择子代理实施。当前分支 `codex/workout-efficiency`，起点 HEAD `a5b99b8`。依据同日设计规格与实施计划，以下记录最终结果。

## 实现结果

| 任务 | 结果 |
| --- | --- |
| 1 重量领域模型 | 十进制器械读数、kg/lb、精确步进；整数不强制显示小数，kg 辅助显示保留两位 |
| 2 v6 迁移 | 原子升级，旧单层计划包装为父计划的多个训练日；迁移失败回滚 |
| 3 v4 备份与 CSV | v1–v3 升级、v4 严格验证；CSV 保留原单位与标准 kg，支持再导入 |
| 4 父计划与轮换 | 任意父计划／训练日数量、独立轮换；稳定保留训练日和动作出现项 ID |
| 5 计划 UI | 父／日／动作三级编辑、排序、草稿丢弃与删除确认；管理列表为唯一新建入口 |
| 6 重量持久化 | 原始读数、单位与标准 kg 同事务写入；完成组不受后续偏好修改影响 |
| 7 方向锁定输入 | 重量上下、次数左右；起手区域锁定、高亮、多指过滤、取消还原、键盘和语义操作 |
| 8 幅度与单位设置 | 明确选择后保存、取消不变；kg/lb 独立预设／自定义幅度，可选 kg 换算 |
| 9 历史操作 | 日期筛选、补加预填、行内删除、详情返回保留日期、当前列表 CSV 导出 |
| 10 月历与首页 | 月历、完成标记刷新、实测高度居中、小屏／横屏／大字号滚动回退 |
| 11 验收与交付 | 格式、静态分析、512 条测试、49 项浏览器流程、19 项变异守卫、Web 与 Android 双构建通过 |

没有新增依赖。用户已有 `.claude/settings.local.json`、`.tmp/` 和讨论草图 `.superpowers/` 保留，未纳入本轮提交。子代理共享工作区，本轮实现、更新日志与验收文档采用集成提交。

## 审查与修复

- 计划保存、开训、导入和偏好提交保留可备份容量验证；源读数与标准 kg 必须一致。
- 首页自行监听数据 revision，避免重建状态打断“结束旧训练并开始新训练”；切换计划／日查询期间禁止旧选择开训。
- 训练日编辑标题和内容一起滚动，覆盖横屏键盘及 2 倍字号。
- 设置草稿保留各单位的有效自定义幅度；偏好与待填组同事务更新，检查归属和冲突 token。
- 替换旧 +/- 测试定位时使用真实滑动并断言新重量，保留更正、撤销、替换的原有断言。
- 两项变异首次未被检测，补入“只有活动训练不能作为轮换来源”和“无训练记录时训练日孤立父引用”独立测试后，19 项全部被检测。
- 浏览器驱动等待位置稳定且命中元素未被提示条遮挡，识别 Flutter 内嵌 range 的原生可访问值；月历与管理入口使用真实触摸事件。

## 自动化验证

```powershell
. .\scripts\env.ps1
dart format --output=none --set-exit-if-changed lib test
flutter analyze --no-pub
flutter test --no-pub --reporter expanded
flutter build web --no-pub --no-wasm-dry-run
flutter build apk --debug --no-pub
flutter build apk --release --no-pub
```

格式：194 个文件，0 个变化。静态分析：No issues found。全量测试：512 条通过（基线 396 条）。日志位于 `build/training-redesign-{format,analyze,all-tests,web,debug,release}.log`。

浏览器使用独立 Chrome profile／origin 与真实 SQLite wasm；下载和恢复真实文件，无仓储调用替代 UI。

| 套件 | 通过 | `build/acceptance/` 下最终证据目录 |
| --- | --- | --- |
| 原训练流程 | 7 | `browser-2026-10-17T09-05-41-142Z` |
| 备份与旧版恢复 | 6 | `browser-backup-2026-10-17T09-06-17-329Z` |
| CSV 导入 | 4 | `browser-import-2026-10-17T08-58-38-436Z` |
| 多训练日计划 | 8 | `browser-plans-2026-10-17T09-13-14-101Z` |
| 更正／撤销／替换等效率操作 | 11 | `browser-workout_efficiency-2026-10-17T09-03-58-466Z` |
| 本轮日历／输入／原生单位／视口 | 13 | `browser-training_redesign-2026-10-17T09-14-41-068Z` |

共 49 项；每目录保存 `results.json`、截图和语义树。真实 AppBootstrap 的补记联动另覆盖选择日期、录入 50 lb、核对 kg、详情返回与同页取消／确认删除。

变异验证：`import_plans_mutation_check.mjs` 9 项、`backup_mutation_check.mjs` 10 项全部检测成功。每次变异后恢复原始字节；证据目录分别为 `import-plan-mutations-2026-10-17T09-10-49-663Z`、`backup-mutations-2026-10-17T09-11-31-743Z`。

## 产物与平台边界

- 正式 Web 预览：`http://localhost:8080/`，服务实际 `build/web`。
- 主包 debug：`build/app/outputs/flutter-apk/app-debug.apk`。
- 主包 release：`build/app/outputs/flutter-apk/app-release.apk`（67.4 MB）。
- `aapt dump badging` 确认包名 `com.mobis.gym_tracker`、versionName `1.0.0`、minSdk 24、targetSdk 36。
- release SHA256：`628AFA84D20DFC6F92B9837B9EA4ABE3E5A8653945D9EF03AB27CD83A21D6CDE`。

初次交付时没有设备。用户随后连接手机，主包已覆盖安装并完成主要真机验收：方向锁定、高亮及中断还原、kg/lb原始读数、强杀恢复、常亮、熄屏计时、横屏滚动和历史联动均通过。清理测试记录后，备份的整个data对象与基线逐字段一致，旧5场／21组／52动作和偏好未变化。详情与实测范围见[Android真机验收记录](2026-10-17-android-training-redesign-acceptance.md)；多指、汗手与长时间现场的主观手感仍待人工试用。

## 云端与更新日志

用户指定远程 `https://github.com/Mob1S/restart_gymtool`，配置为 `origin`，提交并推送当前 `codex/workout-efficiency` 分支。变更摘要见根目录 `CHANGELOG.md`。
