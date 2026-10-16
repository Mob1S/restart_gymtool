# 训练操作效率改进 Implementation Plan

> **For agentic workers:** 按本文任务逐项实施，每项完成失败用例、实现、定向验证和独立复核后再进入下一项。步骤使用未勾选清单追踪。编写阶段只交付计划；后续实施已获用户授权，实际结果见实施更新和执行记录。
>
> **实施更新（2026-10-16）：** 已获得用户实施授权；Tasks 1–10 的功能与回归完成。Task 11 的自动化、Web 和主包构建结果见 [执行记录](2026-10-16-workout-efficiency-execution.md)，Android 真机未执行。下文未勾选的“先失败测试 / 分任务提交”是未逐项执行的过程步骤，不把它们伪记成已执行；实现与实际测试位置以执行记录为准。
>
> **日期：** 2026-10-16（Asia/Shanghai）
>
> **范围依据：** 用户认可第 1、3、4、5、7 项，并随后明确“第六项可以加进来”。第 3 项遵循用户修正：“可以调整下一组的重量，次数是做完才选定的”。
>
> **执行方式：** 本文不要求创建新聊天、派发子代理或立即执行。后续获得实施指令时，按同一代码库的实际状态接续。

**Goal:** 在现有单机健身记录流程中加入记录纠错、休息时调重、动作调重幅度、收藏与最近使用及批量选择、临时替换动作、器械设置备忘，减少训练现场的查找和重复操作。

**Architecture:** 保留“当前一组”记录页、SQLite 即时保存和正计时休息。训练写入收口到事务仓储，继续由 ActiveSessionController 编排；动作偏好采用独立表并进入新备份格式。公共动作选择器同时支持单选和多选，供训练、计划和既有补记入口复用。

**Tech Stack:** 当前项目 Flutter / Dart、Provider、SQLite（Android / FFI / Web wasm）、go_router、现有 UI tokens 与组件。已读 README 记录的工具链为 Flutter 3.47.6 / Dart 3.13.5；实施时用实际本机输出核对。本期默认不新增第三方依赖。

## Global Constraints

- 训练记录永不丢失：完成、撤销、替换等多步数据变更必须原子提交；失败后保留原记录。
- 绝不伪造数据：未完成组不进入成绩统计，未知休息留空，开始下一组不等于完成一组。
- 保留“正计时，不催促”、现有 30 分钟休息闸门、同时最多一段活动休息。
- 保留“估算 · 仅供参考”“粗略参考”“总容量（重量 × 次数）”及现有统计公式。
- 休息页只编辑下一组重量；次数仍在实际做完后由用户确认。
- 新功能按 exercise.id 或 session_exercise.id 关联，不能用动作名作主键。
- 原计划与本次训练分开；本次替换动作不修改 split_template / template_exercise，不改变 session.template_id。
- SQL 仅放 data 仓储及既有 db 层；domain 不依赖 Flutter；界面不直接访问 db。
- 已发布迁移 v1–v4 不修改；本计划新增 v5。备份导出升级为 v3，继续接受旧 v1 / v2。
- 保留单份备份 20 MiB、总记录 100,000 的现有上限；新偏好行纳入总数。
- 训练动作和组的排序补 rowid 兜底；不得假定导入数据的 position 连续或唯一。
- 真机使用主应用 com.mobis.gym_tracker 覆盖更新；遵守 README 最新约定，不再创建独立验收包。
- 原计划编写阶段仅交付文档；后续实施已由用户明确授权。Android 真机操作仍遵守本文件与 README 的主包约定。

---

## 1. 已确认范围与本计划的实施取舍

### 1.1 六项功能

| 编号 | 功能 | 本期交付 |
|---|---|---|
| 1 | 修改已完成组、撤销误点 | 当前训练已完成组可修改重量与次数；在刚完成后的休息阶段撤销最近一次完成 |
| 3 | 休息时准备下一组重量 | 休息页可调重量并保存；开始下一组沿用该重量；休息页没有次数编辑或次数目标 |
| 4 | 每个动作自己的调重幅度 | 按动作保存步长，记录页、休息页和纠错弹层使用一致步长 |
| 5 | 收藏、最近使用、批量选择 | 收藏置前；最近实际练过的动作快捷选择；训练与计划支持一次加入多个动作 |
| 6 | 本次临时替换动作 | 无成绩时直接换，有成绩时保留旧组并接上新动作；使用新动作自己的上次成绩和偏好 |
| 7 | 器械设置备忘 | 按动作保存长期备注，在训练时查看和编辑，随备份恢复 |

第 2 项“上次训练逐组参考”没有进入本轮确认范围。保留现有历史成绩预填，不另建逐组参考面板。

### 1.2 为便于落地采用的具体取舍

以下是本计划给出的实现方案，不能表述为用户逐条指定的要求：

1. 纠错先覆盖**当前进行中的训练**，包括本场已经隐藏但保留成绩的动作。结束后的历史训练仍只读；历史编辑另开范围。
2. 撤销只面向“刚才误点完成”：还在该次休息中、尚未开始后续组时可用；不做任意历史操作撤销栈。
3. 调重幅度先提供 0.5 / 1 / 1.25 / 2.5 / 5 kg 五档，默认 2.5 kg，不增加任意步长输入。
4. 最近使用最多显示 10 个不同动作，由已完成组推导；收藏不限于这 10 个。
5. 器械备忘为最多 500 个 Unicode code point 的纯文本，按动作长期保存；暂不区分多个健身房或同名器械实例。
6. 一次多选中每个动作只能选一次，按点击顺序添加；允许通过再次打开选择器，在同一训练或计划里再次添加同一动作。
7. 替换目标已在本场出现时，创建新的动作出现项，不自动合并现有组。

### 1.3 交付分批

- **A：纠错与休息调重。** 可以先独立交付；数据库仍可保持 v4 / 备份 v2。
- **B：动作偏好与快速选择。** 增加 v5 / 备份 v3；包含步长、收藏、备忘、最近使用和多选。
- **C：临时替换。** 复用 A 的事务写入与 B 的选择器、偏好，最后完成联动验收。

建议顺序 A → B → C。每批都必须能独立跑通原训练、继续训练、导出恢复流程，不留只露入口但无法使用的页面。

## 2. 当前代码核对结果

本计划以读取时 HEAD 21c41ff 为基线。工作区已有 .claude/settings.local.json 修改和 .tmp/ 未跟踪目录，后续实施不得清理、覆盖或混入提交。README 最新记录为 337 条测试通过；本轮未重跑，实施时重新记录实际基线。

| 现有文件 | 已核对事实 | 本期处理 |
|---|---|---|
| lib/features/workout/record_page.dart | 当前组大数字；完成后进入 RestView；上一组提示读的是本场成绩 | 加本场组列表、纠错入口、动作设置与替换入口 |
| lib/features/workout/rest_view.dart | 时间戳正计时，主要操作为开始下一组 | 加下一组重量控件、刚完成组摘要和撤销入口 |
| lib/state/active_session_controller.dart | 完成操作按多条写入执行；预建下一组；新增动作与首组使用私有辅助方法 | 对相关写入加统一互斥、事务与提交后刷新，抽出公共仓储辅助方法 |
| lib/data/repositories/set_repo.dart | 已有 addSet / updateSetValues / completeSet / startRest / endRest / cancelRest | 保留低层函数，业务修改走新的受保护仓储 |
| lib/features/workout/number_stepper.dart | 默认步长 2.5；加减后会对步长网格取整 | 改成相对当前值加减，避免导入重量被跳档 |
| lib/features/workout/drag_number.dart | 默认 2.5；显示固定最多一位小数；拖动也按网格取整 | 统一步长和重量格式，增加拖动结束回调 |
| lib/features/workout/exercise_picker.dart | 肌群分组、名称搜索、单选即返回、自动弹键盘 | 复用单选；增加常用区、多选提交，打开时先展示列表 |
| lib/features/plans/plan_editor_page.dart | 单次加入一个动作；计划允许重复动作 | 增加草稿批量加入，不提前写计划 |
| lib/features/import/manual_workout_form.dart | 使用同一个单选选择器 | 保持单选接口与补记行为 |
| lib/data/repositories/record_management_repo.dart | 已有保留已完成组、删除动作、整场快照 token | 复用快照校验与保留组语义；替换不得调用“最后一个动作禁止删除”的 UI 路径 |
| lib/data/db/migrations.dart | 当前 schemaVersion = 4；迁移只追加 | 在 B 批追加独立 v5 建表 |
| lib/domain/backup.dart / lib/data/repositories/backup_repo.dart | 备份 v2，校验 schema 上限 4，settings 可缺省 | 在 B 批增加偏好数据段、v3 校验和替换顺序 |
| lib/state/data_revision.dart | 已有通用变更通知 | 成功写入后通知，失败与取消不通知 |

## 3. 交互规则

### 3.1 修改本场已完成组

- 记录态和休息态都有“本场已记 N 组”入口，打开按动作分组的底部列表。
- 列表保留“本次不再继续”的动作及其成绩，因此替换后仍能修正旧动作的两组。
- 点击某组打开“修改第 N 组”，包含动作名、重量、实际次数、保存和取消。
- 重量可用该动作步长微调，也能直接输入；次数为非负整数。常规控件仍按当前范围使用，遇到旧导入的超常规值不能在打开弹层或只改另一个字段时截断原值。
- 仓储只修改 weight / reps；id、session_exercise_id、position、completed_at、rest_started_at、rest_seconds 保持原样。
- 保存后本场摘要和最终统计使用新数值；不自动把修改后的重量传播到下一组，避免覆盖已准备的重量。
- 休息时改上一组，计时不停、不归零；取消不写库。
- 如果训练已经结束、组被删除或快照变化，保留输入并提示“记录已变化，请重新打开后修改”，不写入过期编辑。

### 3.2 撤销刚才的完成

撤销入口放在休息页刚完成组摘要旁，文案“误点完成？撤销”。这是常驻次级操作，不使用几秒后消失的 SnackBar 作为唯一入口。

**允许条件必须全部成立：**

1. session.finished_at 为 NULL。
2. 目标是本场最新完成的一组，且属于当前查看的动作出现项。
3. 该组 rest_started_at 非空、rest_seconds 为空，仍处于有效休息期。
4. 该动作只有一个未完成占位组，它位于目标组之后；目标组后面没有其他已完成组。
5. 整场只有这一段活动休息；快照 token 与预览一致。
6. 30 分钟闸门已经清理的休息不再提供撤销。旧导入中不满足这些条件的状态不猜测恢复。

**单事务结果：**

- 删除自动产生的下一组占位，使用明确 pendingSetId 定位。
- 将误点的已完成组改回未完成，清空 completed_at / rest_started_at / rest_seconds。
- 保留被撤销组自己的重量、次数、id 和 position，返回这组继续记录。
- 此前已经确认并写入的其他组休息时长不变；不重建历史计时。
- 如果休息中调过“下一组重量”，该准备值随下一组占位一起撤销；入口说明“返回刚才这一组，下一组准备值将清除”。
- 重复点击只能成功一次；重启后从数据库状态判断能否撤销，不依赖内存撤销栈。
- “开始下一组”、其他组完成、结束训练或替换该动作后，原撤销入口失效。

### 3.3 休息时调整下一组重量

休息页依次展示当前动作、正计时、下一组重量、开始第 N 组；本场组列表与撤销为次级操作。

- 重量读写该动作**唯一未完成组**的 weight。不是刚完成组的重量，也不是计划目标重量。
- 休息页不显示次数控件，不写 reps，不展示“目标次数”。
- 单击加减保存一次；拖动时本地预览，松手时保存一次。保存完成前显示保存状态，不承诺尚未提交的数据已经持久化。
- 开始下一组前等待最后一次调重提交；成功后用原 endRest 口径结算休息，进入记录态。
- 做完后由用户选择实际次数，再点“完成这组”。现有次数参考值可以保留，但未完成组不属于实际成绩。
- 重启、切换动作再返回，都从占位组读取最后**已提交**的重量。
- 调重保存失败时显示“重量未保存，重试”，保留当前输入；不能带着未保存提示静默进入下一组。
- 只有重量变动触发写入；计时每秒刷新不触发数据库写入或 DataRevision。
- 不新增倒计时、到时强制开始或自动完成。

### 3.4 动作设置：步长与器械备忘

记录页动作名附近放一个“动作设置”入口，打开同一底部弹层：

- 调重幅度：0.5 / 1 / 1.25 / 2.5 / 5 kg，单选。
- 器械备忘：多行纯文本，例“座椅第 4 档；靠背第 2 档；短握把”。
- 保存 / 取消；保存一步提交步长和备忘。改步长不修改当前组或任何历史重量。
- 控件的加减、拖动、休息调重、纠错都使用同一个动作步长。
- 步长按 exercise.id 保存，跨计划、跨训练生效；同名不同 id 的动作互不影响。
- 有备忘时在记录页和休息页显示最多两行，点击展开全文；无备忘时不占一张空卡片。
- 清空备忘后保存即删除文字；保留内部换行，去除首尾空白；最多 500 code point。
- 备忘只表示当前器械设置，不追溯修改 session_exercise.note，也不声称是当年训练时的设置。

### 3.5 收藏、最近使用、多选

- 选择器顶部提供“常用 / 全部”。存在收藏或最近记录时默认常用，否则默认全部。
- 常用内先收藏，再列最多 10 个最近实际练过、且未在收藏区重复展示的动作。
- 收藏区按原有肌群 / 拼音排序，不新增自定义排序功能。
- 最近使用由已完成组计算：按 MAX(COALESCE(completed_at, session.started_at)) 降序，同时间按现有动作排序、id 兜底。包括正在训练里已完成的组；浏览或仅加入计划不计入最近使用。
- CSV / 补记按记录中的实际历史时间参与；删除全部相关成绩后，该动作不再靠已删除数据占据最近区。
- 星标是独立点击目标，点击只改变收藏状态，不能顺便选中或关闭弹层。
- 搜索按名称检索全部可选动作，不局限当前常用区；查询为空恢复当前标签。
- 默认不自动弹键盘；用户点搜索框后才弹出。继续保留键盘避让和 SafeArea。
- 单选模式保留点选返回，用于手动补记与临时替换。
- 多选模式点击行切换勾选，底部固定“添加 N 个动作”；N=0 时禁用。
- 多选按点击顺序加入，取消后不新增训练动作或计划草稿项。已经明确点下的收藏修改保留，收藏不属于添加草稿。
- 训练批量添加：所有动作出现项与第一组一次提交，失败全部回滚，焦点落在第一个新加动作。
- 计划批量添加：只改本地草稿，最终保存计划时才落库。
- 已归档动作不进入新选择；历史和已有计划继续显示归档动作。原收藏和备忘不因归档被删除。

### 3.6 本次临时替换

入口文案“替换当前动作”，位于动作菜单；替换前先通过单选选择目标，再显示操作后果和“替换为 ××”按钮。

| 源动作状态 | 替换结果 |
|---|---|
| 没有已完成组 | 删除旧出现项及未完成占位，创建新动作出现项放到原位置 |
| 已完成 2 组、仍有下一组占位 | 保留旧出现项及 2 组，删旧占位；新出现项紧跟旧出现项，旧项退出可继续动作条 |
| 是最后一个可继续动作 | 允许替换，事务结束后仍有一个可继续的新动作 |
| 目标与源 exercise.id 相同 | 返回未变更，不写库、不重置成绩 |
| 目标已经在本场另一位置出现 | 新建独立出现项，不合并、不搬组 |
| 目标已归档或被恢复操作替换掉 | 提示重新选择，不写入 |
| 源组或训练在确认前变化 | 快照冲突，重新加载，不沿用过期预览 |

其他规则：

- 新动作首组沿用 getLastPerformance(newExerciseId, currentSessionId) 的现有语义；无历史仍使用默认 20 kg / 次数参考 8。不继承旧动作重量或备忘。
- 新动作只建立一个未完成组；保留次数参考不代表已经完成。
- 若源动作正在休息，取消这一段未确认的休息，保留 rest_seconds 原值，不将换器械耗时记成休息，也不启动新动作休息。
- 若活动休息属于另一个动作，替换不取消或重置它；之后显式开始下一组或完成新组时沿用现有会话级结算逻辑。
- 完成后焦点转到新出现项。顺序按完整出现项列表重排，然后由未完成组推导可继续列表。
- 原动作的已完成组仍出现在本场组列表、训练总结、历史和各自动作走势中。
- 不修改动作库、原计划、计划轮转关联；不把原动作重命名成新动作。

## 4. 数据设计与兼容

### 4.1 动作偏好表：追加 v5

在 lib/data/db/schema.dart 新增 createExercisePreferencesSql；在 migrations.dart 追加 v5，schemaVersion 改为 5。原建表字符串和 v1–v4 原样保留。

~~~sql
CREATE TABLE IF NOT EXISTS exercise_preference (
  exercise_id TEXT PRIMARY KEY
    REFERENCES exercise(id) ON DELETE CASCADE,
  weight_step_milli INTEGER NOT NULL DEFAULT 2500
    CHECK(weight_step_milli IN (500, 1000, 1250, 2500, 5000)),
  is_favorite INTEGER NOT NULL DEFAULT 0
    CHECK(is_favorite IN (0, 1)),
  equipment_note TEXT NOT NULL DEFAULT ''
    CHECK(length(equipment_note) <= 500)
);
~~~

默认无行等价于 2500 / false / 空字符串。只有实际修改偏好才创建行；三项全部恢复默认时可删除行。读全量动作时批量合并偏好，避免每个动作单独查询。

步长使用千分之一 kg 的整数存储，只用于偏好；现有 set_entry.weight 继续使用 REAL，不重写历史数值。最近使用由成绩推导，不额外维护 last_used_at 或点击日志。

A 批的纠错、撤销、调重不新增组字段，不持久化 UI 撤销 token。

### 4.2 备份 v3

新文件的顶层 version = 3、schemaVersion = 5；data 增加：

~~~json
{
  "exercisePreferences": [
    {
      "exerciseId": "existing-exercise-id",
      "weightStepMilli": 1250,
      "isFavorite": true,
      "equipmentNote": "座椅第 4 档\n短握把"
    }
  ]
}
~~~

- v3 必须有 exercisePreferences 数组，空数组表示没有自定义偏好。
- 该数组按 exerciseId 唯一；引用 exercises 中的有效 id；归档动作可被引用。
- weightStepMilli 只能是表定义中的五个整数；isFavorite 必须是 JSON bool；equipmentNote 必须是字符串、长度不超 500 code point。
- _fields / _tables 增加该段；主键校验新增映射：settings 用 key，exercisePreferences 用 exerciseId，其余用 id。
- 数据段按 SQLite rowid 顺序读取，与现有快照 token 规则一致。不要对偏好写入使用 DELETE + INSERT 来模拟更新。
- 兼容矩阵：v1 / v2 接受 schema 1–4；v3 要求 schema 5。本计划不导出 v2/schema5 的混搭文件。
- 旧 v1 / v2 恢复为“无动作偏好”的完整快照，清空本机 exercise_preference；旧文件无 settings 时仍保留主题偏好，不能把旧动作的收藏备注挂到新动作上。
- 恢复删除顺序将 exercise_preference 放在 exercise 之前；插入顺序在 exercises 之后插入 preferences。
- 保持全部恢复在同一事务里，旧格式兼容、坏字段、孤儿引用、重复 exerciseId 均在写库前拒绝。
- 偏好纳入导出体积 / 记录数、恢复前变化检查和导入追加后的容量校验。
- 预览新增“动作偏好 N 项”，写明本机收藏、调重幅度、器械备忘将一起替换；旧备份说明这些项目恢复为默认。
- 更新恢复后的缓存与选择器；立即反映新偏好，无需杀进程。
- 旧版 App 无法读取 v3，这是预期的版本边界；新版继续读旧文件，不覆盖旧文件。为便于恢复旧版本，升级前保留原 v2 导出文件。

### 4.3 事务、并发和刷新

新增业务仓储负责“检查 → 写入”，同一事务里只使用 tx；不得从 tx 内调用再次开启事务的 public 包装函数。

- 完成一组原子化：复核 active session 和目标 pendingSetId → 结束先前活动休息 → 写实际数值 → 标完成 → 开休息 → 建下一占位。
- 撤销原子化：复核完整预览 → 删除明确下一占位 → 重置明确目标组。
- 替换原子化：复核预览和目标动作 → 建新出现项与首组 → 删除或保留旧项 → 重排顺序。
- 批量添加原子化：检查所有目标 → 顺序创建出现项与首组 → 容量检查。
- 修改和调重也由仓储复查 session 未结束和组所属关系，不能只信 UI 内存。
- 编辑 / 撤销 / 替换预览 token 可复用 readSessionDeletion(tx, sessionId).token 的完整会话快照；不要把计时器的当前秒数放进 token。
- 最近完成组排序用 completed_at DESC, rowid DESC；撤销时同时检查目标确实是源动作的最后已完成组，不能只靠时间戳。
- ActiveSessionController 统一处理写入中的状态。完成、开始、结束、纠错、撤销、添加、移除、替换之间互斥。
- 连续调重只串行提交最后目标值；按 pendingSetId 绑定队列，不能在切动作后写到另一个占位。
- 开始、结束、切动作、打开变更预览以及离开记录页前先 flushPendingWeight；失败时留在当前操作并提供重试。
- reset / 恢复备份使旧队列 generation 失效。恢复提交前先结束或取消未提交的页面输入；取消的输入不得在恢复后复活。
- 已提交但加载失败与事务失败区分：“已保存，页面刷新失败，请重新载入”；重试只读取，不能再执行一次替换或批量添加。
- 完成一组的成功触感在提交成功后触发；失败不表现成已完成。
- 每个成功业务写入调用一次 onDataChanged / DataRevision.changed；取消、冲突、失败不发成功通知。
- 测试固定时间，不依赖真实 sleep 或恰好同一毫秒。

## 5. 文件与接口边界

### 5.1 文件分工

| 文件 | 新建 / 修改 | 职责 |
|---|---|---|
| lib/domain/workout_edit.dart | 新建 | 纠错、撤销、替换预览与写入结果类型 |
| lib/domain/exercise_preferences.dart | 新建 | 步长选项、偏好值对象、备注校验、相对调重纯函数 |
| lib/data/repositories/workout_write_repo.dart | 新建 | 原子完成、开始、结束、pending 重量、批量添加与首组创建 |
| lib/data/repositories/workout_edit_repo.dart | 新建 | 本场组更正、撤销及快照检查 |
| lib/data/repositories/exercise_replacement_repo.dart | 新建 | 替换预览与单事务替换 |
| lib/data/repositories/exercise_preferences_repo.dart | 新建 | 批量读取、部分字段更新、默认行清理 |
| lib/data/repositories/exercise_picker_repo.dart | 新建 | 动作、偏好与最近使用汇总 |
| lib/state/active_session_controller.dart | 修改 | 串行写入、输入 flush、预览、提交结果与当前焦点 |
| lib/state/exercise_preferences_controller.dart | 新建 | 偏好加载 / 保存 / revision 失效 |
| lib/features/workout/completed_sets_sheet.dart | 新建 | 本场所有已记组，包括隐藏动作 |
| lib/features/workout/edit_set_sheet.dart | 新建 | 更正某组实际重量和次数 |
| lib/features/workout/exercise_settings_sheet.dart | 新建 | 步长和器械备忘编辑 |
| lib/features/workout/next_set_weight.dart | 新建 | 休息态下一组重量与保存状态 |
| lib/features/workout/replace_exercise_sheet.dart | 新建 | 选择目标后的预览与提交 |
| lib/features/workout/exercise_picker.dart | 修改 | 单选兼容入口、多选、常用、搜索、星标 |
| lib/features/workout/record_page.dart / rest_view.dart | 修改 | 连接入口与新组件，继续使用 FillOrScroll |
| lib/features/workout/number_stepper.dart / drag_number.dart | 修改 | 相对加减、共享步长、格式和拖动结束事件 |
| lib/domain/format.dart | 修改 | 统一实际重量显示，支持 1.25 kg |
| lib/ui/widgets/session_summary_view.dart | 既有回归，不改结构 | 当前只展示汇总和次数数组；验证改组、撤销、替换后的结果 |
| lib/features/progress/progress_page.dart / exercise_detail_page.dart | 修改 | 实际重量文本同步；估算值显示口径不变 |
| lib/features/plans/plan_editor_page.dart / lib/state/plan_controller.dart | 修改 | 多选加入草稿 |
| lib/data/db/schema.dart / migrations.dart | 修改 | v5 表 |
| lib/domain/backup.dart / lib/data/repositories/backup_repo.dart | 修改 | v3 字段、版本、校验与恢复顺序 |
| lib/features/settings/backup_preview_dialog.dart / backup_section.dart | 修改 | 偏好恢复说明 |
| lib/app/providers.dart / lib/state/backup_controller.dart | 修改 | provider 生命周期、恢复前调重清理与恢复后刷新 |
| test/support/workout_fixture.dart | 新建 | 真实内存库与两个动作的最小训练夹具 |
| test/domain、test/data、test/state、test/widget、test/e2e | 新建对应测试 | 业务行为与失败边界 |
| scripts/browser_workout_efficiency_smoke.mjs | 新建 | 真 UI 操作和文件往返 |
| scripts/browser_backup_smoke.mjs | 修改 | 注册 workout_efficiency 场景模块，并适配原有备份场景的多选确认 |
| README.md | 实施收尾时修改 | 使用说明、备份版本和实际验证结果 |

不把新 UI、SQL、数据类型继续堆进 record_page.dart。只抽出本期改动需要的职责，不做全项目架构重排。

### 5.2 固定接口契约

以下为本计划新增的接口，实施时按此命名；类型放在 domain，SqlExecutor 只用于仓储。

~~~dart
enum WorkoutWriteResult {
  saved,
  savedNeedsReload,
  unchanged,
  busy,
  conflict,
  failed,
}

class CompletedSetEdit {
  final String sessionId;
  final SetEntry original;
  final String token;
  const CompletedSetEdit(this.sessionId, this.original, this.token);
}

class UndoSetPreview {
  final String sessionId;
  final String sessionExerciseId;
  final String setId;
  final String pendingSetId;
  final String token;
  const UndoSetPreview(this.sessionId, this.sessionExerciseId,
      this.setId, this.pendingSetId, this.token);
}

class ExerciseReplacementPreview {
  final String sessionId;
  final String sourceSessionExerciseId;
  final String sourceExerciseId;
  final String targetExerciseId;
  final String sourceName;
  final String targetName;
  final int completedSets;
  final String token;
  const ExerciseReplacementPreview({
    required this.sessionId,
    required this.sourceSessionExerciseId,
    required this.sourceExerciseId,
    required this.targetExerciseId,
    required this.sourceName,
    required this.targetName,
    required this.completedSets,
    required this.token,
  });
}

class ExercisePreference {
  final String exerciseId;
  final int weightStepMilli;
  final bool isFavorite;
  final String equipmentNote;
  final String token;
  const ExercisePreference({
    required this.exerciseId,
    this.weightStepMilli = 2500,
    this.isFavorite = false,
    this.equipmentNote = '',
    required this.token,
  });
  double get weightStepKg => weightStepMilli / 1000;
}

class ExercisePickerData {
  final List<Exercise> all;
  final Map<String, ExercisePreference> preferences;
  final List<String> recentIds;
  ExercisePickerData(this.all, this.preferences, this.recentIds);
}
~~~

预览对象由仓储返回。集合在构造时不可变复制；上面 ExercisePickerData 的简单构造签名保留，实际构造体使用 List.unmodifiable / Map.unmodifiable。

| 所在位置 | 接口 |
|---|---|
| workout_write_repo | Future<SessionExercise> addExerciseWithFirstSet(SqlExecutor tx, String sessionId, String exerciseId)；只使用已有 tx，不开事务 |
| workout_write_repo | Future<void> completeWorkoutSet(SqlExecutor exec, {required String sessionId, required String pendingSetId, required double weight, required int reps, required int now}) |
| workout_write_repo | Future<void> beginWorkoutSet(SqlExecutor exec, {required String sessionId, required String pendingSetId, required int now}) |
| workout_write_repo | Future<void> finishActiveWorkout(SqlExecutor exec, {required String sessionId, required int now}) |
| workout_write_repo | Future<void> savePendingWeight(SqlExecutor exec, {required String sessionId, required String pendingSetId, required double weight}) |
| workout_write_repo | Future<List<String>> addWorkoutExercises(SqlExecutor exec, String sessionId, List<String> exerciseIds)；返回新 session_exercise.id |
| workout_edit_repo | Future<CompletedSetEdit> inspectCompletedSet(SqlExecutor exec, String sessionId, String setId) |
| workout_edit_repo | Future<void> updateCompletedSet(SqlExecutor exec, CompletedSetEdit edit, {required double weight, required int reps}) |
| workout_edit_repo | Future<UndoSetPreview?> inspectUndoSet(SqlExecutor exec, String sessionId, String sessionExerciseId, {required int now}) |
| workout_edit_repo | Future<void> undoCompletedSet(SqlExecutor exec, UndoSetPreview preview, {required int now}) |
| exercise_replacement_repo | Future<ExerciseReplacementPreview> inspectExerciseReplacement(SqlExecutor exec, String sessionId, String sourceSessionExerciseId, String targetExerciseId) |
| exercise_replacement_repo | Future<String> replaceWorkoutExercise(SqlExecutor exec, ExerciseReplacementPreview preview)；返回新出现项 id，同动作返回源 id |
| exercise_preferences_repo | Future<Map<String, ExercisePreference>> readExercisePreferences(SqlExecutor tx, Iterable<String> ids) |
| exercise_preferences_repo | Future<ExercisePreference> saveExercisePreference(SqlExecutor exec, String exerciseId, {required String expectedToken, int? weightStepMilli, bool? isFavorite, String? equipmentNote}) |
| exercise_picker_repo | Future<ExercisePickerData> loadExercisePickerData(SqlExecutor exec) |
| ActiveSessionController | bool get writing；String? get writeMessage；只读暴露写入状态和错误文案 |
| ActiveSessionController | Future<WorkoutWriteResult> editCompletedSet(CompletedSetEdit edit, double weight, int reps) |
| ActiveSessionController | Future<WorkoutWriteResult> undoLastCompletion(UndoSetPreview preview) |
| ActiveSessionController | void stagePendingWeight(String pendingSetId, double weight)；Future<WorkoutWriteResult> flushPendingWeight() |
| ActiveSessionController | Future<WorkoutWriteResult> addExercises(List<String> exerciseIds) |
| ActiveSessionController | Future<WorkoutWriteResult> replaceExercise(ExerciseReplacementPreview preview) |
| ExercisePreferencesController | Future<void> load(Iterable<String> ids)；ExercisePreference preferenceFor(String exerciseId)；Future<WorkoutWriteResult> save(String exerciseId, {int? weightStepMilli, bool? isFavorite, String? equipmentNote}) |
| exercise_picker.dart | 保留 Future<Exercise?> showExercisePicker(BuildContext context)；新增 Future<List<Exercise>?> showExerciseMultiPicker(BuildContext context) |
| PlanController | void addExercises(List<String> exerciseIds)；已有 addExercise 委托单元素列表 |
| domain/exercise_preferences.dart | double adjustWeight(double value, double stepKg, int steps, {double min = 0, double max = 500}) |
| domain/format.dart | String formatWeightKg(double value)；只返回数字文本，必要时加约等号 |

偏好保存用 null 表示字段不变，空字符串表示清空备忘。星标保存必须仅更新 isFavorite，不能拿旧弹层里的备注覆盖新备注。冲突时重新加载，不静默最后写入者覆盖全部偏好。

## 6. 实施任务

每个任务内按清单顺序执行。提交只包含该任务明确的文件，禁止 git add .；不要提交构建产物或用户原有本地修改。以下保留原定步骤；实际执行与文件合并调整以执行记录为准。


### [x] Task 1（A）：把完成、开始和结束训练变为受保护的原子操作

**Files**

- Create: lib/data/repositories/workout_write_repo.dart
- Create: lib/domain/workout_edit.dart
- Create: test/support/workout_fixture.dart
- Create: test/data/workout_write_repo_test.dart
- Modify: lib/state/active_session_controller.dart
- Modify: lib/data/repositories/set_repo.dart（listSets 的 position 后补 rowid 排序）
- Test: test/state/complete_set_test.dart、test/state/active_session_controller_test.dart

**Interfaces:** 产出 §5.2 的 completeWorkoutSet / beginWorkoutSet / finishActiveWorkout / addExerciseWithFirstSet。ActiveSessionController 构造函数增加可选 int Function()? now，用于可重复的时间测试，生产默认 DateTime.now().millisecondsSinceEpoch。

- [ ] 记录实际 HEAD、工作区修改、Flutter 版本和原测试基线。

~~~powershell
. .\scripts\env.ps1
git status --short
git rev-parse HEAD
flutter --version
flutter analyze
flutter test --reporter expanded
~~~

预期：原测试通过；若现状已有失败，先记录并定位，不把失败归因于尚未实施的功能。

- [x] 建立真实内存库夹具。基础代码放 test/support/workout_fixture.dart：

~~~dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/repositories/exercise_repo.dart';
import 'package:gym_tracker/state/active_session_controller.dart';

class WorkoutClock {
  int value = DateTime.utc(2026, 10, 16, 2).millisecondsSinceEpoch;
  int call() => value;
}

class WorkoutFixture {
  final FfiExecutor db;
  final ActiveSessionController controller;
  final WorkoutClock clock;
  final String benchId;
  final String rowId;
  const WorkoutFixture(
    this.db, this.controller, this.clock, this.benchId, this.rowId);
}

Future<WorkoutFixture> workoutFixture() async {
  final db = await FfiExecutor.openMigrated();
  addTearDown(() => db.close());
  final bench = await createCustomExercise(db, name: '杠铃卧推');
  final row = await createCustomExercise(db, name: '坐姿划船');
  final clock = WorkoutClock();
  final controller = ActiveSessionController(db, now: clock.call);
  addTearDown(controller.dispose);
  await controller.startNew();
  await db.run('UPDATE session SET started_at=? WHERE id=?',
      [clock.value, controller.session!.id]);
  await controller.resume();
  await controller.addExercise(bench.id);
  return WorkoutFixture(db, controller, clock, bench.id, row.id);
}
~~~

- [ ] 先写失败用例：完成按钮并发两次只能生成一个完成组和一个占位；在最后一次 INSERT 注入异常后，数值、完成状态、休息和组数全部回到调用前；结束训练与完成组不能交错。一个核心用例：

~~~dart
test('并发完成只记一组', () async {
  final f = await workoutFixture();
  await Future.wait([
    f.controller.completeCurrentSet(40, 8),
    f.controller.completeCurrentSet(40, 8),
  ]);
  final rows = await f.db.all<Map<String, Object?>>(
    'SELECT * FROM set_entry ORDER BY position,rowid');
  expect(rows.where((r) => r['is_completed'] == 1), hasLength(1));
  expect(rows.where((r) => r['is_completed'] == 0), hasLength(1));
});
~~~

- [ ] 执行失败测试，确认失败来自当前竞态或缺失接口，而不是夹具错误。

~~~powershell
flutter test test/data/workout_write_repo_test.dart test/state/complete_set_test.dart --reporter expanded
~~~

- [x] 将完成操作落到如下仓储事务；所调用的 updateSetValues / completeSet / startRest / endRest / addSet 均是已有 set_repo 函数。

~~~dart
Future<void> completeWorkoutSet(
  SqlExecutor exec, {
  required String sessionId,
  required String pendingSetId,
  required double weight,
  required int reps,
  required int now,
}) async {
  if (!weight.isFinite || weight < 0 || reps < 0) {
    throw const RecordManagementException('重量或次数无效');
  }
  await exec.transaction((tx) async {
    final pending = await tx.first<Map<String, Object?>>(
      'SELECT st.session_exercise_id FROM set_entry st '
      'JOIN session_exercise se ON se.id=st.session_exercise_id '
      'JOIN session s ON s.id=se.session_id '
      'WHERE st.id=? AND se.session_id=? '
      'AND s.finished_at IS NULL AND st.is_completed=0',
      [pendingSetId, sessionId],
    );
    if (pending == null) {
      throw const RecordManagementException('当前组已变化，请重新载入');
    }
    final rests = await tx.all<Map<String, Object?>>(
      'SELECT st.id FROM set_entry st '
      'JOIN session_exercise se ON se.id=st.session_exercise_id '
      'WHERE se.session_id=? AND st.rest_started_at IS NOT NULL',
      [sessionId],
    );
    if (rests.length > 1) {
      throw const RecordManagementException('休息状态异常，请重新载入');
    }
    for (final rest in rests) {
      await endRest(tx, rest['id'] as String, now);
    }
    await updateSetValues(tx, pendingSetId, weight, reps);
    await completeSet(tx, pendingSetId, now);
    await startRest(tx, pendingSetId, now);
    await addSet(tx, pending['session_exercise_id'] as String, weight, reps);
  });
}
~~~

- [x] 将 _addExerciseWithFirstSet 从 controller 移到新仓储，保持 getLastPerformance 的参数和默认值，返回新 SessionExercise；startNew 的现有事务直接使用该 helper，禁止嵌套事务。
- [x] beginWorkoutSet 在事务内验证 pendingSetId 所属和 active session，再结束整场唯一活动休息。finishActiveWorkout 在事务内 cancelRest 并 finishSession；保留末组休息不入账的口径。
- [x] controller 在第一个 await 之前置写入锁，finally 释放。原 completeCurrentSet / beginNextSet / endWorkout 对外签名保留；从 currentExercise 捕获明确 id，避免 await 后按已变化的 currentIndex 写入。
- [x] 提交后读库失败记录为已提交状态；UI 提供“重新载入”，不能重复完成一组。只有提交成功后触感和一次数据通知。
- [ ] 跑定向回归，确认新增事务和旧开训、继续训练流程全部通过；按本任务文件清单提交。

**完成条件：** 完成组不留半状态；并发点击不重复记组；原休息、开训和结束规则不变。

### [x] Task 2（A）：更正与撤销仓储

**Files**

- Create: lib/data/repositories/workout_edit_repo.dart
- Create: test/data/workout_edit_repo_test.dart
- Modify: lib/domain/workout_edit.dart
- Modify: lib/state/active_session_controller.dart
- Create: test/state/workout_edit_controller_test.dart

**Interfaces:** 消费 Task 1 的原子写入与 fixture；产出 inspectCompletedSet / updateCompletedSet / inspectUndoSet / undoCompletedSet，以及 controller 的对应编排方法。

- [x] 加两类失败测试。测试文件导入 fixture、workout_edit_repo、set_repo 和 flutter_test：

~~~dart
test('纠错只改实际数值，计时字段不变', () async {
  final f = await workoutFixture();
  await f.controller.completeCurrentSet(40, 10);
  final sessionId = f.controller.session!.id;
  final seId = f.controller.currentSessionExerciseId!;
  final before = (await listSets(f.db, seId))
      .singleWhere((s) => s.isCompleted);
  final edit = await inspectCompletedSet(f.db, sessionId, before.id);
  await updateCompletedSet(f.db, edit, weight: 42.5, reps: 8);
  final after = (await listSets(f.db, seId))
      .singleWhere((s) => s.isCompleted);
  expect(after.weight, 42.5);
  expect(after.reps, 8);
  expect(after.completedAt, before.completedAt);
  expect(after.restStartedAt, before.restStartedAt);
  expect(after.restSeconds, before.restSeconds);
});

test('撤销清掉新占位并恢复刚才那组', () async {
  final f = await workoutFixture();
  await f.controller.completeCurrentSet(40, 8);
  final sessionId = f.controller.session!.id;
  final seId = f.controller.currentSessionExerciseId!;
  final before = (await listSets(f.db, seId))
      .singleWhere((s) => s.isCompleted);
  final preview = await inspectUndoSet(
    f.db, sessionId, seId, now: f.clock.value);
  expect(preview, isNotNull);
  await undoCompletedSet(f.db, preview!, now: f.clock.value);
  final rows = await listSets(f.db, seId);
  expect(rows, hasLength(1));
  expect(rows.single.id, before.id);
  expect(rows.single.isCompleted, isFalse);
  expect(rows.single.completedAt, isNull);
  expect(rows.single.restStartedAt, isNull);
  expect(rows.single.restSeconds, isNull);
  expect(rows.single.weight, 40);
});
~~~

- [ ] 测试缺失接口时失败；再实现预览读取和事务复核。复用 readSessionDeletion(tx, sessionId).token；比较 session active、完整 token 和明确组 id。
- [x] 更正的最终写入严格为：

~~~sql
UPDATE set_entry
SET weight=?, reps=?
WHERE id=? AND session_exercise_id=? AND is_completed=1;
~~~

- [x] 撤销复核 §3.2 六项条件后，在同一 tx 中按顺序执行：

~~~sql
DELETE FROM set_entry
WHERE id=? AND session_exercise_id=? AND is_completed=0;

UPDATE set_entry
SET is_completed=0,
    completed_at=NULL,
    rest_started_at=NULL,
    rest_seconds=NULL
WHERE id=? AND session_exercise_id=? AND is_completed=1;
~~~

- [x] 加拒绝用例：已经开始下一组；另一动作刚完成一组；历史训练；隐藏动作没有占位；重复撤销；两组同 completed_at；超过 30 分钟；预览后重量变化；外来 session/set id。
- [x] 在 DELETE 后、UPDATE 后分别注入异常，核对整个数据库快照与操作前一致。异常注入包装器必须在 transaction 回调内包装 tx，不能只拦外层 executor。
- [x] controller 预览前等待调重 flush，提交成功后恢复所选 sessionExerciseId，调用一次通知；保存失败保留编辑输入。

~~~powershell
flutter test test/data/workout_edit_repo_test.dart test/state/workout_edit_controller_test.dart test/state/complete_set_test.dart --reporter expanded
~~~

预期：全部通过；随后提交本任务文件。

### [x] Task 3（A）：本场组列表、纠错弹层与撤销入口

**Files**

- Create: lib/features/workout/completed_sets_sheet.dart
- Create: lib/features/workout/edit_set_sheet.dart
- Modify: lib/features/workout/record_page.dart
- Modify: lib/features/workout/rest_view.dart
- Create: test/widget/workout_edit_test.dart
- Modify: test/widget/viewport_test.dart

**Interfaces:** 使用 Task 2 的预览对象和 controller 方法；本场列表读取 controller.exercises 全量，不能只读 recordingExercises。

- [ ] 写界面失败用例：本场记录入口可点；改 10 次为 8 后返回仍在休息；取消不改库；保留成绩的隐藏动作可见；开始下一组后撤销入口消失。
- [x] 添加稳定语义键：completed-sets、edit-set-weight、edit-set-reps、save-set-edit、undo-last-completion。键用于交互定位，不替代文本和可访问性标签。
- [x] 建立薄弹层接口，保存按钮等待真实结果：

~~~dart
Future<void> showCompletedSetsSheet(BuildContext context);
Future<void> showEditSetSheet(
  BuildContext context, CompletedSetEdit edit);
~~~

入口的最终调用方式：

~~~dart
TextButton(
  key: const ValueKey('completed-sets'),
  onPressed: c.loading || c.writing
      ? null
      : () => showCompletedSetsSheet(context),
  child: Text('本场已记 ' + completedCount.toString() + ' 组'),
)
~~~

其中 writing 是 controller 新增只读忙状态，completedCount 从全部 exercises 的 isCompleted 组求和，不存第二份计数。

- [x] 弹层使用本地 TextEditingController 保存草稿，只有保存成功才关闭；错误文本留在弹层。打开时用原始 double 生成可编辑文本，不用四舍五入后的显示文本覆盖数据。
- [x] 撤销使用 inspectUndoSet 判断资格；按钮执行 controller.undoLastCompletion，成功后回记录态并同步当前占位值。
- [x] 修改不能重置 RestView 的 restStartedAt；避免以整个 controller revision 作为计时器 Widget Key。
- [x] 验证 320×480、640×360、360×640 且字号 2.0、300dp 键盘场景；保存 / 取消 / 开始按钮可达，无溢出。

~~~powershell
flutter test test/widget/workout_edit_test.dart test/widget/viewport_test.dart --reporter expanded
~~~

预期：真实写库断言和布局断言通过；随后提交本任务文件。

### [x] Task 4（A）：休息调重与输入保存次序

**Files**

- Create: lib/features/workout/next_set_weight.dart
- Modify: lib/features/workout/rest_view.dart
- Modify: lib/features/workout/record_page.dart
- Modify: lib/features/workout/drag_number.dart
- Modify: lib/state/active_session_controller.dart
- Modify: lib/data/repositories/workout_write_repo.dart
- Create: test/state/pending_weight_test.dart
- Create: test/widget/rest_weight_test.dart
- Modify: lib/state/record_management_controller.dart（删除前 flush）
- Modify: lib/state/backup_controller.dart / lib/app/providers.dart（恢复前 hook）

**Interfaces:** stagePendingWeight / flushPendingWeight / savePendingWeight；DragNumber 增加 VoidCallback? onChangeEnd，拖动结束和取消时提交当前预览值。BackupController 增加可选 Future<void> Function()? beforeRestore，放在真正 restoreBackup 调用之前；hook 失败不启动恢复。

- [ ] 写失败用例，核心数据断言为：

~~~dart
test('休息调重只改下一占位重量，重启保留', () async {
  final f = await workoutFixture();
  await f.controller.completeCurrentSet(40, 8);
  final seId = f.controller.currentSessionExerciseId!;
  final before = await listSets(f.db, seId);
  final pending = before.singleWhere((s) => !s.isCompleted);
  final completed = before.singleWhere((s) => s.isCompleted);
  f.controller.stagePendingWeight(pending.id, 42.5);
  expect(await f.controller.flushPendingWeight(),
      WorkoutWriteResult.saved);
  await f.controller.resume();
  final after = await listSets(f.db, seId);
  final next = after.singleWhere((s) => !s.isCompleted);
  final done = after.singleWhere((s) => s.isCompleted);
  expect(next.weight, 42.5);
  expect(next.reps, pending.reps);
  expect(done.weight, completed.weight);
  expect(done.restStartedAt, completed.restStartedAt);
  expect(done.restSeconds, completed.restSeconds);
});
~~~

- [x] savePendingWeight 在事务内验证目标仍属于 active session、is_completed=0，最终只执行：

~~~sql
UPDATE set_entry
SET weight=?
WHERE id=? AND is_completed=0;
~~~

- [x] controller 将暂存值按 pendingSetId 保存，单写入循环串行提交；写入期间的新输入覆盖尚未提交的目标值，不能覆盖已经在写的参数。flush 等待本次调用前的最新目标提交。
- [x] 已提交无变化返回 unchanged；无待保存值也返回 unchanged。上面的首个实际保存返回 saved。任一失败返回 failed，保留输入供重试。
- [x] 给 RestView 添加下一占位 id、当前准备重量、保存状态、调重回调、提交回调；不添加 reps 或目标次数参数。
- [x] 开始 / 结束 / 撤销 / 替换 / 添加 / 移除 / 删除之前完成 flush。备份恢复 beforeRestore 先 flush；若因此使原恢复预览过期，使用既有“重新预览并确认恢复”提示，禁止绕过预览 token。
- [x] 点击“开始第 N 组”只结束休息并进入记录页；实际次数依然由完成时的控件取值。计时状态不因调重、打开本场列表或改备注改变。
- [x] reset / restore 递增 generation 并清空未提交草稿，晚到的旧保存完成事件不能覆盖恢复后的内存。
- [x] 覆盖快速连点、拖动松手、拖动取消、保存中点击开始、写入失败重试、切动作、返回、恢复备份、熄屏重启，以及调重后撤销的占位清除。
- [ ] 跑 A 批全部定向测试与既有训练测试；随后提交本任务文件。此时 A 批可以独立交付，不依赖新偏好表。

~~~powershell
flutter test test/state/pending_weight_test.dart test/widget/rest_weight_test.dart test/state/workout_edit_controller_test.dart test/widget/workout_edit_test.dart test/state/complete_set_test.dart test/widget/viewport_test.dart --reporter expanded
~~~

### [x] Task 5（B）：动作偏好、v5 迁移和 v3 备份一起交付

**Files**

- Create: lib/domain/exercise_preferences.dart
- Create: lib/data/repositories/exercise_preferences_repo.dart
- Modify: lib/data/db/schema.dart / migrations.dart
- Modify: lib/domain/backup.dart
- Modify: lib/data/repositories/backup_repo.dart
- Modify: lib/features/settings/backup_preview_dialog.dart / backup_section.dart
- Create: test/domain/exercise_preferences_test.dart
- Create: test/data/exercise_preferences_repo_test.dart
- Modify: test/data/migrations_test.dart
- Modify: test/domain/backup_test.dart / backup_boundaries_test.dart
- Modify: test/data/backup_repo_test.dart / backup_repo_boundaries_test.dart / import_repo_test.dart
- Create: test/fixtures/backup/current-v3.json
- Preserve: test/fixtures/backup/legacy-v1.json / legacy-v2.json / current-v2.json

**Interfaces:** ExercisePreference、readExercisePreferences、saveExercisePreference；偏好 token 是当前存储行的稳定序列化值，无行时使用固定 absent 标记并包含 exerciseId。

- [x] 先写 v4 升级 v5 保留原始动作 / 训练 / 计划的失败测试。仅执行 v1–v4 迁移并构造数据，再执行新 migrate；比较旧表逐字段快照。
- [x] 写偏好部分更新失败测试：

~~~dart
test('收藏更新不覆盖器械备忘', () async {
  final f = await workoutFixture();
  final first = (await readExercisePreferences(f.db, [f.benchId]))
      [f.benchId]!;
  final noted = await saveExercisePreference(
    f.db, f.benchId,
    expectedToken: first.token,
    weightStepMilli: 1250,
    equipmentNote: '座椅第 4 档',
  );
  final starred = await saveExercisePreference(
    f.db, f.benchId,
    expectedToken: noted.token,
    isFavorite: true,
  );
  expect(starred.equipmentNote, '座椅第 4 档');
  expect(starred.weightStepMilli, 1250);
  expect(starred.isFavorite, isTrue);
});
~~~

- [x] 实现 §4.1 建表、纯值对象和校验。readExercisePreferences 对每个请求 id 返回默认值或实际值；不存在的动作由写接口拒绝，读取不制造数据库行。
- [x] saveExercisePreference 在事务内读取原值、比 token、合并非 null 字段、校验、UPSERT；全默认时删除偏好行；事务结尾执行现有备份容量校验。
- [x] 按 §4.2 扩展备份。新主键选择逻辑固定为：

~~~dart
String backupPrimaryKey(String section) => switch (section) {
  'settings' => 'key',
  'exercisePreferences' => 'exerciseId',
  _ => 'id',
};
~~~

不能仅改 backupVersion 而漏掉 schemaVersion 上限、_tables、恢复顺序或 v1/v2 缺段归一化。

- [x] 新 v3 fixture 至少含：1.25 kg 步长、收藏、中文多行备注、归档动作偏好、活动休息和已调好的下一占位。
- [x] 验证真实文件字节 encode → decode → restore → export 后，偏好和组字段完全一致；旧 v1/v2 成功恢复并清掉本机旧偏好。
- [x] 拒绝重复 exerciseId、引用不存在、非法步长、数字代替布尔、超长备注、v3 缺段、100001 记录和超 20 MiB；坏文件不写库。
- [x] 偏好写入 / 恢复中途失败整批回滚，恢复预览后改收藏会使预览失效。追加导入保持已有偏好，并把偏好计入总容量。

~~~powershell
flutter test test/domain/exercise_preferences_test.dart test/data/exercise_preferences_repo_test.dart test/data/migrations_test.dart test/domain/backup_test.dart test/domain/backup_boundaries_test.dart test/data/backup_repo_test.dart test/data/backup_repo_boundaries_test.dart test/data/import_repo_test.dart --reporter expanded
~~~

预期：全部通过，旧 fixture 保留其旧格式；随后提交本任务文件。新表和新备份必须同批落地，避免用户创建了无法备份的备注。

### [x] Task 6（B）：步长、重量显示和器械备忘界面

**Files**

- Create: lib/state/exercise_preferences_controller.dart
- Create: lib/features/workout/exercise_settings_sheet.dart
- Modify: lib/app/providers.dart
- Modify: lib/features/workout/record_page.dart / rest_view.dart / next_set_weight.dart / edit_set_sheet.dart
- Modify: lib/features/workout/number_stepper.dart / drag_number.dart
- Modify: lib/domain/exercise_preferences.dart / format.dart
- Modify: lib/features/progress/progress_page.dart / exercise_detail_page.dart
- Create: test/widget/exercise_settings_test.dart
- Modify: test/domain/format_test.dart / test/domain/exercise_preferences_test.dart
- Create: test/state/exercise_preferences_controller_test.dart

**Interfaces:** 消费 Task 5 偏好仓储；controller 批量缓存按 exerciseId 索引，恢复后失效；输出统一步长和备注给三个重量编辑位置。

- [ ] 写纯函数失败测试：

~~~dart
test('步长按当前值相对增加，保留非网格起点', () {
  expect(adjustWeight(21.3, 2.5, 1), closeTo(23.8, 1e-9));
  expect(adjustWeight(21.3, 2.5, -1), closeTo(18.8, 1e-9));
  expect(adjustWeight(0, 1.25, -1), 0);
  expect(adjustWeight(499, 2.5, 1), 500);
});
test('重量展示保留四分之一公斤', () {
  expect(formatWeightKg(21.25), '21.25');
  expect(formatWeightKg(22.5), '22.5');
  expect(formatWeightKg(20), '20');
});
~~~

- [x] 实现相对调重，替换两个控件原来的“除以 step 再 round”：

~~~dart
double adjustWeight(
  double value, double stepKg, int steps, {
  double min = 0,
  double max = 500,
}) {
  if (!value.isFinite || !stepKg.isFinite || stepKg <= 0 ||
      !min.isFinite || !max.isFinite || min > max) {
    throw ArgumentError('无效的重量范围或调重幅度');
  }
  return (value + stepKg * steps).clamp(min, max).toDouble();
}
~~~

此函数只在用户实际操作时调用。加载导入重量、改步长、改次数不能调用它来“归一化”原重量。旧超范围值不自动截断；用户要修正重量时可用弹层直接输入非负有限数。

- [x] formatWeightKg 显示最多两位小数并去掉尾零；若原值与显示值差超过 1e-9，前缀“≈”。仅改变显示，数据仍保留原始 double；编辑弹层直接加载原始值。统一记录页、控件和进步页的实际重量文本，估算 1RM / 总容量的既有整数显示规则不变。现有总结页只有汇总和次数数组，本任务不增加新的逐组重量布局。
- [x] 动作设置弹层使用 §3.4 内容，保存时只提交 weightStepMilli / equipmentNote；收藏字段不被旧草稿覆盖。加载失败显示重试，不把默认值误展示为已经保存的设置。
- [x] 所有重量控件显式传入 preference.weightStepKg；新增控制器只提供偏好，不承担训练写入或休息计时。
- [x] 已保存备注在记录 / 休息态两行展示、可展开；取消弹层不保存，清空可保存；乱码和 Emoji 按 code point 校验。
- [x] 校验不同动作、相同动作跨计划、同名不同 id、改偏好不改历史、1.25 kg 跨页展示、恢复后立即刷新，以及两张弹层旧 token 冲突。

~~~powershell
flutter test test/domain/exercise_preferences_test.dart test/domain/format_test.dart test/state/exercise_preferences_controller_test.dart test/widget/exercise_settings_test.dart test/widget/rest_weight_test.dart test/widget/progress_pages_test.dart --reporter expanded
~~~

预期：全部通过；随后提交本任务文件。

### [x] Task 7（B）：最近使用与收藏选择器

**Files**

- Create: lib/data/repositories/exercise_picker_repo.dart
- Modify: lib/domain/exercise_preferences.dart
- Modify: lib/features/workout/exercise_picker.dart
- Create: test/data/exercise_picker_repo_test.dart
- Create: test/widget/exercise_picker_test.dart
- Test: test/widget/import_and_plans_test.dart

**Interfaces:** loadExercisePickerData 返回全量非归档动作、偏好映射和 recentIds；保留 showExercisePicker 的单选返回类型。

- [x] 测试最近使用只能由已完成组产生；只有占位 / 只进计划 / 只浏览不出现；旧 CSV 按实际时间排序；重复动作只出现一个 id；归档过滤；删除成绩后变化。
- [x] 聚合最近时间使用下面查询，并在 Dart 对同时间结果应用 compareExercises 后再以 id 兜底：

~~~sql
SELECT se.exercise_id,
       MAX(COALESCE(st.completed_at, s.started_at)) AS last_performed_at
FROM set_entry st
JOIN session_exercise se ON se.id=st.session_exercise_id
JOIN session s ON s.id=se.session_id
JOIN exercise e ON e.id=se.exercise_id
WHERE st.is_completed=1 AND e.is_archived=0
GROUP BY se.exercise_id;
~~~

先排序 / 去重，截取最近 10 个，再在显示常用区时排除已在收藏区出现的 id。不要用 MAX(rowid) 充当最后训练时间。

- [x] UI 加常用 / 全部、独立星标和全库搜索；将 autofocus 改为 false，保留 viewInsets 避让和 useSafeArea。
- [x] 星标走 preference controller 部分更新，保存失败恢复原星标并显示重试；不选中动作、不关弹层。
- [x] 测试单选点击仍立即返回正确 Exercise；补记取消仍返回 null；搜索零结果不隐藏返回操作。
- [x] 验证星标和行选择各自可点击区域至少 44dp，不靠长按发现收藏。

~~~powershell
flutter test test/data/exercise_picker_repo_test.dart test/widget/exercise_picker_test.dart test/widget/import_and_plans_test.dart test/widget/viewport_test.dart --reporter expanded
~~~

预期：单选旧入口和新常用区均通过；随后提交本任务文件。

### [x] Task 8（B）：训练和计划批量添加

**Files**

- Modify: lib/features/workout/exercise_picker.dart
- Modify: lib/features/workout/record_page.dart
- Modify: lib/state/active_session_controller.dart
- Modify: lib/data/repositories/workout_write_repo.dart
- Modify: lib/features/plans/plan_editor_page.dart / lib/state/plan_controller.dart
- Create: test/state/batch_add_exercises_test.dart
- Modify: test/widget/exercise_picker_test.dart
- Modify: test/widget/import_and_plans_test.dart
- Modify: scripts/browser_plans_smoke.mjs / browser_smoke.mjs（真实流程适配）

**Interfaces:** showExerciseMultiPicker、addWorkoutExercises、ActiveSessionController.addExercises、PlanController.addExercises。

- [ ] 写失败用例：按 B→A 选择，加入顺序 B→A；反选再选回的动作放到最后；关闭弹层没有新增；同一批次不重复，分两批仍可加入同一动作。
- [x] 训练批量仓储在一个 transaction 内校验所有 exerciseId，再逐个调用 Task 1 的 addExerciseWithFirstSet；返回每个新出现项 id。
- [x] 在第二个动作插入后注入失败，断言第一个动作和两个动作的占位都回滚；目标归档 / 消失、容量超限也全部回滚。
- [x] 已有 addExercise(String) 委托 addExercises([id])，保留旧调用者；批量成功仅通知一次、焦点定位第一个新增项。
- [x] 计划草稿的批量追加保留重复项语义，实现核心为：

~~~dart
void addExercises(List<String> exerciseIds) {
  final current = draft;
  if (_disposed || busy || current == null || exerciseIds.isEmpty) return;
  _edit(current.name, [...current.exerciseIds, ...exerciseIds]);
}
~~~

这里复用已核对存在的 _edit 和 _notify，让 dirty 标记、原 expectedToken 和 dispose 保护保持一致。

- [x] 修改记录页、计划页为多选入口；手动补记保持 showExercisePicker 单选。
- [x] 选择器底栏“添加 N 个动作”可在键盘打开时点击；零选中禁用。收藏立即生效，取消只撤销选择草稿。
- [x] 更新旧浏览器脚本中的“点动作即加入”步骤为勾选后提交，保留原断言；不通过删旧测试来适应新 UI。

~~~powershell
flutter test test/state/batch_add_exercises_test.dart test/widget/exercise_picker_test.dart test/widget/import_and_plans_test.dart test/e2e/plan_library_preservation_test.dart --reporter expanded
~~~

预期：全部通过；随后提交本任务文件。此时 B 批独立可用。

### [x] Task 9（C）：临时替换的预览和事务

**Files**

- Create: lib/data/repositories/exercise_replacement_repo.dart
- Modify: lib/domain/workout_edit.dart
- Modify: lib/state/active_session_controller.dart
- Create: test/data/exercise_replacement_repo_test.dart
- Create: test/state/exercise_replacement_controller_test.dart

**Interfaces:** inspectExerciseReplacement / replaceWorkoutExercise / controller.replaceExercise；消费 Task 1 首组创建、既有 retainCompletedSets 和完整会话快照。

- [x] 先写两个关键失败用例：

~~~dart
test('有成绩的替换保留原组并新建独立出现项', () async {
  final f = await workoutFixture();
  await f.controller.completeCurrentSet(40, 8);
  await f.controller.beginNextSet();
  f.clock.value += 10000;
  await f.controller.completeCurrentSet(40, 7);
  final sessionId = f.controller.session!.id;
  final sourceId = f.controller.currentSessionExerciseId!;
  final before = (await listSets(f.db, sourceId))
      .where((s) => s.isCompleted).map((s) => s.id).toList();
  final preview = await inspectExerciseReplacement(
    f.db, sessionId, sourceId, f.rowId);
  final newId = await replaceWorkoutExercise(f.db, preview);
  final source = await listSets(f.db, sourceId);
  expect(source.map((s) => s.id).toList(), before);
  expect(source.every((s) => s.isCompleted), isTrue);
  expect(source.every((s) => s.restStartedAt == null), isTrue);
  final target = await listSets(f.db, newId);
  expect(target, hasLength(1));
  expect(target.single.isCompleted, isFalse);
  expect(newId, isNot(sourceId));
});

test('唯一可继续动作也能原子替换', () async {
  final f = await workoutFixture();
  final sessionId = f.controller.session!.id;
  final sourceId = f.controller.currentSessionExerciseId!;
  final preview = await inspectExerciseReplacement(
    f.db, sessionId, sourceId, f.rowId);
  final newId = await replaceWorkoutExercise(f.db, preview);
  await f.controller.resume();
  expect(f.controller.recordingExercises, hasLength(1));
  expect(f.controller.currentSessionExerciseId, newId);
});
~~~

- [x] 预览读取源动作、目标动作、完成组数和会话 token；只接受仍在 active session 且有唯一占位的源。目标必须存在、未归档。
- [x] 实现事务顺序：重新验证 token / active / source / target → 新建目标及首组 → 按源完成组数分支 → 重排顺序。先确定完整 id 序列，再按 id 写 position，不按 position 批量对调。
- [x] 无完成组分支删除明确 sourceSessionExerciseId；有成绩分支调用 retainCompletedSets(tx, sourceId)，把新 id 放在旧 id 后面。
- [x] 源 rest_started_at 只取消不计算时长；其他动作休息字段逐字段保持。完整位置序列重排，但组的 position、重量、次数、completed_at 不改。
- [x] 同 exerciseId 返回源 id，并由 controller 映射 unchanged；不产生新组或数据通知。
- [x] 新目标在本场已出现时仍建新出现项；getLastPerformance 排除当前 session，不挪用本场另一次出现项成绩。
- [x] 注入首组创建后、旧项处理后、重排中途失败；事务回滚，包括原活动休息。比较原计划两张表及 exercise 表逐字段不变。
- [x] controller flush 后才取预览，执行后通过新出现项 id 定位，不依赖“原 index + 1”；提交后重载失败返回 savedNeedsReload，不重复替换。

~~~powershell
flutter test test/data/exercise_replacement_repo_test.dart test/state/exercise_replacement_controller_test.dart test/state/remove_exercise_test.dart test/e2e/plan_library_preservation_test.dart --reporter expanded
~~~

预期：全部通过；随后提交本任务文件。

### [x] Task 10（C）：替换入口与完整现场流程

**Files**

- Create: lib/features/workout/replace_exercise_sheet.dart
- Modify: lib/features/workout/record_page.dart
- Modify: lib/features/workout/rest_view.dart
- Create: test/widget/exercise_replacement_test.dart
- Create: test/e2e/workout_efficiency_test.dart

**Interfaces:** 单选选择器、替换预览与 controller.replaceExercise；现有移除入口继续保留。

- [x] 从动作菜单进入单选选择器。选中目标后展示源 / 目标、已完成组保留说明和“仅影响本次训练”；确认按钮只执行当前预览。
- [x] 无已完成组文案：“本次将 杠铃卧推 换为 哑铃卧推，原计划保持不变。”
- [x] 有已完成组文案：“杠铃卧推已记 2 组会保留，后续改练哑铃卧推，原计划保持不变。”
- [x] 取消不写库；选择原动作直接返回；保存中禁用重复提交。冲突显示重新选择入口，不沿用旧确认。
- [x] 新动作显示自己的步长、备忘、历史预填；旧动作在“本场已记”里可见。替换后旧动作不再有休息调重和撤销入口。
- [x] 写贯穿测试：按计划开训 → 两组 → 更正一组 → 调下一组重量 → 临时替换 → 新动作一组 → 结束 → 核对两动作成绩 → 下次同计划仍含原动作。
- [x] 另测“新增 B 后再把 A 替换成 B”，两个 B 出现项独立保存；统计仍按 exerciseId 聚合的现有口径展示，不把出现项 id 当动作库 id。

~~~powershell
flutter test test/widget/exercise_replacement_test.dart test/e2e/workout_efficiency_test.dart test/widget/remove_exercise_test.dart test/widget/viewport_test.dart --reporter expanded
~~~

预期：上述操作从真实界面完成且数据库断言通过；随后提交本任务文件。

### Task 11：整轮浏览器、备份与 Android 验收

**Files**

- Create: scripts/browser_workout_efficiency_smoke.mjs
- Modify: scripts/browser_backup_smoke.mjs
- Modify: scripts/browser_import_smoke.mjs / browser_plans_smoke.mjs（新选择器 / v3 断言）
- Modify: test/e2e/workout_efficiency_test.dart
- Modify: README.md
- Create during execution: docs/superpowers/plans/2026-10-16-workout-efficiency-execution.md（实际跨日时使用实施日日期）

**Interfaces:** 复用现有浏览器驱动 run(h)，不创建另一套浏览器启动器；在 GYM_BROWSER_FEATURE 白名单加入 workout_efficiency。现有动态导入 browser_ + feature + _smoke.mjs 将直接对应新脚本，不另设不一致的别名。

新脚本入口使用现有模式：

~~~javascript
import path from 'node:path';
import { fileURLToPath } from 'node:url';

export async function run(h) {
  await h.check('从空库创建训练并选择卧推', async () => {
    await h.clickText('开始训练', true);
    await h.clickText('添加动作', true);
    await h.until(() => h.has('胸'), 'exercise picker data ready');
    await h.clickText('卧推', true);
    await h.clickText('添加 1 个动作', true);
    await h.expectText('完成这组');
  });
  await h.check('打开动作设置入口', async () => {
    await h.clickText('动作设置', true);
    await h.expectText('调重幅度');
    await h.screenshot('01-exercise-settings');
  });
}

if (process.argv[1] &&
    path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  process.env.GYM_BROWSER_FEATURE = 'workout_efficiency';
  import('./browser_backup_smoke.mjs').catch(error => {
    console.error(error);
    process.exitCode = 1;
  });
}
~~~

上述代码给出空库启动和首个界面检查。继续在 run(h) 中按下方矩阵加入其余场景，每项都要有最终状态断言，不能只点击和截图。预置动作真实名称为“卧推”，测试夹具自建的“杠铃卧推”不用于空库浏览器定位。

- [x] 完成 §7 的浏览器矩阵，关键结果同时读取 UI 和导出的真实 JSON；禁止只调用仓储替代浏览器交互。
- [x] 跑格式、静态分析、全量测试一次，全部通过后再构建 Web：

~~~powershell
. .\scripts\env.ps1
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test --reporter expanded
flutter build web --no-pub
node scripts/browser_smoke.mjs
node scripts/browser_backup_smoke.mjs
node scripts/browser_import_smoke.mjs
node scripts/browser_plans_smoke.mjs
node scripts/browser_workout_efficiency_smoke.mjs
~~~

- [x] 原浏览器备份脚本在 feature 为空时也会创建训练，必须同步加入多选确认并显式聚焦搜索框；它原先依赖 autofocus。原 mutation 脚本若绑定了 v2 字段或单选语义，先更新其断言和匹配点，再运行；所有预期破坏仍必须被测试发现。不要为了通过而删除变异守卫。

~~~powershell
node scripts/backup_mutation_check.mjs
node scripts/import_plans_mutation_check.mjs
~~~
- [x] 构建主应用，记录实际产物哈希：

~~~powershell
flutter build apk --debug --no-pub
flutter build apk --release --no-pub
Get-FileHash -LiteralPath build\app\outputs\flutter-apk\app-release.apk -Algorithm SHA256
adb devices -l
~~~

- [ ] 设备连接且处于后续实施授权范围时，用主包覆盖更新，保留数据：

~~~powershell
adb install -r build\app\outputs\flutter-apk\app-release.apk
adb shell am start -n com.mobis.gym_tracker/.MainActivity
~~~

- [ ] 真机按 §7.2 验收；测试前记录现有数据和导出备份。测试训练用明确的“效率验收”名称，结束后通过界面删除测试记录；收藏和备忘恢复到测试前的值。
- [x] 不自动执行整库恢复来清理主包。需要在主包核验整库恢复时，单独确认将替换的数据，并先保存当前备份；其他功能继续按可逆 UI 操作验收。
- [x] 没有设备时记录“未执行真机验收”，交付现有结果和断点；构建成功不算真机通过。
- [x] README 更新六项用法、撤销边界、v3 导出与旧备份恢复语义；执行记录填写实际命令、通过数量、证据目录、APK SHA256 和未执行项。
- [x] 最后逐项对照 §8 完成定义，再按明确文件清单提交。不要预写“全部通过”。


## 7. 验收矩阵

### 7.1 浏览器与自动化必须覆盖

| ID | 场景与操作 | 必须核对的结果 |
|---|---|---|
| E01 | 完成 40 kg × 10，纠正为 40 kg × 8 | 只有 weight/reps 可变；完成时间和休息开始不变；容量使用 320 |
| E02 | 打开纠错，输入后取消 | 库和摘要均不变 |
| E03 | 完成后撤销，再完成同一组 | 第一次完成被撤回；最终只有一组真实成绩和一个下一占位 |
| E04 | 开始下一组后尝试旧撤销预览 | 拒绝；不删除新占位，不回滚旧组 |
| E05 | 休息把下一组 40 调成 42.5，重载继续 | 已完成组仍 40；未完成组 42.5；计时延续 |
| E06 | 休息调重后开始，做完选择 6 次 | 新完成组为 42.5 × 6，休息期间没有保存目标次数 |
| E07 | 调重保存中立即点击开始 / 切动作 | 等待正确占位提交；不丢最后目标值，不写错动作 |
| E08 | 设置卧推步长 1.25、划船 5 | 两动作加减互不影响，拖动与按钮步长一致 |
| E09 | 原重量 21.3，步长 2.5，按加号 | 结果约 23.8，不跳到 25；改步长本身不改重量 |
| E10 | 写备忘、清空、取消、重载 | 保存持久化，清空生效，取消保留原文；长度边界一致 |
| E11 | 收藏动作、打开常用、搜索另一动作 | 收藏置前；星标不触发行选择；搜索覆盖全部可选动作 |
| E12 | 仅将动作加入计划，然后查看最近 | 不进入最近；实际完成组后进入 |
| E13 | 多选 B→A，取消一次再确认一次 | 取消零新增；确认按 B→A 添加，各有一个首组占位 |
| E14 | 同动作分两批加入计划 | 两个独立草稿项，保存后仍为两项 |
| E15 | 零完成组时替换唯一动作 | 正好一个新可继续项；旧未完成项消失；原计划不变 |
| E16 | 已完成两组后替换 | 旧两组逐字段保留，旧占位消失，新目标首组独立 |
| E17 | 源休息时替换、其他动作休息时替换 | 源休息取消且不写推测时长；其他动作休息保留 |
| E18 | 替换为本场已有的动作 | 独立出现项，已有目标组数、数值不变 |
| E19 | 选择源自身、取消替换、过期预览 | 自身 / 取消不写；过期明确拒绝 |
| E20 | v3 真文件导出，在另一隔离 origin 导入 | 收藏、步长、Unicode 备注、活动训练及准备重量逐字段相等 |
| E21 | 导入旧 v1 / v2，旧文件缺 settings | 训练与计划恢复，动作偏好为空默认；主题按原兼容规则保留 |
| E22 | 坏 v3、孤儿偏好、超限文件、恢复取消 | 数据完全不变 |
| E23 | 恢复预览后改收藏或下一组重量 | 拒绝旧预览，要求重新预览 |
| E24 | 对第二次新增 / 撤销删除后 / 替换重排注入失败 | 整场快照回滚，不留下半个新动作 |
| E25 | 两组同毫秒、同 position 的兼容输入 | 查询顺序稳定；撤销根据明确 id，不误删其他组 |
| E26 | 替换后修改保留的旧组，再结束 | 旧 / 新动作历史归属正确，容量和走势使用各自成绩 |
| E27 | 备份恢复后仍有旧异步调重回调 | 旧 generation 不再修改新内存或新库 |
| E28 | 提交已成功但刷新异常，再点击重试 | 只重读状态，不多出新动作 / 新组 |
| E29 | 小屏、横屏、大字号、键盘打开 | 主按钮可达，备注不挤掉计时，弹层可滚动 |
| E30 | 所有六项操作后退出重开 | 数据、收藏、步长、备注与可继续动作恢复一致 |

自动化可以按底层 / state / widget / e2e 分层覆盖同一矩阵，不要求浏览器重复每一个故障注入。浏览器必须覆盖 E01、E03、E05、E06、E08、E10、E11、E13、E15、E16、E20、E21、E22、E29、E30 的真实用户流程。

### 7.2 Android 主包验收

| ID | 操作 | 通过标准 |
|---|---|---|
| A01 | 用主包覆盖升级已有数据的 v4 安装 | 原动作库、训练、计划不变；新偏好默认值正确 |
| A02 | 单手完成 / 修改 / 撤销，连续点完成 | 触感只在成功后出现；不重复记组；编辑按钮可点击 |
| A03 | 休息调重，熄屏 30 秒，再亮屏 | 时长连续，已保存重量在，次数未被新增流程自动修改 |
| A04 | 调重成功后强杀 App，再打开继续 | 唯一占位及其重量恢复；未完成组仍不算成绩 |
| A05 | 改步长，写中文 / Emoji / 多行备忘 | 输入法不挡保存按钮，1.25 正确显示，重启持久化 |
| A06 | 收藏、多选、搜索、键盘收起 | 星标不误选；确认顺序与用户选择一致 |
| A07 | 练两组后换动作，再练一组结束 | 旧两组 + 新一组全部保留，原计划不变 |
| A08 | 系统文件选择器导出 v3，取消选择 / 保存 | 实际文件可读；取消不改数据库 |
| A09 | 深色 / 浅色、大字号和横屏 | 没有溢出、遮挡、不可达按钮 |
| A10 | 清理本轮测试训练和测试偏好 | 只通过 UI 清理明确测试项，原有真实训练保持不变 |

v3 文件的整库恢复正确性先由隔离 Web / FFI 验证；Android 原生恢复若尚未单独执行，在结果里明确记录这一平台差异，不能用文件导出成功替代恢复验收。

## 8. 完成定义与交付清单

### 8.1 用户可见完成定义

- [x] 当前训练的已完成组能修改，包含替换后保留下来的旧动作组。
- [x] 刚误点完成能按规定边界撤回，其他真实记录不受影响。
- [x] 休息能调下一组重量，次数在实际完成后确认，开始下一组不产生虚假成绩。
- [x] 每个动作记住自己的步长，1.25 kg 显示不丢精度。
- [x] 收藏和最近使用减少寻找操作，多选一次提交，计划仍允许重复动作。
- [x] 临时替换可在零组 / 已练组 / 唯一动作三种状态使用，旧组和原计划保持正确。
- [x] 器械备忘能查看、编辑、清空并跨训练保留。
- [x] 备份包含全部新数据，旧 v1 / v2 能恢复，新 v3 往返一致。
- [x] 错误、取消、重启、快速点击、恢复冲突都不产生半完成数据。
- [x] 自动化、浏览器、构建和真机结果分别记录，未执行项明确列出。

### 8.2 实施完成时交付

1. 本计划各任务的实际勾选状态；被调整的任务说明最终实现位置。
2. README 最新使用说明与备份兼容说明。
3. 实际执行记录：提交号、命令、结果、真实测试数量、证据目录、遗留事项。
4. 主应用 release APK 路径与 SHA256；仅在已实际构建后提供。
5. 真机验收结果或可接续的明确断点。

### 8.3 本次计划文档自检

- 范围覆盖：1 → Tasks 1–3；3 → Task 4；4 / 7 → Tasks 5–6；5 → Tasks 7–8；6 → Tasks 9–10；统一验收 → Task 11。
- 已区分用户明确要求和计划中的实现取舍，未把第 2 项加入范围。
- 六项功能涉及的数据、备份、失败回滚、重启和旧入口回归均有对应任务。
- 编写阶段曾保持全部未勾选；本轮实施后的实际勾选与验收结果按执行记录更新。
