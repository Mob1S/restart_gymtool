# Training Plan Rest Days Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** 支持任意训练／休息周期，按本地自然日显示“今日已完成／明天休息／今天休息”，兼容已有训练和备份。

**Architecture:** 用纯函数从当前周期、最近有效完成和首次启用日期推导状态；仓储在事务中校验推荐和训练类型。休息不创建训练记录，首页在午夜及恢复前台时重新读取。

**Tech Stack:** Flutter/Dart、现有 SQLite executor、flutter_test、Chrome CDP 浏览器验收；不增加依赖。

## Global Constraints

- 依据 `../specs/2026-10-18-training-plan-rest-days-design.md`（用户已批准实施）。
- schema7；备份v5；兼容v1–v4，旧项目全部视为training，activatedOn为null。
- 休息从完成日的次日起计；前导休息从首次启用当日起计；未完成训练不跳过。
- 保留原始重量单位、动作出现项ID、训练快照、容量校验、事务与冲突检测。
- 历史允许关联后来改为rest的项目；新开训只允许training。
- Flutter测试、构建串行执行；PowerShell先执行 `. .\scripts\env.ps1`。
- 继续在当前分支实施，保留用户未跟踪目录；使用普通提交和push。

## File responsibilities and interfaces

- `lib/domain/training_schedule.dart`：纯日期推进，返回`TrainingSchedule`。
- `lib/domain/training_plans.dart`：`TrainingDayKind { training, rest }`、各日的`kind`和计划的`LocalDate? activatedOn`。
- `lib/domain/local_date.dart`：`int daysSince(LocalDate other)`，用UTC投影年月日计算天数。
- `lib/domain/plans.dart`：`PlannedWorkout.schedule`；`hasUsableDay`只在推荐状态为training时成立。
- `lib/data/db/migrations.dart`：原子追加schema7，不改发布过的迁移内容。
- `lib/domain/backup.dart`、`backup_upgrade.dart`、`data/repositories/backup_repo.dart`：v5字段及严格兼容转换。
- `lib/data/repositories/training_plan_repo.dart`：保存kind、拒绝rest动作，`activateTrainingPlan(exec,id,{required LocalDate today})`只填空值。
- `lib/data/repositories/workout_plan_repo.dart`：`loadNextWorkout/readPlannedWorkout`增加`DateTime? now`，调用纯推导并把日期／结果纳入令牌。
- `lib/state/active_session_controller.dart`：开训事务拒绝休息推荐。
- `lib/features/plans/{plan_editor_page,day_editor_sheet,plan_picker}.dart`：周期编辑、类型转换确认、手选只列训练日。
- `lib/features/workout/workout_home_page.dart`：状态展示、显式首页激活、午夜和生命周期刷新。

### Task 1: 日历推进模型

**Files:** 上述四个domain文件；`test/domain/training_schedule_test.dart`。

**Interfaces:** `TrainingSchedule resolveTrainingSchedule({required List<TrainingDay> days, required LocalDate today, LocalDate? activatedOn, String? completedDayId, LocalDate? completedOn})`；返回`state`（empty/training/completed/rest）、`day`、`nextTrainingDay`。后续任务消费这些签名。

- [x] 写失败测试：`expect(schedule(on: LocalDate(2026,10,18)).state, TrainingScheduleState.completed);`；同一完成记录19日为rest、20日为training。
- [x] 执行 `. .\scripts\env.ps1; flutter test test/domain/training_schedule_test.dart --no-pub`，预期缺失类型失败。
- [x] 实现civil date差值：`DateTime.utc(year,month,day).difference(DateTime.utc(other.year,other.month,other.day)).inDays`。从完成项下一项遍历，完成当日拦住rest；只消耗rest，遇training停止；全rest用取模避免无限遍历。
- [x] 增加前导／连续／跨周期／全rest、空计划、删除完成项、未完成训练等待、时钟回拨、跨年与闰日断言；运行同一命令预期全绿。
- [x] 提交 `feat: derive training and rest days from local dates`。

### Task 2: 数据和备份

**Files:** migrations、backup三个文件、training_plan_repo、template_repo；`test/data/training_rest_days_test.dart`、`test/data/backup_v5_test.dart`。

**Interfaces:** 消费Task1类型；生产`activateTrainingPlan`和v5导出，保留`upgradeBackupToV4`，新增`Map<String,Object?> upgradeBackupToV5(Map<String,Object?> root)`。

- [x] 写失败用例：schema6数据库迁移后旧行kind=training、activated_on=null；v4原始单位备份升v5后`sourceWeight/sourceUnit`相等。
- [x] 执行 `. .\scripts\env.ps1; flutter test test/data/training_rest_days_test.dart test/data/backup_v5_test.dart --no-pub`。
- [x] 原子事务执行`ALTER TABLE split_template ADD COLUMN kind TEXT NOT NULL DEFAULT 'training' CHECK(kind IN ('training','rest'))`与`ALTER TABLE training_plan ADD COLUMN activated_on TEXT`，同事务写schema7。
- [x] 字段读取／草稿保留kind；rest且exerciseIds非空抛`PlanValidationException('休息日不能包含动作')`。激活使用`UPDATE training_plan SET activated_on=? WHERE id=? AND activated_on IS NULL`并保留容量守卫。
- [x] v5字段校验：`kind`只允许两个值；`activatedOn`为null或`LocalDate.tryParse`成功；rest的templateExercises必须为空，sessions引用仍按现有父子匹配验证。
- [x] 在独立测试中验证非法日期/kind/rest动作/孤立引用及恢复失败原数据不变；测试激活幂等与历史关联rest合法；运行用例至全绿。
- [x] 提交 `feat: persist rest days with schema7 and backup v5`。

### Task 3: 推荐和开训安全

**Files:** workout_plan_repo、active_session_controller；`test/data/training_rest_days_test.dart`。

**Interfaces:** 消费Task1/2；`loadNextWorkout(..., DateTime? now)`与`readPlannedWorkout(..., DateTime? now)`；`PlannedWorkout.schedule`提供首页状态。

- [x] 写失败用例：当天completed、次日rest、下一日training；同一日期令牌可开训，跨日旧令牌拒绝；手选rest拒绝。
- [x] 推荐读取只查live/legacy的finished_at，不在读取时写激活日期；日期由`now ?? DateTime.now()`转换为LocalDate。
- [x] 令牌加入`today.key`和推导state；手选training覆写推荐但不写进度；开训事务检查`!planned.freeTraining && !planned.hasUsableDay`即拒绝。
- [x] 验证自由训练/manual/csv不推进；排序、改名、删除、转rest、删除最近session后重推；活动session跨日保留。
- [x] 运行 `. .\scripts\env.ps1; flutter test test/data/training_rest_days_test.dart test/data/training_plan_repo_test.dart --no-pub`至全绿并提交。

### Task 4: 编辑和首页

**Files:** 三个plans UI文件、plan_controller、workout_home_page；`test/widget/rest_days_test.dart`。

**Interfaces:** 消费`kind/activatedOn/schedule/activateTrainingPlan`；主页可注入`DateTime Function()? now`便于午夜测试，默认真实设备时钟。

- [x] 写失败UI断言：`expect(find.text('今天休息'), findsOneWidget)`；不显示“本次没有动作”；有活动训练仍显示“继续训练”。
- [x] 周期标题和训练/休息数量，添加休息日，rest默认名“休息”；类型控件切换已有动作时弹确认，取消保持草稿、确认只清草稿动作。
- [x] 选择训练日过滤kind；保留ID与父级事务；各计划列表摘要使用训练和休息实际数量。
- [x] 首页显式激活当前父计划后读取推荐；中间状态使用文本；提供自由训练和手选；空／仅rest不显示不存在的下一训练日。
- [x] `WidgetsBindingObserver`恢复前台和`Timer(nextMidnight.difference(now))`刷新；刷新时清除旧手选；dispose移除监听和计时器。保持实测居中及溢出滚动。
- [x] 测试转换确认/取消、草稿丢弃、午夜/前台、活动优先、390×844居中、窄屏/横屏/大字体可达。
- [x] 执行 `. .\scripts\env.ps1; flutter test test/widget/rest_days_test.dart test/widget/training_home_test.dart test/widget/multiday_plans_test.dart --no-pub`至全绿并提交。

### Task 5: 完整回归与发布记录

**Files:** `scripts/browser_backup_smoke.mjs`及相关浏览器套件、`CHANGELOG.md`、本计划及设计状态。

- [x] 更新当前导出版本断言为5/7，保留旧v4输入测试；新增真实文件rest计划保存／恢复／手选测试。
- [x] 执行`. .\scripts\env.ps1; dart format lib test`，再`flutter analyze --no-pub`，预期无问题。
- [x] 执行`. .\scripts\env.ps1; flutter test --no-pub --reporter expanded`，预期原有回归和新增测试全部通过。
- [x] 执行`. .\scripts\env.ps1; flutter build web --no-pub --no-wasm-dry-run`，运行本地Chrome真实流程（使用现有隔离profile，不碰手机用户数据）。
- [x] changelog写实际行为／备份兼容；记录实际测试结果和未验设备范围；更新本计划完成项和设计实施状态。
- [x] 审查`git diff --check`和`git status --short`，仅提交本轮文件，普通`git push origin HEAD`。

## Self-review

规格1–7均映射到以上任务；类型、签名和版本保持一致。自然日推导、首次启用、连续/全休息、历史引用与开训限制分开验证；未引入固定分化或休息完成记录。用户已批准实施，沿用此前选择的当前会话执行方式，不再重复请求方案批准。
