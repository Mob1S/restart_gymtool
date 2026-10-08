# Phase 2 实施计划：历史与进步

> **规格**：[`../specs/2026-10-09-flutter-gym-tracker-phase2-design.md`](../specs/2026-10-09-flutter-gym-tracker-phase2-design.md)
> **上游**：[`2026-10-08-gym-tracker-design.md`](../specs/2026-10-08-gym-tracker-design.md)（旧 RN 总纲）
> **上一期**：[`2026-10-08-phase1-skeleton-and-recording.md`](./2026-10-08-phase1-skeleton-and-recording.md)

---

## 全局约束（每个 Task 都适用）

| 约束 | 内容 |
|---|---|
| **subagent 一律不碰 git** | 只写文件、只跑测试。提交由主 agent 做。出处：旧项目 §7.3 的共享 git index 事故 |
| `domain/` **不得 import Flutter** | 由 `test/layering_test.dart` 规则 3 守。`chart_geometry.dart` 最容易破功（想要 `Offset`） |
| 口径只有一份实现 | `estimateOneRepMax` / `totalVolumeLoad` **一行都不改**，`progress.dart` 一律调用 |
| **禁止 N+1** | 进步页三处（动作列表 / 动作详情 / 迷你走势）共用 `listAllCompletedSetFacts` 一次查询 |
| `rowid` 兜底 | 所有按时间排序的查询一律 `ORDER BY <time> DESC, rowid DESC`（总纲 §4.3） |
| 迁移只追加 | 本期**不需要**新迁移 —— Phase 1 的 schema v3 已含全部所需表和列。**若发现要加列，先停下汇报** |
| 环境 | 每条命令前先 `. C:\ccproject\restart_gymtool\scripts\env.ps1` |
| 守卫必须会红 | 每个 Task 的测试都要做变异验证（见 Task 14 的总表） |

**验收命令**

```powershell
. C:\ccproject\restart_gymtool\scripts\env.ps1
flutter analyze                                  # 期望 No issues found!
flutter test test/domain test/data test/state    # 日常快速反馈
flutter test                                     # 提交前必须完整跑（含 e2e）
```

---

## 里程碑

| 里程碑 | Task | 内容 |
|---|---|---|
| **A 纯逻辑** | 1–2 | `progress.dart`（每场一个点）、`chart_geometry.dart`（折线几何） |
| **B 数据层** | 3–6 | 两条新 SQL + 分组 + `SessionSummary` 值对象 |
| **C 界面层** | 7–12 | 抽 `SessionSummaryView`、手绘 `TrendChart`、四个新页面 + 路由 |
| **D 验收** | 13–16 | 界面断言、变异验证、Chrome 走查、真机验收 |

---

## Task 1：`domain/progress.dart` —— 把组折算成「每场一个点」

**新建**：`lib/domain/progress.dart`
**测试**：`test/domain/progress_test.dart`

```dart
import 'types.dart';   // 只为 SetLike 之类的既有类型；不要 import Flutter

/// 一条「已完成组」的事实。仓储查出来的就是它，之后全在 Dart 里算。
class SetFact {
  final String exerciseId;
  final String sessionId;
  final int sessionStartedAt;
  final double weight;
  final int reps;
  const SetFact({...});
}

/// 一场训练里的一个点。**一次训练 = 一个点。**
class SessionPoint {
  final String sessionId;
  final int startedAt;
  final double topWeight;
  final int topWeightReps;
  final double? bestE1rm;
  final double? e1rmWeight;
  final int? e1rmReps;
  final double volumeLoad;
  const SessionPoint({...});
}

/// 把散的组聚成「每场一个点」，按 `startedAt` 升序、`sessionId` 兜底。
List<SessionPoint> buildSessionPoints(List<SetFact> facts);
```

**实现要点**

- **输入顺序不得依赖**：函数内部自己按 `(startedAt, sessionId)` 分组并排序。
- **`topWeight`**：该场最大重量；**并列时取次数多的那一组**（`topWeightReps` 反映这一点）。
- **`bestE1rm`**：该场所有组里 `estimateOneRepMax(w, r)` 的**最大值**，
  并记下它**来自哪一组**（`e1rmWeight` / `e1rmReps`）。
  **不是「最重那组的 e1RM」** —— 见下。
- **`volumeLoad`**：该场 `Σ(w × r)`。
- 该场一组都没有 → 不会出现在结果里（仓储已过滤 `is_completed = 1`）。

**测试用例（每条都要有）**

| # | 用例 | 断言 |
|---|---|---|
| 1 | ⭐ **一次训练 = 一个点** | 同一场 3 组 → 结果 `hasLength(1)` |
| 2 | ⭐ **最佳 e1RM 不来自最重的那组** | 同一场 `{60×10, 70×3}` → `bestE1rm` `closeTo(78.51, 0.01)`，且 `e1rmWeight == 60`、`e1rmReps == 10` |
| 3 | 最大重量并列取次数多的 | `{60×5, 60×8}` → `topWeight == 60`、`topWeightReps == 8` |
| 4 | 全部组次数 > 10 → 该场 e1RM 为 null | `{60×12, 55×15}` → `bestE1rm` isNull，`topWeight == 60`，`volumeLoad == 60*12+55*15` |
| 5 | `reps == 1` 用实测重量 | `{100×1}` → `bestE1rm == 100` |
| 6 | 输入乱序也能聚合 | 打乱 `facts`，结果与有序时**完全相同** |
| 7 | 多场按时间升序 | 三场乱序输入 → 输出 `startedAt` 严格升序 |
| 8 | 容量只累加该场 | 两场 → 各自的 `volumeLoad` 不串 |

**变异验证**：把 `bestE1rm` 改成「取 `topWeight` 那组的 e1RM」→ **用例 2 必须红**。

---

## Task 2：`domain/chart_geometry.dart` —— 折线几何

**新建**：`lib/domain/chart_geometry.dart`
**测试**：`test/domain/chart_geometry_test.dart`

```dart
/// 不要用 `Offset` —— 那是 `dart:ui` 的，`domain/` 不许 import Flutter。
class ChartPoint {
  final double x, y;
  final int index;   // 原始的 values 下标；null 项不产生 ChartPoint
  const ChartPoint({...});
}

class ChartLayout {
  final List<ChartPoint> points;   // 按 x 升序
  final int? highlightIndex;       // 最大值所在的**第一个**下标
  final double minValue, maxValue; // 非 null 值的范围
  final int gapCount;              // values 里 null 的个数
  const ChartLayout({...});
}

ChartLayout layoutChart({
  required List<double?> values,
  required double width,
  required double height,
  double insetY = 12,
});
```

**实现要点（四条都是规格 §2.2 定的）**

1. **x 按索引等距**：`x = index / (values.length - 1) * width`；
   只有一个元素时 `x = width / 2`（不除零）。
2. **y 取 `min..max` 缩放到 `[insetY, height - insetY]`**，**不强制从 0**。
3. **`min == max` 时全部画在竖直居中**（`y = height / 2`），**不除零、不贴底**。
4. **`null` 跳过不产生点**，但相邻非 null 点在画线时直接连（画线在 `TrendChart` 里做）。

**测试用例**

| # | 用例 | 断言 |
|---|---|---|
| 1 | 单元素 | `points` 长度 1，`x == width/2` |
| 2 | ⭐ **全等值不除零、不贴底** | `[60, 60, 60]` → 三个 `y == height/2`，无异常 |
| 3 | ⭐ **y 不从 0 起** | `[100, 110]` → 最小值那个点 `y == height - insetY`（而不是按 0..110 缩放） |
| 4 | ⭐ **高亮点是最大值不是最新值** | `[100, 50, 80]` → `highlightIndex == 0` |
| 5 | 并列取最早 | `[80, 100, 100]` → `highlightIndex == 1` |
| 6 | null 跳过但计入 gapCount | `[1, null, 3]` → `points` 长度 2，`points[1].index == 2`，`gapCount == 1` |
| 7 | 全 null | `points` 空、`highlightIndex` isNull、不崩 |
| 8 | 空列表 | 不崩，`points` 空 |

**变异验证**：`highlightIndex` 改成 `values.length - 1` → **用例 4、5 必须红**。

---

## Task 3：`data` —— 一次性取全部已完成组

**新建**：`lib/data/repositories/progress_repo.dart`
**测试**：`test/data/progress_repo_test.dart`

```dart
/// 取**所有**已完成组的原始事实（跨全部训练、全部动作）。
///
/// 一条 SQL 解决动作列表 + 动作详情 + 迷你走势三处，之后全在 Dart 里分组。
/// **不按动作逐个查** —— 那是 N+1，在手机上会肉眼可见地卡
/// （旧项目 sessionRepo 的注释里写明了这一条）。
Future<List<SetFact>> listAllCompletedSetFacts(SqlExecutor exec);
```

```sql
SELECT se.exercise_id AS exercise_id,
       s.id           AS session_id,
       s.started_at   AS session_started_at,
       st.weight      AS weight,
       st.reps        AS reps
  FROM set_entry st
  JOIN session_exercise se ON se.id = st.session_exercise_id
  JOIN session s           ON s.id  = se.session_id
 WHERE st.is_completed = 1
   AND s.finished_at IS NOT NULL
 ORDER BY s.started_at ASC, s.rowid ASC, se.position ASC, st.rowid ASC
```

**测试用例**

| # | 用例 | 断言 |
|---|---|---|
| 1 | ⭐ **进行中的训练不进结果** | 建一场不 `finishSession` → 结果为空 |
| 2 | 未完成的组不进结果 | 占位组（`is_completed = 0`）被排除 |
| 3 | 只取到该动作的组 | 两个动作分开建组 → 按 `exerciseId` 分得开 |
| 4 | 同毫秒两场用 `rowid` 兜底 | 手工把两场 `started_at` 写成同一个值 → 顺序与插入顺序一致（**不要 sleep**） |
| 5 | 空库返回空表 | 不是异常 |

---

## Task 4：`data` —— 历史列表的聚合查询

**修改**：`lib/data/repositories/session_repo.dart`（**追加**，不改既有函数）
**测试**：`test/data/session_summary_list_test.dart`

```dart
class SessionSummaryRow {
  final WorkoutSession session;
  final int durationSeconds;
  final int setCount;
  final double volumeLoad;
}

/// 历史列表：**一条聚合查询**，不是「先查训练、再逐个查组」。
Future<List<SessionSummaryRow>> listSessionSummaries(SqlExecutor exec);
```

```sql
SELECT s.id, s.name, s.started_at, s.finished_at,
       COUNT(st.id)                          AS set_count,
       COALESCE(SUM(st.weight * st.reps), 0) AS volume_load
  FROM session s
  LEFT JOIN session_exercise se ON se.session_id = s.id
  LEFT JOIN set_entry st ON st.session_exercise_id = se.id
                        AND st.is_completed = 1
 WHERE s.finished_at IS NOT NULL
 GROUP BY s.id
 ORDER BY s.started_at DESC, s.rowid DESC
```

**测试用例**

| # | 用例 | 断言 |
|---|---|---|
| 1 | ⭐ **0 组训练仍然出现** | 建一场不加动作就结束 → 结果含它，`setCount == 0` |
| 2 | ⭐ **0 组时容量是 0 不是 null** | 同上 → `volumeLoad == 0`（不是 `null`、不抛） |
| 3 | ⭐ 进行中的训练不出现 | `WHERE finished_at IS NOT NULL` |
| 4 | 只数已完成的组 | 有占位组时 `setCount` 不把它算进去 |
| 5 | 容量口径与总结页一致 | 2 组 `20×8`、`30×10` → `volumeLoad == 460` |
| 6 | 最近的在前 | 两场 → 后建的在前（`started_at DESC`） |
| 7 | 同毫秒 `rowid` 兜底 | 同用例 4 的手法 |

**变异验证**：`LEFT JOIN` → `JOIN` → **用例 1 必须红**；
`COALESCE(...)` 去掉 → **用例 2 必须红**。

---

## Task 5：`domain` —— 动作列表与每动作的点

**新建**：`lib/domain/progress_index.dart`（或并入 `progress.dart`，二选一，**不要两处都写**）
**测试**：`test/domain/progress_index_test.dart`

```dart
/// 进步列表的一行。
class ExerciseProgressRow {
  final String exerciseId;
  final int lastTrainedAt;        // 最近一次训练的时间
  final double topWeight;         // 那一次最重的一组
  final int topWeightReps;
  final List<SessionPoint> recent; // 最近 N 个点，给迷你走势用（N = 12）
}

/// 按「最近练过」倒序。
List<ExerciseProgressRow> buildProgressIndex(List<SetFact> facts);
```

**实现要点**

- **没练过的动作不出现**（调用方从 `exercise` 表拿名字，`buildProgressIndex` 只管有数据的）。
- `recent` 取**最近** 12 个点，但**按时间升序**返回（画线要左旧右新）。
- 同一动作的多个 `SetFact` 聚成 `SessionPoint`（**复用 Task 1 的
  `buildSessionPoints`，不重写**）。
- **不必先按 `exerciseId` 过滤**：`buildSessionPoints` 的分组键就是
  `(exerciseId, sessionId)`，传全量进去再按 `point.exerciseId` 挑即可。
  （实施时改过一版：原计划分组键只有 `sessionId`，靠「调用方记得先过滤」
  的注释把关 —— 那是一类**静默算错**，数字错了却不报错。见 Task 14 变异 #10。）

**测试用例**

| # | 用例 | 断言 |
|---|---|---|
| 1 | 按最近练过倒序 | 动作 A 最后练于 9/1、B 于 9/10 → B 在前 |
| 2 | 没数据的动作不出现 | 只传 A 的 facts → 结果只有 A |
| 3 | 迷你走势取最近 12 个且升序 | 造 15 场 → `recent` 长度 12，首元素是第 4 场 |
| 4 | 复用而非重写 | A 的 `recent.last` 的 `volumeLoad` 与 Task 1 同输入下的结果一致 |

---

## Task 6：`data` —— `SessionSummary` 值对象与装载

**新建**：`lib/domain/session_summary.dart`（值对象，纯数据）
**新建**：`lib/data/repositories/session_summary_loader.dart`（读库，返回上面的值对象）
**测试**：`test/data/session_summary_loader_test.dart`

```dart
class ExerciseSummary {
  final String exerciseName;
  final List<SetEntry> sets;   // 只含已完成组，按 position / rowid 稳定排序
}

class SessionSummary {
  final WorkoutSession session;
  final List<ExerciseSummary> exercises;  // 空动作不上总结页
  final int durationSeconds;
  final int totalSets;
  final double volumeLoad;
}

Future<SessionSummary?> loadSessionSummary(SqlExecutor exec, String sessionId);
```

**这个 Task 的全部意义**：把 `SummaryPage._load()` 现在那段逻辑**原样搬出来**，
使总结页与历史详情**共用同一份计算**（口径字样与数字一旦分叉就会有一处悄悄写歪）。

**测试用例**

| # | 用例 | 断言 |
|---|---|---|
| 1 | ⭐ 数字与 Phase 1 总结页一致 | 3 组 `122.5×12` → `totalSets == 3`、`volumeLoad closeTo(4410, 0.001)` |
| 2 | 空动作不进 summary | 加了动作但一组没做 → `exercises` 为空 |
| 3 | 不存在的 sessionId | 返回 null（不抛） |
| 4 | 进行中的训练也能装载 | `finishedAt` 为 null 时 `durationSeconds` 用「现在」算，不崩 |

---

## Task 7：抽出 `SessionSummaryView`

**新建**：`lib/ui/widgets/session_summary_view.dart`
**修改**：`lib/features/workout/summary_page.dart`（改成「装载 + 渲染 + 完成按钮」）

```dart
class SessionSummaryView extends StatelessWidget {
  final SessionSummary summary;
  const SessionSummaryView({super.key, required this.summary});
}
```

**把 `SummaryPage.build` 里那段 `ListView` 的 children 整段搬过来**，包括：

- 顶部三块 `StatBlock`（**已经是 `Wrap`**，别退回 `Row`）
- 「总容量（重量 × 次数）」
- 「组间休息回顾（粗略参考）」
- 每个动作的卡片：**原始次数数组原样** + 提示或「组数不足 3 组，暂不判断」

**`SummaryPage` 改造后**：AppBar 仍然 `automaticallyImplyLeading: false`，
底部仍然有「完成」按钮 → `context.go('/')`。

> ⚠️ **`test/widget/smoke_test.dart` 里那条总结页用例是这次的回归网** ——
> 它逐字断言了口径字样与数字。**改完必须仍然全绿**；
> 若它红了，先判断是「搬家搬错了」还是「断言过时了」，**不许直接改断言**。

---

## Task 8：`ui/widgets/trend_chart.dart` —— 手绘折线

**新建**：`lib/ui/widgets/trend_chart.dart`

```dart
class TrendChart extends StatelessWidget {
  final List<double?> values;   // null = 这一场没有可用于换算的组
  final bool compact;           // true = 列表行里的迷你走势
  const TrendChart({super.key, required this.values, this.compact = false});
}
```

**一个 `CustomPainter`，只画三样**：

1. **折线** —— `Path` 依次连接 `layoutChart(...).points`，**跳过 null 直接连过去**
2. **圆点** —— 每点一个；`highlightIndex` 那个用 `c.success` 且半径更大
3. **不画**坐标轴 / 网格 / 刻度（规格 §2.2 第 2 条：y 不从 0 起，画刻度就得为它辩护）

`compact: true` → 高度 28，只画线 + 最后一个点，不画高亮。

**注意**：`TrendChart` 在 `ui/`，**可以** import Flutter；几何计算仍然全部来自
`domain/chart_geometry.dart`，**这里不许再算一遍**。

---

## Task 9：历史列表

**修改**：`lib/features/history/history_page.dart`（替换占位页）
**新建**：`lib/features/history/history_row.dart`（可选，若行内逻辑超过 20 行就拆）

- 每行：`formatDate(startedAt)` / `session.name ?? '未命名训练'` /
  `'${formatDuration(d)} · $setCount 组 · ${volumeLoad.round()} kg'`
- 点击 → `context.go('/history/${row.session.id}')`
- **空态**：「还没有已完成的训练」+「完成第一次训练后，这里会留下记录」
- 数据来自 Task 4 的 `listSessionSummaries`

---

## Task 10：历史详情 + 路由

**新建**：`lib/features/history/session_detail_page.dart`
**修改**：`lib/app/router.dart`（在 ShellRoute **外面**加一条，理由：要占满全屏、带返回键）

```dart
GoRoute(
  path: '/history/:id',
  builder: (_, s) => SessionDetailPage(sessionId: s.pathParameters['id']!),
),
```

- `AppBar` **有返回键**（默认即可，不要 `automaticallyImplyLeading: false`）
- 正文 = `SessionSummaryView(summary: ...)`
- 取不到 → 「这场训练不存在」（沿用 `SummaryPage` 的写法）

⚠️ `/history/:id` 与 ShellRoute 里的 `/history` **路径前缀相同**，
go_router 会优先匹配更长的那条；**写完要在 Chrome 上实际点一次确认**，
不要只看代码推理。

---

## Task 11：进步列表

**修改**：`lib/features/progress/progress_page.dart`（替换占位页）

- 数据：`listAllCompletedSetFacts` → `buildProgressIndex`
- 每行：动作名 / 「最近 `<formatDate>` · 最重 `<w> kg × <r>`」 / 右侧 `TrendChart(compact: true)`
- 动作名从 `exercise` 表按 id 取（`getExercise`），取不到写「未知动作」—— **不崩**
- 点击 → `/progress/<exerciseId>`
- **空态**：「还没有练过的动作」

---

## Task 12：动作详情三张卡 + 路由

**新建**：`lib/features/progress/exercise_detail_page.dart`
**修改**：`lib/app/router.dart`（再加一条 ShellRoute 外的路由）

**结构**：`PageView` 三页 + 页码点 + 顶部动作名。

**每张卡的文案逐字固定**（规格 §4.4，**这是产品红线**）：

| 卡片 | 值 | 头 | 附加 |
|---|---|---|---|
| 最大重量 | `topWeight` 的最大值 | `最好 · <日期>` | — |
| 估算 1RM | `bestE1rm` 的最大值 | `最好 · <日期>` | **`估算 · 仅供参考`** + **`来自 <w> kg × <r>`** |
| 总容量 | `volumeLoad` 的最大值 | **`最高 · <日期>`** | — |

**三种异常态**（规格 §6，各自独立）：

1. 动作 id 不存在 / 没练过 → 「这个动作还没有记录」，**不崩**
2. 只练过一次 → 一个点**不画线** + 「再练一次就能看到走势」
3. e1RM 页无点 → 「还没有可用于换算的组（次数都 > 10）」

**有缺口时**（e1RM 序列里有 null）→ 图下写：
「有 N 次训练没有可用于换算的组（次数 > 10）」，N 取自 `layout.gapCount`

---

## Task 13：界面断言

**新建**：`test/widget/phase2_pages_test.dart`

沿用 Phase 1 的 `settleReal`（假时钟推不动 sqlite 的真 I/O）与两个 provider 的写法
（见 `test/widget/smoke_test.dart` 顶部注释）。

| # | 断言 |
|---|---|
| 1 | ⭐ 历史行显示「1 组 · 160 kg」（1 组 × 20kg × 8 次 = 160） |
| 2 | ⭐ 历史详情**有返回键**、总结页**没有** |
| 3 | ⭐ 动作详情三张卡的文案：`最好` × 2、**`最高` × 1**、`估算 · 仅供参考`、`来自 60 kg × 10` |
| 4 | ⭐ `find.textContaining('个人最好')` **`findsNothing`**（容量不是力量成绩） |
| 5 | 深链没练过的动作 → 「这个动作还没有记录」，且 `takeException()` isNull |
| 6 | 只练过一次 → 「再练一次就能看到走势」 |
| 7 | 空库 → 历史与进步两个列表都显示各自空态 |

---

## Task 14：变异验证总表（**这一节不做完，本期不算完**）

逐条把实现改回错的写法，确认对应测试**变红**，再改回来。
**每条都要记下红出来的实际信息**（哪条测试、什么期望/实际）。

| # | 变异 | 应当变红 |
|---|---|---|
| 1 | `bestE1rm` 改成「取最重那组的 e1RM」 | `progress_test` 用例 2 |
| 2 | `highlightIndex` 改成「最后一个点」 | `chart_geometry_test` 用例 4、5 |
| 3 | y 轴改成从 0 起 | `chart_geometry_test` 用例 3 |
| 4 | `min == max` 时不特判（除零） | `chart_geometry_test` 用例 2 |
| 5 | 聚合查询 `LEFT JOIN` → `JOIN` | `session_summary_list_test` 用例 1 |
| 6 | 去掉 `COALESCE` | `session_summary_list_test` 用例 2 |
| 7 | 去掉 `s.finished_at IS NOT NULL` | `progress_repo_test` 用例 1、`session_summary_list_test` 用例 3 |
| 8 | 总容量卡片「最高」→「最好」 | `phase2_pages_test` 用例 3、4 |
| 9 | 去掉「估算 · 仅供参考」 | `phase2_pages_test` 用例 3 |
| 10 | ~~分组键改回只有 `sessionId`~~ **已在实施时验过** | `progress_test` 用例 11（实测：2 个点变 1 个，`has length of <1>`）|
| 11 | 去掉 `ORDER BY ... s.rowid ASC` | **⚠️ 验不出来** —— 实测本用例仍绿，FFI 的查询计划恰好就是插入序。见 Task 3 的说明 |

> **一条永远绿的守卫等于没有守卫。** Phase 1 靠这条抓到过两条假绿
> （拼音排序的断言、`rowid` 兜底的行序），代价已经付过一次。

---

## Task 15：静态检查与全量测试

```powershell
. C:\ccproject\restart_gymtool\scripts\env.ps1
dart format lib test
flutter analyze      # 期望 No issues found!
flutter test         # 全绿；本期结束时断言总数应 ≥ 175（Phase 1 是 145）
```

规模基准：旧项目 M2 结束时 79 条，M4 结束时 198 条。本期两个里程碑合计**以 ≥ 175 为目标**，
**但不为凑数而写**。

---

## Task 16：Chrome 预览 + 真机验收

**Chrome（开发回路，不是验收）**：`flutter run -d chrome`，走通
「历史列表 → 详情」与「进步列表 → 动作详情三张卡」。

**真机验收** —— 照规格 §7.4 那张表**用手工核算的数字对照屏幕**：

```powershell
adb shell svc power stayon usb     # ⚠️ 不可省：息屏后 screencap 会返回上一帧而不报错
adb shell uiautomator dump
```

| 项 | 期望 |
|---|---|
| 历史行 | `1 分钟 · 1 组 · 160 kg` ← 1 × (20 × 8) = **160** |
| e1RM 卡 | `50 × 8` → 平均 **62.32** → 屏显 **62** |
| 总容量 | `50 × 8 × 4 组` = **1600** |
| 只练过一次 | 一个点不画线 + 「再练一次就能看到走势」 |
| 深链没练过的动作 | 「这个动作还没有记录」，不崩 |

**结果如实写进本文档**（含未通过的项）。旧项目最后一轮 12 项验收全部未做、
在文档里躺了很久 —— 这份作业单的一半理由就是不让它重演。

---

## 完成定义（Definition of Done）

| # | 条件 |
|---|---|
| 1 | `flutter analyze` 无问题 |
| 2 | `flutter test` 全绿，断言数 ≥ 175 |
| 3 | Task 14 的 9 条变异**逐条验过会红**，并把红出来的实际信息记在本文档 |
| 4 | 分层守卫 `test/layering_test.dart` 仍全绿（`chart_geometry.dart` 没 import Flutter） |
| 5 | Phase 1 的 145 条**全部仍绿**（尤其是总结页那条口径断言） |
| 6 | Chrome 预览走通历史与进步两条链路 |
| 7 | 真机验收 5 项**跑过并如实记录** |
| 8 | 界面文案红线的三条（`最好`/`最高`/`估算 · 仅供参考`）有自动化断言守着 |
