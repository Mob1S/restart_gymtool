# Phase 4：分化计划、轮转与记录删除 Implementation Plan

> **状态：2026-10-16 已按用户「开始实现」接入功能，自动化与真实浏览器通过；Android 真机验收待设备。实际任务分组、合并测试位置和未执行项见 [执行记录](./2026-10-16-phase3b-phase4-execution.md)。以下细项保留原实施方案，不将未按原命令逐条执行的步骤追记为通过。**
>
> **For agentic workers:** 推荐按 4A（计划与轮转）→ 4B（记录删除）两个可独立回归的批次执行。所有步骤先写失败用例，再最小实现、验证、明确清单提交；记录实际结果，不提前勾选。

**Goal:** 用户能管理有序分化计划、自动进入下一套训练，并明确删除错误训练或训练中的动作；删除与保留记录的语义可预测，备份、历史、进步和继续训练保持一致。

### 2026-10-16 实际交付检查

- [x] 计划草稿、重复 / 空计划、保存、排序、删除及解除关联。
- [x] 轮转、本次选择、活动冲突优先、原子开训。
- [x] 指定训练删除、动作删组 / 保留组、焦点与数值同步、末项保护。
- [x] 旧备份 / CSV / 进步 / 继续训练联动，自动化与真实浏览器验证。
- [x] Android debug / release 构建与包名核对。
- [ ] Android P1–P6、D1–D5、B1 真机验收；需连接设备。

**Architecture:** 纯轮转 / 可见性逻辑 + 事务化计划仓储 / 记录管理仓储 + state 编排 + 现有记录页、历史页、设置和新计划页。复用 schema v4 与共享 DataRevision，不维护独立轮转游标，不为隐藏已完成动作加第二份状态表。

**Tech Stack:** Flutter 3.47.6 / Dart 3.13.5、SqlExecutor.transaction、SQLite / FFI / wasm、Provider、go_router、现有 UUID 与 UI 组件。

## 1. 起点、依赖与范围

### 1.1 开始前事实

- 2026-10-16 当前代码为 Phase 3A 已实现版本，记录的测试基线 **304 条**；Android 真机备份验收仍未补，不能称完整验收完成。
- `split_template`、`template_exercise` 已由 v4 创建，`session.template_id` 已由 v3 创建。**本期不再新建这些表，不改写任何已发布迁移，不无故升到 v5。**
- 旧 v2 备份可已含非空计划、重复动作、相同 position；这些是需要正常加载的数据，不能进入计划页时清空重建。
- 推荐先完成[Phase 3B 计划](./2026-10-16-phase3b-record-import.md)，再执行本期。通用 `state/data_revision.dart` 是 3B Task 0 的交付；它在当前代码中尚不存在，执行时先核对。
- [3A 执行记录](./2026-10-16-phase3a-execution.md)、[当前状态](./2026-10-15-current-state.md)是启动检查依据；后续实际 HEAD / 测试数按现场记录，不写死到 304。

### 1.2 需求依据

- [Flutter 总体规格](../specs/2026-10-08-flutter-gym-tracker-design.md) §5.3、§9–10。
- [旧项目总纲](../specs/2026-10-08-gym-tracker-design.md) §5.4、§5.7。
- 已只读核对旧项目 `src/domain/rotation.ts`、`src/repositories/templateRepo.ts` 和 `docs/superpowers/specs/2026-10-07-plans-and-record-management-design.md`。
- 复用产品规则，不照抄旧项目手写 BEGIN 或按 position 批量更新的实现；当前已存在真正事务接口。

### 1.3 本期边界

**4A：计划。** 新建、重命名、有序动作清单、上移 / 下移、整份保存、删除计划、首页下一套、临时换本次计划、按计划原子开训。

**4B：记录。** 历史详情删除整场、记录页删除当前活动训练、移除本场动作（删组 / 保留已完成组）、焦点与继续训练刷新。

不做日历排课、周期长度、周几绑定、目标重量 / 目标次数 / 目标组数、批量删除、回收站、撤销、手势拖拽排序、编辑已完成组。需要时另立设计，不顺带扩展。

## 2. Global Constraints 与行为规则

### 2.1 计划只存什么

计划存名字、计划顺序、动作及动作顺序，允许同一个动作出现两次；每个出现项拥有独立 template_exercise.id。组重量 / 次数继续来自 getLastPerformance，无历史用现有默认 20 kg × 8，不在计划里存另一份目标。

已有归档动作仍能保留在已导入计划中并带归档提示，不自动解档或丢弃；新增选择默认沿用现有动作选择器，已存动作可以移除。

编辑只改本地草稿，保存后整份原子覆盖。新计划在点击保存前不创建数据库行；取消不会留下「新计划」空壳。允许明确保存空动作清单，空计划可编辑、可删除，也可开始一场空训练后自行加动作。

### 2.2 轮转

| 状态 | 结果 |
|---|---|
| 无计划 | 复用最近一场已结束训练的动作组合；无历史为空训练 |
| 有计划，无已结束关联训练 | 第一套 |
| 最近已结束关联训练为 A | 当前有序列表中 A 的下一套，末尾循环到第一套 |
| 来源模板已不存在 / 返回 null | 第一套 |
| 最近一场是无模板 CSV / 补记 / 自由训练 | 跳过该场，仍看最近的非空 template_id |
| 有一场正在进行 | 先冲突提示，不建立另一场，不推进轮转 |

不储存 nextIndex。结束空训练也属于一场已结束关联训练，按现有 finishedAt 规则参与轮转；若要排除零组训练，需另行改变已明确的规则，本计划不暗改。

「换一个计划」只影响**这次开训前的本地选择**；选择后不创建训练、不推进轮转。真正开始时一次写入该 template_id；完成后下一次从它的下一套开始。取消选择、只浏览或启动失败均不推进。进行中训练不提供一键替换整份动作清单。

### 2.3 删除的三种语义

| 操作 | 数据后果 | 必需提示 |
|---|---|---|
| 删除计划 | 删除计划 / 计划动作；所有引用它的 session.template_id 置 NULL；训练和组保留 | 写明训练仍在，只解除关联 |
| 删除训练 | 仅删除明确 id 的 session，子动作 / 组由外键级联 | 日期、已记组数、对进步数据的影响、无法撤销 |
| 移除本场动作：删记录 | 删该 session_exercise 及组，重排剩余顺序 | 已完成 N 组时明确「删掉这 N 组」 |
| 移除本场动作：保留记录 | 删除该动作未完成占位组，取消其进行中休息，保留已完成组与 session_exercise | 显示「保留已记组，本次不再继续此动作」 |

未完成过任何组的动作可直接移除；有组时三个选择为「删掉这 N 组」「保留已记组」「取消」。**记录页只剩一个可继续动作时，不显示移除按钮，controller 同样拒绝绕过 UI 的最后一项移除。**整场删除是独立确认，不受该限制。

### 2.4 数据与兼容

- 所有写入参数化、单操作事务；事务内只用 tx，不用外层 Database。
- 当前 `session.template_id` 没有外键声明，删除计划必须主动置空，覆盖历史和正在进行的训练。
- 列表按 `position ASC, rowid ASC`，最近训练按 `started_at DESC, rowid DESC`。
- 备份已有并列 position 时，读取保留 rowid 次序；只有用户执行保存 / 移动 / 删除时才重排为连续位置，启动时不悄悄改备份内容。
- 不删 exercise 动作库记录、不篡改保留组的重量 / 次数 / 休息、不自动结束其他活动训练。
- SQL 成功后只发一次数据变更通知；提交后 UI 刷新失败与事务失败分别提示。
- 不清空用户主包；真机删除验收只在 `.acceptance` 包。

## 3. 目录与契约

| 文件 | 职责 |
|---|---|
| Create `lib/domain/plans.dart` | SplitTemplate、TemplateExercise、TemplateDraft / Detail / Summary |
| Create `lib/domain/rotation.dart` | nextTemplateIndex 纯函数 |
| Create `lib/domain/exercise_visibility.dart` | 从完整训练中推导可继续动作及选择回退规则 |
| Create `lib/domain/record_management.dart` | 整场删除预览 / 结果的纯值对象 |
| Create `lib/data/repositories/template_repo.dart` | 原子保存 / 删除 / 移动、一次聚合列表 |
| Create `lib/data/repositories/workout_plan_repo.dart` | 读取下一套和首次开训写入所需快照 |
| Create `lib/data/repositories/record_management_repo.dart` | 单场 / 单动作预览、精确删除 / 保留组 |
| Modify `lib/data/repositories/session_repo.dart` | 新增最近已完成计划 id 查询；同位置列表加 rowid 兜底 |
| Modify `lib/state/active_session_controller.dart` | 原子开训、完整 / 可继续动作分离、移除后焦点 |
| Create `lib/state/plan_controller.dart` | 草稿、保存、移动、删除计划、busy 与冲突 |
| Create `lib/state/record_management_controller.dart` | 删除确认、提交后内存 / 路由刷新 |
| Create `lib/features/plans/{plan_list_page,plan_editor_page,plan_picker}.dart` | 有序计划管理 / 编辑 / 换本次计划 |
| Create `lib/features/history/delete_session_dialog.dart` | 写明后果的整场确认 |
| Create `lib/features/workout/remove_exercise_dialog.dart` | 两种移除语义与取消 |
| Modify 设置、训练首页、记录页、动作条、历史列表 / 详情 | 入口、计划卡片、移除、刷新 |
| Modify `lib/app/{router,providers}.dart` | 新 provider / 路由，原 router 不重建 |
| Existing `lib/state/data_revision.dart` | 3B 交付的通用刷新；不得假定当前代码已有 |
| Create `scripts/browser_plans_smoke.mjs` | 真实点击轮转 / 删除 / 备份往返 |

### 3.1 领域类型

`plans.dart` 的固定字段如下，列表一律 immutable：

```dart
class SplitTemplate {
  final String id;
  final String name;
  final int position;
  final int createdAt;
  const SplitTemplate({required this.id, required this.name,
      required this.position, required this.createdAt});
}

class TemplateExercise {
  final String id;
  final String templateId;
  final String exerciseId;
  final int position;
  const TemplateExercise({required this.id, required this.templateId,
      required this.exerciseId, required this.position});
}

class TemplateSummary {
  final SplitTemplate template;
  final int exerciseCount;
  const TemplateSummary(this.template, this.exerciseCount);
}

class TemplateItem {
  final TemplateExercise entry;
  final String exerciseName;
  final bool isArchived;
  const TemplateItem(this.entry, this.exerciseName, this.isArchived);
}

class TemplateDetail {
  final SplitTemplate template;
  final List<TemplateItem> exercises;
  final String editToken;
  TemplateDetail(this.template, List<TemplateItem> exercises, this.editToken)
      : exercises = List.unmodifiable(exercises);
}

class TemplateDraft {
  final String? id;
  final String name;
  final List<String> exerciseIds;
  final String? expectedToken;
  TemplateDraft({this.id, required this.name,
      required List<String> exerciseIds, this.expectedToken})
      : exerciseIds = List.unmodifiable(exerciseIds);
}
```

新建草稿 id / token 为 null；现有详情编辑必须带 editToken。重复 exerciseId 合法，不能把 exerciseIds 变成 Set。

### 3.2 接口清单

| 模块 | 接口 |
|---|---|
| rotation.dart | `int? nextTemplateIndex(List<String> orderedIds, String? lastTemplateId)` |
| template_repo.dart | `Future<List<TemplateSummary>> listTemplates(SqlExecutor exec)` |
| template_repo.dart | `Future<TemplateDetail?> getTemplate(SqlExecutor exec, String id)` |
| template_repo.dart | `Future<List<TemplateSummary>> readTemplates(SqlExecutor tx)` / `Future<TemplateDetail?> readTemplate(SqlExecutor tx, String id)`：持有事务时使用，不再开事务 |
| plans.dart | `String templateOrderToken(List<TemplateSummary> ordered)`：固定顺序 JSON 保存 id / position，移动前后用同一契约 |
| template_repo.dart | `Future<TemplateDetail> saveTemplate(SqlExecutor exec, TemplateDraft draft)` |
| template_repo.dart | `Future<bool> moveTemplate(SqlExecutor exec, String id, int direction, String expectedOrderToken)`，direction 仅 -1 / 1 |
| template_repo.dart | `Future<TemplateDeletePreview?> inspectTemplateDeletion(SqlExecutor exec, String id)` |
| template_repo.dart | `Future<TemplateDeleteResult> deleteTemplate(SqlExecutor exec, TemplateDeletePreview preview)` |
| session_repo.dart | `Future<String?> findLatestTemplateId(SqlExecutor exec)` |
| workout_plan_repo.dart | `Future<PlannedWorkout> loadNextWorkout(SqlExecutor exec, {String? preferredTemplateId})` |
| workout_plan_repo.dart | `Future<PlannedWorkout> readPlannedWorkout(SqlExecutor tx, {String? preferredTemplateId})`：事务内只读版本 |
| record_management_repo.dart | `Future<SessionDeletePreview?> inspectSessionDeletion(SqlExecutor exec, String id)` |
| record_management_repo.dart | `Future<SessionDeleteResult> deleteSession(SqlExecutor exec, SessionDeletePreview preview)` |
| record_management_repo.dart | `Future<void> deleteSessionExercise(SqlExecutor tx, String sessionExerciseId)`，调用方持有事务 |
| record_management_repo.dart | `Future<void> retainCompletedSets(SqlExecutor tx, String sessionExerciseId)`，调用方持有事务 |

`PlannedWorkout` 含 `String? templateId`、`String? name`、`List<String> exerciseIds`、`String selectionToken`；不创建训练。

`TemplateDeletePreview` 含目标 id / 名字、动作数、已结束 / 活动训练引用数和目标快照 token；result 含 deleted、detachedCompleted、detachedActive。`SessionDeletePreview` 含 session、completedSets、pendingSets、目标 session 与子记录快照 token；result 含 deleted、sessionId、wasActive。这些 preview 仅由 inspect 生成，不用页面拼计数。

类型归属：SplitTemplate、TemplateExercise、Summary / Item / Detail / Draft、PlannedWorkout、TemplateDeletePreview / Result 均在 `domain/plans.dart`；SessionDeletePreview / Result 在 `domain/record_management.dart`，引用既有领域 WorkoutSession。ExerciseRemovalPreview 与 RemoveExerciseChoice 在活动训练 controller 中定义，页面消费 state 契约。不得让 domain 反向依赖 controller 或仓储。

预览 token 为固定字段顺序 JSON，不用随机 hashCode。对目标内容做并发复核；其他无关训练改变不应阻止删除目标，但目标在确认期间新增组必须重新确认。

## Task 0：基线与旧数据 fixture

**Files:** Create `test/fixtures/plans/`，新建测试辅助 `test/support/plan_fixtures.dart`；只读核对 schema、备份和 3B DataRevision。

- [ ] **Step 1：保留现场。** git status / log，记录实际测试基线；用户文件不动，不将当前主包用来做删除测试。
- [ ] **Step 2：准备真实 v4 fixture。** 计划 A / B / C，重复同一动作、一个空计划、归档动作、两个并列 position；训练含已结束关联 / 未关联、活动训练和占位组。
- [ ] **Step 3：存一份合法旧 v2 备份。** 有非空计划与 session.templateId，先证明现有 3A 能恢复，执行本期后仍能原样重导出。
- [ ] **Step 4：验证没有新表需求。** 检查 v4 表和列；若契约有缺口，先改计划说明，不偷偷修改 v4 / v3。
- [ ] **Step 5：运行现有全量测试。** 此时只核实基线，不提前把未来任务勾选。

## 4A：计划管理与轮转

## Task 1：计划类型、纯轮转与查询

**Files:** Create `lib/domain/plans.dart`、`lib/domain/rotation.dart`；Modify `session_repo.dart`；Test `test/domain/rotation_test.dart`、`test/data/plan_history_test.dart`。

纯轮转完整实现：

```dart
int? nextTemplateIndex(List<String> orderedIds, String? lastTemplateId) {
  if (orderedIds.isEmpty) return null;
  return (orderedIds.indexOf(lastTemplateId ?? '') + 1) % orderedIds.length;
}
```

最近已完成关联计划查询：

```sql
SELECT template_id
  FROM session
 WHERE finished_at IS NOT NULL AND template_id IS NOT NULL
 ORDER BY started_at DESC, rowid DESC
 LIMIT 1;
```

- [ ] **Step 1：失败测试锁边界。** 空列表 null；A/B/C 无上次→A、A→B、C→A；唯一计划永远它；已删 id→A。
- [ ] **Step 2：实现领域类型和纯函数。** 不读时钟、不读数据库、不写 settings。
- [ ] **Step 3：查询真实 SQLite。** 更晚的无模板训练和活动训练均不能盖掉上次已结束模板；同毫秒逆序 ID 由 rowid 决定。
- [ ] **Step 4：验证只读查询的空库和悬挂历史容错。** 返回的旧 id 由纯轮转函数落回第一项，不在查询中更新历史。需要计划仓储的 loadNextWorkout 在 Task 2 完成后接入，避免依赖尚未创建的模块。
- [ ] **Step 5：验证与提交。** `flutter test --no-pub test/domain/rotation_test.dart test/data/plan_history_test.dart`；提交 `feat(plans): derive rotation from completed sessions`。

## Task 2：原子保存、移动与删除计划仓储

**Files:** Create `lib/data/repositories/template_repo.dart`、`lib/data/repositories/workout_plan_repo.dart`、`test/data/template_repo_test.dart`、`test/data/workout_plan_repo_test.dart`。

### 2.1 读

listTemplates 用一次 `LEFT JOIN + COUNT + GROUP BY` 取动作数，空计划不消失；按 t.position / t.rowid。getTemplate 取模板，再一次 JOIN 读取动作名和归档状态，按 te.position / te.rowid；不存在返回 null。不让页面逐个查询动作名。

公开 listTemplates / getTemplate 用 transaction 包装只读快照；对应 readTemplates / readTemplate 仅用传入的 tx，不再开事务。save / move / delete 和 workout_plan_repo 在事务内只调用这些 read 版本。

loadNextWorkout 同样包装事务，内部调用 readPlannedWorkout；后者组合 readTemplates、findLatestTemplateId 与 readTemplate。无计划时复制最近已结束场动作，有计划时保留重复 / 归档项，preferred 不存在明确失败。其 selectionToken 覆盖有序计划、所选计划内容及用于轮转的最近已结束关联训练；不包含浮动时钟或进行中时长。

### 2.2 保存

saveTemplate 在一个事务内校验名字非空、引用动作存在；已有 id 必须存在且 editToken 与当前内容相同。新建取当前最大 position+1，保存 name、计划动作及连续位置。动作行每项生成独立 UUID，重复动作不共用主键。空清单合法。

名称与动作清单一起保存，不能先 rename 提交、后覆盖动作失败；编辑已删除的旧 id 不应静默重新创建。取消草稿没有数据库副作用。

### 2.3 移动

先读有序 IDs，复核 expectedOrderToken；用 id 找当前位置，越界 / 无变化返回 false。交换相邻项后依序 `UPDATE ... SET position=? WHERE id=?`。不要用 `WHERE position=?`，旧备份允许并列 position，那会一次移动多条。

```sql
UPDATE split_template SET position = ? WHERE id = ?;
```

### 2.4 删除

inspect 显示将解除的历史 / 活动引用数量。delete 事务内复核目标与引用快照，再执行：

```sql
UPDATE session SET template_id = NULL WHERE template_id = ?;
DELETE FROM split_template WHERE id = ?;
```

template_exercise 靠已开启的外键级联；其他计划按原稳定顺序重新编号。训练、组、name、note 和活动训练均保留。目标已经不存在返回 deleted=false；目标 / 引用在确认期间变化则要求重新确认。

- [ ] **Step 1：失败测试包含完整表快照。** 旧计划加载、空计划计数、重复动作、并列位置移动、取消草稿不新增。
- [ ] **Step 2：实现三种写事务。** 不调用会自行开事务的公共函数造成嵌套；事务内只用私有 tx helper。
- [ ] **Step 3：注入保存删除后 / 第 2 项插入 / 解除引用后 / 重排行中失败。** 计划、关联训练和其他表全部回到操作前。
- [ ] **Step 4：校验删除后仍可导出合法 v2。** 无悬挂 templateId，训练组值保持。
- [ ] **Step 5：接入只读下一套选择并测试无副作用、非法 override、重复动作与旧 fallback。** 在已有事务中调用 readPlannedWorkout 不得出现嵌套事务。
- [ ] **Step 6：`flutter test --no-pub test/data/template_repo_test.dart test/data/workout_plan_repo_test.dart test/data/backup_repo_test.dart`。** 提交 `feat(plans): persist ordered templates transactionally`。

## Task 3：计划列表、草稿编辑和冲突提示

**Files:** Create `lib/state/plan_controller.dart`、`lib/features/plans/plan_list_page.dart`、`lib/features/plans/plan_editor_page.dart`；Modify settings、router、providers；Test `test/state/plan_controller_test.dart`、`test/widget/plan_pages_test.dart`、`test/app/router_test.dart`。

### 3.1 入口与路由

- 设置增加「训练计划」入口。
- `/plans`：列表、动作数、上移下移、编辑、新建。
- `/plans/new`：本地新草稿；`/plans/:id/edit`：已存草稿，new 显式静态路由先定义。
- 页面在 ShellRoute 外，真实点击用 push，可返回；不存在 id 显示「这个计划不存在」并保留返回 / 列表入口。

### 3.2 草稿与状态

PlanController 管 loadList、loadDraft、updateName、addExercise、removeDraftItem、moveDraftItem、saveDraft、movePlan、previewDelete、confirmDelete；公开 busy / dirty / draft / message，只通过方法修改。

复用 showExercisePicker，多次选择相同动作生成不同草稿项 key；不能把 key 当 exerciseId。上移 / 下移按钮按数组项索引操作草稿，保存前不写库。离开 dirty 草稿时可继续编辑或丢弃；没有 dirty 就直接返回。

editToken 冲突提示「计划已变化，请重新载入」；保留本地输入给用户阅读，不自动覆盖远端或覆盖备份恢复后的新计划。写入中禁用重复保存和退出，异常释放 busy。

### 3.3 界面测试

- [ ] 真实点新建→改名→选动作→保存，数据库只在保存后变化。
- [ ] 两个相同动作都显示 / 可单独移动，保存后仍两项。
- [ ] 改名、清单、位置一次成功；失败后数据库旧数据完整，本地草稿可重试。
- [ ] 删除计划对话框写明关联训练保留；取消不写，确认后列表与首页更新。
- [ ] 导入旧计划不自动重建 UUID 或改位置；首次打开不写库。
- [ ] 大字号、键盘、长列表可滚动，最后一项的操作可达。
- [ ] 完成状态 / UI / 路由测试后提交 `feat(plans): add template list and draft editor`。

## Task 4：按计划原子开训与首页下一套

**Files:** Modify `active_session_controller.dart`、`workout_home_page.dart`、`session_repo.dart`；Create `lib/features/plans/plan_picker.dart`；Test `test/state/planned_workout_test.dart`、`test/widget/workout_plan_home_test.dart`、既有旅程测试。

### 4.1 顺序与事务边界

`startNew` 扩展可选 `preferredTemplateId`、`expectedSelectionToken`；StartResult 增加 busy / planChanged，原 started / conflict 保持。默认无 override 为自动轮转。

1. 防重复点击 guard，先 resume 探冲突；有活动 session 立即返回 conflict，不读取 / 写入新训练。
2. 开一个事务，**再次**确认没有活动训练；调用 readPlannedWorkout(tx) 读取最新计划和最近已完成 templateId，生成选择；不在 tx 内调用 loadNextWorkout。
3. 与首页预览 token 不一致则返回 planChanged，不创建 session；让用户重看卡片。
4. 定完计划后创建 session，name 默认计划名，template_id 一次写入；无计划沿用旧 fallback。
5. 依计划项顺序创建 session_exercise 与第一条未完成组；默认数值继续用 getLastPerformance，同动作重复项独立建行。
6. 全部写入提交后才更新 controller / 导航；任何写失败都无半场训练。

现有 `_previousSessionExerciseIds`、`_addExerciseWithFirstSet` 直接使用 `_exec`，必须改为接收执行上下文并传 tx；事务内不能再调用外层 `_exec`，否则可能死锁。createSession 可增加可选 startedAt 给固定时钟测试使用，默认行为保持。

### 4.2 首页与本次换计划

有计划显示「下一次：推日 · 第 1 / 3 套」及动作摘要，点开始直接开，不每次询问。换计划 sheet 只选择本次 preferred id，不写库；关闭或换页后可回到自动方案。活动训练存在时优先显示继续，开始新的仍经过原三选冲突流程。

已开始的动作清单是计划的一份快照，后续改计划、删计划、调顺序不能覆盖正在练的 session_exercise / 组。删计划时仅刷新活动 session 的 templateId 元数据。

- [ ] **Step 1：失败测试先锁调用顺序。** 冲突时没有新增任何 SQL 写入，计划选择发生在 createSession 前。
- [ ] **Step 2：事务化开训。** 第 2 个动作插入失败，session 与第 1 动作 / 组都回滚；controller 不宣称已开始。
- [ ] **Step 3：防并发。** 两次同时 startNew，最多一场活动训练；busy 结果不会导航到 null session。
- [ ] **Step 4：实际轮转。** A→结束→B→结束→C→结束→A；开始但不结束不推进；结束零组计划场按明确规则推进。
- [ ] **Step 5：插入无模板 CSV / 补记后轮转不变；删除上一关联计划或调整计划顺序后按最新列表计算。**
- [ ] **Step 6：完成后但内存重载失败时保留已创建训练，提示重新进入继续；不自动 startNew 再造一场。**
- [ ] **Step 7：`flutter test --no-pub test/state/planned_workout_test.dart test/widget/workout_plan_home_test.dart test/e2e/journey_test.dart`。** 提交 `feat(workout): start the selected split atomically`。

## 4B：记录删除与保留已完成组

## Task 5：精确删除仓储与稳定重排

**Files:** Create `lib/domain/record_management.dart`、`lib/data/repositories/record_management_repo.dart`、`test/data/record_management_repo_test.dart`；Modify session / set 仓储的同位置排序查询。

### 5.1 整场

inspectSessionDeletion 在读取事务中取得目标、完整子记录和已完成 / 占位组数；token 不含会随时间变化的「当前时长」。deleteSession 在事务中复核目标 token，使用 `DELETE FROM session WHERE id=?`，由外键级联。不能用否定条件、NOT IN 或复制整库重建来删一场。

如果确认期间用户又完成一组，计数和 token 变化，必须重新确认；目标已经删除时安全返回 deleted=false，不把它误当别的训练。

### 5.2 单动作硬删除

目标的父 session 和顺序必须从数据库查询，不相信界面提交的 position：

```sql
DELETE FROM set_entry WHERE session_exercise_id = ?;
DELETE FROM session_exercise WHERE id = ?;
```

然后按旧 `position ASC, rowid ASC` 读取该场剩余项，用 id 逐项写 `0..n-1`。这比对所有 `position > oldPosition` 减一更能处理旧备份的并列位置；不影响其他训练。

### 5.3 保留已完成组

```sql
DELETE FROM set_entry
 WHERE session_exercise_id = ? AND is_completed = 0;
UPDATE set_entry SET rest_started_at = NULL
 WHERE session_exercise_id = ? AND rest_started_at IS NOT NULL;
```

保留已经写入的 rest_seconds 原值，不为移除动作把最后一段休息转成测量值；不删除 session_exercise，不重排该行到历史别处。其不再有未完成组，所以能从记录页隐藏，历史 / 总结 / 进步仍读取全部已完成组。

- [ ] **Step 1：失败用例。** 删除单场只删目标与子表，另一场、动作库、计划、偏好不变；已删除 id 再执行无异常。
- [ ] **Step 2：动作归属检查。** 仓储取得真正 parent，不能用伪造 sessionId 删到其他训练或移动其他场顺序。
- [ ] **Step 3：事务验证。** 删除组后 / 删除动作后 / 重排中间抛错，全部数据回到前值。
- [ ] **Step 4：保留组分支。** 已完成 3 组 + 占位 1 组→剩 3 组，weight / reps / completedAt / 已测 rest 不变，进行中休息已取消。
- [ ] **Step 5：重排包含并列 position。** 余项按稳定读取顺序连续编号，而非只对数字减一。
- [ ] **Step 6：`flutter test --no-pub test/data/record_management_repo_test.dart`。** 提交 `feat(records): delete exact records transactionally`。

## Task 6：完整动作、可继续动作与焦点

**Files:** Create `lib/domain/exercise_visibility.dart`；Modify `active_session_controller.dart`、`record_page.dart`、`exercise_strip.dart`；Test `test/domain/exercise_visibility_test.dart`、`test/state/remove_exercise_test.dart`、`test/widget/remove_exercise_test.dart`。

### 6.1 固定状态契约

不能在 `_loadExercises` 直接丢掉「保留已记组」行，否则首页组数、结束时休息、总结都会漏数据。采用：

| 字段 / getter | 含义 |
|---|---|
| `exercises` | 全部当前训练动作及组，继续用于描述 / 总组数 / 全场休息处理 |
| `recordingExercises` | 其中至少有一条未完成组的动作，记录页与动作条使用 |
| `currentSessionExerciseId` | 以数据库 id 固定当前目标，不能仅靠会变化的数组下标 |
| `currentIndex` | 当前 id 在 recordingExercises 的位置，供动作条使用 |
| `currentExercise` | 当前可继续动作，没有则 null |

`completeCurrentSet`、`beginNextSet` 与记录页 `_pendingOf` 必须改用 currentExercise；`_findAnyResting` 仍检查完整 exercises。所有 `exercises[currentIndex]` 调用点逐个检索迁移，不能只改动作条。

隐藏只从 SQLite 的「没有未完成组」推导，不能持久化到另一份 hiddenIds；强杀 / 备份恢复后仍得到同一结果。新加一个同动作可产生新的 session_exercise，不把先前已记组删掉。

领域函数只能接最小形状，不 import state/ActiveExercise。controller 将完整数据映射后调用：

```dart
List<String> recordingExerciseIds(
  List<({String id, bool hasPending})> entries,
) => entries.where((e) => e.hasPending).map((e) => e.id).toList();

String? resolveRecordingSelection(
  List<String> visibleIds, String? selectedId, int previousIndex,
) {
  if (visibleIds.isEmpty) return null;
  if (selectedId != null && visibleIds.contains(selectedId)) return selectedId;
  return visibleIds[previousIndex.clamp(0, visibleIds.length - 1).toInt()];
}
```

### 6.2 纯选择回退

保存移除前可见索引；操作后若原选中 id 仍可见就保持，若已移除则选 `min(oldIndex, newLength-1)`，空列表选择 null / index 0。恢复时最后完成组属于隐藏动作，就选第一条有未完成组的动作，而不是卡在已隐藏的 id。

### 6.3 state 操作

先用 `Future<ExerciseRemovalPreview?> previewExerciseRemoval(String sessionExerciseId)` 读取确认信息；preview 在 state 定义，含 sessionId、sessionExerciseId、completedSets、visibleCount 和父 / 目标组快照 token，构造入口受限。之后调用 `Future<bool> removeExercise(ExerciseRemovalPreview preview, RemoveExerciseChoice choice)`；choice 为 deleteRecorded / keepRecorded / cancel。

每次在 state 检查当前训练仍存在且未结束、目标归属、可见动作数 >1；写入事务重读这些前提并比较 token。确认期间目标从 3 组变为 4 组时要求重新确认，不能只重新数一遍然后直接删。UI 只展示选择，不独自决定能否写库；取消不进入删除事务。

提交后重读完整 exercises、重新选择，并让 RecordPage 调 `_syncFromPending`。否则删掉 50 kg 动作后切到 20 kg 动作，界面仍可能把旧的 50 kg 写进新动作。

- [ ] **Step 1：失败测试覆盖末项与越界。** 首 / 中 / 末项、当前 / 非当前移除、最后一项通过 controller 也不能删。
- [ ] **Step 2：保留记录验证。** 原始组完整存在，总结和进步容量不减少，但 recordingExercises 不再含该行。
- [ ] **Step 3：恢复验证。** 强杀 / reset / resume 后仍隐藏，没有内存 Set；最后完成组是隐藏项时焦点正确。
- [ ] **Step 4：休息验证。** 保留分支取消该项进行中休息，不污染其他动作休息，不伪造秒数。
- [ ] **Step 5：真实点按钮删除当前项。** 新焦点显示正确重量 / 次数，下一次完成写到正确 sessionExerciseId。
- [ ] **Step 6：空可继续列表防御。** 来自旧备份的全完成活动训练只显示添加 / 结束入口，不出现可点但无反应的完成按钮。
- [ ] **Step 7：`flutter test --no-pub test/domain/exercise_visibility_test.dart test/state/remove_exercise_test.dart test/widget/remove_exercise_test.dart test/state/complete_set_test.dart`。** 提交 `feat(workout): remove exercises without losing kept sets`。

## Task 7：整场删除编排与界面

**Files:** Create `lib/state/record_management_controller.dart`、两个确认对话框；Modify history 列表 / 详情、record_page、providers；Test `test/state/record_management_controller_test.dart`、`test/widget/delete_session_test.dart`、router 测试。

### 7.1 入口

- 历史详情 AppBar 菜单「删除这场训练」；列表仍点击进详情，不以无提示滑动直接删除。
- 记录页菜单也可删除当前活动训练，空训练同样可删；必须显示其正在进行。
- 动作条移除入口对应 Task 6，不与整场删除共用容易混淆的一个按钮。

确认示例：「删除 10月16日 19:30 的训练？这场训练和已记的 12 组会消失，相关进步数据将重新计算。此操作无法撤销。」有未完成占位组时可补说明，不把占位算作已记组数。取消为默认安全操作，提交期间禁重复 / 返回。

### 7.2 提交后处理

只有 SQL 提交成功后才更新内存。删掉的 id 等于 ActiveSessionController.session.id 时 reset 并回首页；删除其他训练不得 reset 当前训练。

成功发 DataRevision.changed。历史详情关闭并返回列表；进步列表和动作详情重新取数；已有详情路由再次访问显示「这场训练不存在」且能返回。删除最新计划训练后下次轮转按剩余历史重新计算，不补写游标。

数据库失败保留原状态并提示未删除；SQL 已成功但刷新失败提示「记录已删除，请重新打开查看」，不自动重试删除其他项。

- [ ] **Step 1：先写取消、双击、已删除、目标确认期间变化的测试。**
- [ ] **Step 2：实现 controller 与具体目标 preview。** busy / disposed 处理复用模式，不把 Widget 的 context 存在 controller。
- [ ] **Step 3：实际历史点击到详情→取消→确认删除→返回。** 数据量与路由变化来自真实 onTap，不在测试直接 router.go 伪造链路。
- [ ] **Step 4：活动训练删除后无继续卡、旧记录页无法再写组；删除其他历史时当前 session、重量草稿和组数保持。**
- [ ] **Step 5：删除一个 PR 所在训练后，e1RM / 最重 / 容量和日期从剩余事实重新计算，不保留旧高亮缓存。**
- [ ] **Step 6：运行 controller / widget / router / progress 回归并提交 `feat(records): confirm session deletion and refresh views`。**

## Task 8：跨功能、变异与浏览器验收

**Files:** Create `test/e2e/plans_and_deletion_test.dart`、`scripts/browser_plans_smoke.mjs`；更新已有驱动只增加本期场景，不删除旧断言。

### 8.1 端到端矩阵

| 场景 | 必须成立 |
|---|---|
| 旧 v2 恢复非空计划→列表→按计划开始 | 不丢计划 / 顺序，初始组正确 |
| A/B/C 轮转中间插入 CSV / 补记 | 无模板训练不推进关联轮转 |
| 开 A→改 A 的清单 / 名字 | 当前训练快照不变，后续训练使用新清单 |
| 开 A→删 A | 当前训练及组保留，templateId=NULL |
| 删除最近已结束计划训练 | 轮转由剩余已完成关联历史推导 |
| 保留 3 组隐藏动作→强杀→继续 | 隐藏仍在，历史 / 总结仍有 3 组 |
| 硬删动作→完成新焦点组 | 重量、目标 ID、容量正确 |
| 删 PR 场→查看三张卡 | 值 / 来源 / 日期 / 稀疏或空态正确 |
| 计划移动含并列 position | 不移动错行，重排连续，备份顺序一致 |
| 各种删除后导出→独立空库恢复 | 引用完整、计数与剩余记录一致 |

### 8.2 变异验证

| 临时破坏 | 应变红用例 |
|---|---|
| 最近计划查询漏 finished_at | 活动训练不推进轮转 |
| 漏 template_id 非空过滤 | CSV / 自由训练插入后仍轮转 |
| 漏 rowid 兜底 | 同毫秒逆序 ID |
| 开训事务移除 | 第 2 动作插入失败仍无半场训练 |
| 删计划不解除 templateId | 备份引用检查 / 训练保留测试 |
| 移动按 position 改行 | 并列 position 不误动其他计划 |
| 保留分支删 completed 组 | 历史容量不减少 |
| 保留分支不删占位组 | 强杀后隐藏仍生效 |
| 不同步 currentExercise / 编辑值 | 删除 50 kg 后新 20 kg 组写入正确 |
| 取消仍调用删除 | 取消前后快照相同 |
| 删除其他历史也 reset | 当前活动训练保持 |

逐条保留实际 Expected / Actual，原文恢复后再跑对应测试。不要用 git reset / restore 覆盖本期尚未提交的正常实现。

### 8.3 浏览器真实操作

新驱动从设置真实创建 A / B / C、加入重复动作和空计划、上移下移；从首页换本次计划、开训、结束并核对下一套。随后实际删除训练与动作的两个分支，检查 UI、历史 / 进步与下载备份中的底层值。

每条链路先取消一次，再确认，证明预览 / 对话框之前无写入。使用单独 origin / profile，不污染人工开发数据。截图与 results.json 中记录每条场景和 runtime errors；不能用直接 SQL 操作代替按钮验收。

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
. .\scripts\env.ps1
dart format lib test
flutter analyze --no-pub
flutter test --no-pub --reporter expanded
flutter build web --no-pub
node scripts/browser_smoke.mjs
node scripts/browser_backup_smoke.mjs
node scripts/browser_import_smoke.mjs
node scripts/browser_plans_smoke.mjs
```

上述四份浏览器驱动分别对应旧训练、备份、3B 导入、本期计划与删除；任何回归失败都先排查，不以新增功能通过抵消旧功能失败。

## Task 9：Android、交付与计划回填

### 9.1 独立包真机清单

沿用现有 GYM_ACCEPTANCE_BUILD=1 → `.acceptance`，`adb install --user 0 -r`，驱动目标设置 GYM_ACCEPTANCE_PACKAGE。保存到 `build/acceptance/phase4-<时间>/`，只操作该测试包。

| 编号 | 手工 / ADB 实际路径 | 通过标准 |
|---|---|---|
| P1 | 从旧 v2 备份恢复计划 | 列表与原计划 / 动作顺序一致 |
| P2 | 新建、改名、加重复动作、上下移动、取消草稿 | 保存原子，取消不留行 |
| P3 | A→B→C→A 连续开训结束 | 每场正确预填，开始未结束不推进 |
| P4 | 有活动训练时点击开始 | 原冲突选择仍有效，最多一场活动 |
| P5 | 换本次计划 / 取消选择 | 选择未开始不改历史；完成后从所选后继轮转 |
| P6 | 编辑 / 删除正在使用的计划 | 当前训练组保留，删除只解除关联 |
| D1 | 无组动作直接移除、有组硬删、保留、取消 | 各自后果正确，最后一可继续动作不能移除 |
| D2 | 保留组后强杀 / 重启 | 记录页仍隐藏，总结 / 历史仍有组 |
| D3 | 删除焦点动作，再完成新组 | 新目标重量 / 次数正确，屏幕无假死 |
| D4 | 历史删一场，活动删一场 | 指向明确目标，首页 / 详情 / 继续状态正确 |
| D5 | 删除最高成绩来源训练 | 三张卡立即从剩余数据计算，空态能返回 |
| B1 | 删除后备份 / 恢复到空独立库 | 无孤儿引用，剩余数据一致 |

设备没连或无授权时记录未执行；不要求用户为了计划写作先连接手机。正式实施到该阶段才需要设备。

### 9.2 构建和清理

1. 独立包测试完只卸载 `com.mobis.gym_tracker.acceptance`。
2. 清除当前 shell 的 GYM_ACCEPTANCE_BUILD / GYM_ACCEPTANCE_PACKAGE，重建默认 debug 和 release。
3. aapt 核对主包名 `com.mobis.gym_tracker`，记录大小、SHA-256、构建时间与测试源码提交。
4. 主应用数据不作为故障注入对象；本期计划本身不授权清理真实训练。

### 9.3 提交与完成定义

- [ ] 回填每个任务的命令、实际结果、变异失败信息和未运行项。
- [ ] README 写清计划只存清单、轮转依据、删除不可撤销、保留组与删除组的区别。
- [ ] schema 仍为 v4、备份 version 仍为 2；无多余迁移、轮转游标或隐藏状态表。
- [ ] `git diff --check`；明确文件清单分批提交，用户 `.claude/settings.local.json` / `.tmp/` 排除，build 大证据不入库。
- [ ] 全量旧功能、3A、3B 与本期单元 / 界面 / 端到端测试全部通过。
- [ ] 真实浏览器与 Android 表内项目有记录；全部完成才标 Phase 4 完成。

| 完成条件 | 任务 |
|---|---|
| 已导入计划无损加载、新建编辑移动删除原子 | 0、2–3 |
| 轮转、无计划 fallback、冲突优先、原子开训 | 1、4 |
| 删除只针对指定数据，失败全回滚 | 2、5、7 |
| 保留已记组后强杀仍能正确继续 | 6、8–9 |
| 焦点、权重草稿、最后一项保护无遗漏 | 6–7 |
| 历史 / 进步 / 下次预填 / 备份与删除后一致 | 7–9 |
| 格式、静态、全量、变异、Web、Android 均实测 | 8–9 |

## 需求覆盖自查

仅清单与顺序 → 2–3；最近已结束关联轮转 → 1、4；无计划 fallback → 4；冲突第一步 → 4；重复动作 / 旧位置并列 → 0、2、6；整场删除及提示 → 5、7；删除与保留分支 → 5–6；最后一项 / 索引 → 6；取消不写 / 失败回滚 → 2、5、7；备份兼容 / 旧迁移 → 0、8–9；真实平台与记录 → 8–9。

2026-10-16 已接入计划管理、轮转、记录删除与动作移除，DataRevision 和相应 controller / 界面已存在。实际完成度以 [执行记录](./2026-10-16-phase3b-phase4-execution.md) 为准；Android 真机项目未执行，不标整期验收完成。
