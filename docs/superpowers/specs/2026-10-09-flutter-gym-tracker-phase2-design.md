# Flutter 健身记录 App —— 设计（Phase 2：历史与进步）

> **上游**：[`2026-10-08-gym-tracker-design.md`](./2026-10-08-gym-tracker-design.md)（旧 RN 版总纲）
> **上一期**：[`2026-10-08-flutter-gym-tracker-design.md`](./2026-10-08-flutter-gym-tracker-design.md)（Phase 1）
> **实施计划**：[`../plans/2026-10-09-phase2-history-and-progress.md`](../plans/2026-10-09-phase2-history-and-progress.md)

---

## 1. 范围

### 1.1 交付什么

| # | 内容 | 旧项目对应 |
|---|---|---|
| 1 | **历史列表**：日期 / 名称 / 时长 / 组数 / 容量，最近的在前 | M3 |
| 2 | **历史详情**：与总结页**共用同一套视觉** | M3 |
| 3 | **进步列表**：练过的动作按最近练过倒序，行上「最近一次日期 · 最重的一组」+ 迷你走势 | M4 |
| 4 | **动作详情**：横向分页**三张卡**（最大重量 / 估算 1RM / 总容量），各带最好值、日期与折线 | M4 |

**出口判据**：练完几次之后打开 App，能回答两件事 ——「我上次是怎么练的」与「我有没有在进步」。

### 1.2 明确不做（各自后续开 spec）

- **备份 / 导出 / 导入**（旧 M5/M8）—— **这是本项目唯一会永久损失用户资产的缺口**，
  它的验收必须是对抗性的，不能顺带做。代价已在 Phase 1 写明并接受：数据只有设备本地一份。
- **分化计划与轮转**（旧 M6）、**删除记录**（旧 M7）。
- **跨训练统计推断**：不建模型、不预测、不输出「你的最佳休息时长」。理由见总纲 §3.7。
- **进步页的时间窗**：「最好」= **历史最好**。总纲 §8 已否决「最近 90 天」——
  用户数据量还小，加窗口只会让他以为自己退步了。

### 1.3 与 Phase 1 的关系

**复用（不改口径）**：

- `domain/metrics.dart` 的 `totalVolumeLoad` 与 `estimateOneRepMax` —— **一行都不改**。
  总纲 §3.6 写死了这条：换了公式，进步页的历史曲线会出现**无解释的断层**。
- `domain/format.dart` 的 `formatDate` / `formatDuration`。
- `domain/rest_advice.dart` 的提示五分支，历史详情原样复用。
- Phase 1 的 `tokens.dart` / `theme.dart` / 基础组件。

**要改的**：

- `SummaryPage` 里那段渲染逻辑**抽成 `SessionSummaryView`**，总结页与历史详情共用。
  **两处各写一遍是不允许的** —— 口径字样一旦分叉，就会有一处悄悄写歪。
- `features/history/history_page.dart` 与 `features/progress/progress_page.dart`
  现在是占位页（「将在下一期交付」），本期内替换。

---

## 2. 领域层（`domain/`，不 import Flutter）

新增两个文件，**全是纯函数**，可以用 `dart test` 跑。

### 2.1 `domain/progress.dart` —— 把组折算成「每场一个点」

```dart
/// 一条「已完成组」的事实。仓储查出来就是它，之后全在 Dart 里算。
class SetFact {
  final String exerciseId;
  final String sessionId;
  final int sessionStartedAt;   // 排序与显示日期用
  final double weight;
  final int reps;
}

/// 一场训练里的一个点。**一次训练 = 一个点。**
class SessionPoint {
  final String sessionId;
  final int startedAt;
  final double topWeight;        // 那一次最重的一组
  final int topWeightReps;       // 并列时取次数多的那一组
  final double? bestE1rm;        // 那一次所有可换算组里最好的一个；全不可换算时为 null
  final double? e1rmWeight;      // 这个 e1RM 来自哪一组 —— 界面要写出来
  final int? e1rmReps;
  final double volumeLoad;       // 那一次的 Σ(重量 × 次数)
}

List<SessionPoint> buildSessionPoints(List<SetFact> facts);
```

**四条容易做错、必须用真实数字锁住的语义**（全部来自总纲 §5.5）：

| # | 语义 | 反例（写错时会怎样） |
|---|---|---|
| 1 | **一次训练 = 一个点**，同一次里每组各算各的、取最好的那个 | 按组画点 → 一天之内来回锯齿，看不出「进步」 |
| 2 | **高亮点是「最大值」，不是「最新值」** | 容量在掉的时候，绿点该落在**更早**的那一次 |
| 3 | **「最佳 e1RM」不一定来自「最重的那一组」** | `60×10` 的 e1RM（**78.51**）**高于** `70×3`（**76.42**）—— 尽管后者更重 |
| 4 | **总容量写「最高」不写「个人最好」** | 容量是训练量不是力量成绩，练得少但更重的日子容量反而更低 |

**第 3 条要按实际公式核对，不能凭直觉**。算一遍（这组数字已用脚本核过，别手算）：

```
60 × 10 →  r = 10，可换算
  Epley     60 × (1 + 10/30)   = 80.0000
  Brzycki   60 × 36 / 27       = 80.0000
  Lombardi  60 × 10^0.1        = 75.5355
  平均                          = 78.5118   → 屏显 79

70 × 3 →   r = 3
  Epley     70 × (1 + 3/30)    = 77.0000
  Brzycki   70 × 36 / 34       = 74.1176
  Lombardi  70 × 3^0.1         = 78.1286
  平均                          = 76.4154   → 屏显 76
```

**`60×10` 的 e1RM（78.51）确实高于 `70×3`（76.42）**，尽管后者更重。
测试里就用这两个数字锁住 —— 只要实现写成「取最重那组的 e1RM」，这条就红。

> ⚠️ **这两个数差得不多（2.7%），手算极易算错。** 本文件的第一版就把它算错了
> （Lombardi 一项写成了 75.474 / 78.832，两个都是错的），靠脚本复核才抓出来。
> **凡是要写进文档当判据的数字，一律用脚本跑一遍再由脚本给出的值填。**

**第 1 条的实现要求**：`buildSessionPoints` 的输入顺序**不能依赖**，必须自己按
`sessionStartedAt` 再按 `sessionId` 稳定排序；且同一场训练的多条 `SetFact`
必须被聚成一个点。

**次数 > 10 的组怎么办**：`estimateOneRepMax` 返回 `null`。若某一场**所有组**的次数都 > 10，
这一场在 e1RM 序列上**没有点**（`bestE1rm == null`）——
**不补 0**（0 是「练得很差」，事实是「这一场不适合换算」）、**不补估算**（正是被禁止的外推）。
曲线**直接连过去**，并在图下写一句说明（见 §5）。

### 2.2 `domain/chart_geometry.dart` —— 折线几何

把「一串数值 + 画布尺寸」算成「该画在哪几个坐标」。纯函数，与 Flutter 无关
（`Offset` 是 `dart:ui` 的，因此这里用两个 `double` 组成的 `ChartPoint`，
**不要 import Flutter**）。

```dart
class ChartPoint { final double x, y; final int index; }

class ChartLayout {
  final List<ChartPoint> points;   // 已按 x 升序
  final int? highlightIndex;       // 最大值那一个；全空时为 null
  final double minValue, maxValue;
}

ChartLayout layoutChart({
  required List<double?> values,  // null = 这一场没有可用于换算的组
  required double width,
  required double height,
  double insetY = 12,
});
```

三条规矩：

1. **x 轴按索引等距**（一次训练一格），**不按时间**。
   理由：这张图回答的是「我一次比一次强吗」，不是「我几月几号练了多少」。
   按时间画的话，一周练五次再歇三周，前面五次会挤成一坨。
   代价（明确接受）：**看不出中间歇了多久**。这是取舍，不是疏忽。
2. **y 轴取 `min..max`，不强制从 0 开始**。进步曲线关心的是变化量，从 0 起会把变化压平。
   代价（明确接受）：**看起来涨得比实际猛**。所以图上**不画 y 轴刻度**，
   数值一律由卡片头上的「最好值 · 日期」给出 —— 图只表达走势。
3. **全等值时**（`min == max`，比如连续三次都是 60kg）：全部点画在**竖直居中**，
   不除零、不画在底边。**底边会被读成 0。**

**`null` 的处理**：跳过不画，但**线要连过去**（相邻两个非 null 点直接连）。

**高亮点的取法**：`highlightIndex` = 最大值所在的**第一个**下标。
并列时取最早的 —— 语义是「你**第一次**做到这个数」。

---

## 3. 数据层

### 3.1 一条 SQL，两个调用方

总纲 §4 的纪律「一次全取、在 Dart 里分组」，出处是旧项目 `sessionRepo` 的注释：
**N+1 查询在手机上会肉眼可见地卡**。

进步页的两个界面（动作列表、动作详情）**共用同一次查询**：

```dart
/// 取**所有**已完成组的原始事实（跨全部训练、全部动作）。
///
/// 一条 SQL 解决动作列表 + 动作详情 + 迷你走势三处，之后全在 Dart 里分组。
/// 不按动作逐个查 —— 那是 N+1，在手机上会肉眼可见地卡。
Future<List<SetFact>> listAllCompletedSetFacts(SqlExecutor exec);
```

```sql
SELECT se.exercise_id            AS exercise_id,
       s.id                      AS session_id,
       s.started_at              AS session_started_at,
       st.weight                 AS weight,
       st.reps                   AS reps
  FROM set_entry st
  JOIN session_exercise se ON se.id = st.session_exercise_id
  JOIN session s           ON s.id  = se.session_id
 WHERE st.is_completed = 1
   AND s.finished_at IS NOT NULL
 ORDER BY s.started_at ASC, s.rowid ASC, se.position ASC, st.rowid ASC
```

**三处 `WHERE` 都不能省**：

- `st.is_completed = 1` —— 占位组（`is_completed = 0`）留在库里是刻意的，靠这个标记排除。
- `s.finished_at IS NOT NULL` —— **进行中的那一场不能进历史与曲线**。
  否则用户练到一半切到进步页，会看见一个每做一组就往上跳的点。
- `ORDER BY` 里的 `rowid` 兜底 —— 总纲 §4.3，毫秒同刻的会完全并列。

**规模**：不设 LIMIT。个人训练日志是有界的（每周 3–4 场 × 每场 20 组 ≈ 每年 4000 行），
全量装载换来了「一次 SQL、三处复用」。**若哪天超过约 2000 场，再回来加窗口** ——
到那时「不设时间窗」也该重新讨论了。这条写在这里，是为了将来的人知道我们**想过**。

### 3.2 历史列表：一条聚合查询

```sql
SELECT s.id, s.name, s.started_at, s.finished_at,
       COUNT(st.id)                        AS set_count,
       COALESCE(SUM(st.weight * st.reps), 0) AS volume_load
  FROM session s
  LEFT JOIN session_exercise se ON se.session_id = s.id
  LEFT JOIN set_entry st ON st.session_exercise_id = se.id
                        AND st.is_completed = 1
 WHERE s.finished_at IS NOT NULL
 GROUP BY s.id
 ORDER BY s.started_at DESC, s.rowid DESC
```

- **`LEFT JOIN` 不能改成 `JOIN`** —— 一场一个动作都没加就结束的训练（0 组）
  必须仍然出现在历史里，显示「0 组 · 0 kg」。改成内连接它会**凭空消失**。
- **`COALESCE(..., 0)` 不能省** —— 没有组时 `SUM` 是 `NULL` 不是 0，
  界面会显示「null kg」。
- 时长 = `finished_at - started_at`，与 Phase 1 总结页**同一个算法**（同一份 `domain/`）。

### 3.3 动作列表需要的东西

从 §3.1 那一次查询的结果里，在 Dart 里算出：

- 每个动作的「最近一次训练时间」→ 倒序排列
- 该次训练里「最重的一组」（并列取次数多的）
- 迷你走势 = 该动作最近 N 个 `SessionPoint`（N = 12，够画一个走势）

**没有任何已完成组的动作不出现** —— 那是「还没记录」，不是「0」。

---

## 4. 界面层

### 4.1 历史列表

每行：

```
9月16日 周三
未命名训练
1 分钟 · 1 组 · 160 kg
```

- 日期用 `formatDate`，名称用 `session.name ?? '未命名训练'`
- 点进 `SessionDetailPage`
- **空态**：「还没有已完成的训练」+ 一句「完成第一次训练后，这里会留下记录」

### 4.2 历史详情 = 总结页

把 `SummaryPage` 的渲染主体抽成 `lib/ui/widgets/session_summary_view.dart`：

```dart
class SessionSummaryView extends StatelessWidget {
  final SessionSummary summary;
  const SessionSummaryView({required this.summary, this.footer});
}
```

`SessionSummary` 是**已算好的值**（不是 widget、不是 Future）：

```dart
class SessionSummary {
  final WorkoutSession session;
  final List<ExerciseSummary> exercises;  // 空动作不上总结页
  final int durationSeconds;
  final int totalSets;
  final double volumeLoad;
}
```

装载函数 `loadSessionSummary(exec, sessionId)` 放在 **data 层**（要读库）。
两页各自：

| 页 | AppBar | footer |
|---|---|---|
| `SummaryPage` | **无返回键**（`automaticallyImplyLeading: false`）—— 结束是不可逆的，这里只给一个出口 | 「完成」按钮 → `/` |
| `SessionDetailPage` | **有返回键** | 无 |

**两页的正文逐像素一致**，因为它们就是同一个 widget。

### 4.3 进步列表

每行：动作名 / 「最近 8月20日 · 最重 60 kg × 8」 / 右侧迷你走势（`TrendChart(compact: true)`）。

### 4.4 动作详情：横向分页三张卡

`PageView` 三页，顶部有页码点。每张卡：

```
┌──────────────────────────────────┐
│ 最大重量                          │
│ 62.5 kg          最好 · 9月16日   │   ← 最大重量 / e1RM 用「最好」
│ [ 折线 + 圆点 ]                   │
└──────────────────────────────────┘

┌──────────────────────────────────┐
│ 估算 1RM                          │
│ 79 kg            最好 · 9月16日   │   ← 同样是「最好」
│ 估算 · 仅供参考                    │   ← 强制
│ 来自 60 kg × 10                   │   ← 强制：这一场的 e1RM 取自哪一组
│ [ 折线 + 圆点 ]                   │
└──────────────────────────────────┘

┌──────────────────────────────────┐
│ 总容量                            │
│ 1600 kg          最高 · 9月16日   │   ← **「最高」，不是「最好」**
│ [ 折线 + 圆点 ]                   │
└──────────────────────────────────┘
```

**措辞逐字固定，不得同义替换**（总纲 §5.5 与 §12）：

| 卡片 | 头上的字 | 必须是 |
|---|---|---|
| 最大重量 | `最好 · <日期>` | 不得写「个人最好」以外的变体 |
| 估算 1RM | `最好 · <日期>` + `估算 · 仅供参考` + `来自 W kg × R` | 三样缺一不可 |
| 总容量 | **`最高 · <日期>`** | **不得写「最好」、更不得写「个人最好」** |
| 区块 | 组间休息回顾（`粗略参考`） | 沿用 Phase 1 |

### 4.5 `TrendChart`：手绘折线 + 圆点

**不引图表库**（总纲 §8 已否决：这里只有折线和圆点，引库反而要跟它的样式打架）。
一个 `CustomPainter`，画：

1. 折线 —— `Path` 连接 `layoutChart` 给出的点
2. 圆点 —— 每点一个，`highlightIndex` 那个用 `c.success` 且更大
3. **不画**坐标轴、网格线、刻度（理由见 §2.2 第 2 条）

`compact: true` 时只画线 + 最后一点，用于列表行的迷你走势。

### 4.6 路由

```
/history/:sessionId      历史详情（在外面，占满全屏，带返回键）
/progress/:exerciseId    动作详情（同上）
```

`/history` 与 `/progress` 已经在标签外壳里（Phase 1 就建好了），本期只是把占位页换掉。

---

## 5. 两处必须写的说明文案

**e1RM 卡在图下**（仅当该动作有「没有可用于换算的组」的训练时出现）：

> 有 N 次训练没有可用于换算的组（次数 > 10）

**数量与措辞都是硬要求**：说清**次数**、说清**为什么**（次数 > 10）。
不写「部分数据缺失」这种含糊说法 —— 用户看不懂，也核对不了。

---

## 6. 空态与稀疏态（每一档都要有专门文案）

**真话比好看的图重要**（总纲 §10.3）。数据少的时候图确实不像图，
**不许拿假数据把它填满，也不许画一条平的线假装有走势。**

| 情形 | 文案 |
|---|---|
| 历史列表一场都没有 | 「还没有已完成的训练」 |
| 进步列表一个动作都没有 | 「还没有练过的动作」 |
| 动作详情：这个动作**从没练过**（深链进来的） | 「这个动作还没有记录」—— **不崩** |
| 动作详情：**只练过一次** | 一个点，**不画线** + 「再练一次就能看到走势」 |
| e1RM 卡：该动作所有场次的次数都 > 10 | 一个点都没有 + 「还没有可用于换算的组（次数都 > 10）」 |

---

## 7. 测试与验收

### 7.1 分层测试（沿用 Phase 1 的三层）

- **`domain/`**：纯 `dart test`。`progress.dart` 与 `chart_geometry.dart` 是主战场。
- **`data/`**：`sqflite_common_ffi` 内存库。重点是上面那两条 SQL 的
  `LEFT JOIN`、`COALESCE`、`finished_at` 过滤、`rowid` 兜底。
- **`test/layering_test.dart`**：新增文件不得破坏三条规则
  （`domain/` 不得 import Flutter —— 这条对 `chart_geometry.dart` 最容易破功）。
- **界面**：`test/widget/` 里补冒烟，重点是**口径字样**（§4.4 那张表逐字断言）。

### 7.2 每条守卫都要证明会红

写完之后，把实现**改回错的写法**，确认对应测试变红，再改回来。至少要验这几条：

| 变异 | 应当变红的测试 |
|---|---|
| `buildSessionPoints` 改成「取最重那组的 e1RM」 | `60×10` vs `70×3` 那条 |
| `highlightIndex` 改成「最后一个点」 | 「高亮点是最大值不是最新值」那条 |
| 聚合查询 `LEFT JOIN` → `JOIN` | 0 组训练仍出现在历史里那条 |
| `COALESCE` 去掉 | 0 组训练显示 `0 kg` 而不是 `null kg` 那条 |
| 去掉 `finished_at IS NOT NULL` | 进行中的训练不进历史那条 |
| 总容量卡片文案「最高」→「最好」 | 口径字样那条 |

> **一条永远绿的守卫等于没有守卫。** 这条纪律在 Phase 1 抓到过两条假绿
> （拼音排序、`rowid` 兜底），代价已经付过。

### 7.3 Chrome 预览（开发回路，**不是验收**）

```
历史列表 → 详情；进步列表 → 动作详情三张卡
```

### 7.4 真机验收（数字必须手工核算）

```powershell
adb shell svc power stayon usb     # ⚠️ 不可省
adb shell uiautomator dump
```

**照总纲 §5.5 的真实数字逐条核**：

| 项 | 期望 |
|---|---|
| 历史行 | `9月16日 周三 / 未命名训练 / 1 分钟 · 1 组 · 160 kg` ← 1 组 × (20 kg × 8) = **160** |
| e1RM 卡 | `50 kg × 8` → Epley 63.33 / Brzycki 62.07 / Lombardi 61.56 → 平均 **62.32**，屏显 **62** |
| 总容量 | `50 × 8 × 4 组` = **1600** |
| 只练过一次 | 一个点不画线 + 「再练一次就能看到走势」 |
| 没数据时 | 空态文案 |
| 深链没练过的动作 id | 「这个动作还没有记录」，**不崩** |

---

## 8. 决策台账（含被否决的选项）

| 决策点 | 选择 | 被否决项与原因 |
|---|---|---|
| 图表实现 | **手绘 `CustomPainter`** | 引图表库（这里只有折线和圆点，引库要跟它的样式打架）—— 沿用总纲 §8 |
| x 轴 | **按索引等距**（一次训练一格） | 按时间等距（一周练五次再歇三周会把那五次挤成一坨） |
| y 轴 | **`min..max`，不强制从 0** | 从 0 起（会把变化压平）；画 y 轴刻度（那就得为「不从 0 起」辩护，而图只需要表达走势） |
| 「最好」的时间窗 | **不设，= 历史最好** | 「最近 90 天」—— 用户数据量还小，加窗口只会让他以为自己退步了。沿用总纲 §8 |
| 并列时的「最好·日期」 | **取最早的那一次** | 取最近一次（「你第一次做到这个数」比「你上次也做到了」更像一条记录） |
| e1RM 缺点 | **缺点 + 一句说明，线连过去** | 补 0（0 是「练得很差」）；补估算（正是被禁止的外推）—— 沿用总纲 §5.5 |
| 进步页取数 | **一条 SQL 全取，Dart 里分组** | 按动作逐个查（N+1，手机上肉眼可见地卡）—— 沿用旧 `sessionRepo` 的注释 |
| 历史列表上限 | **不设 LIMIT** | 分页/加载更多（个人日志有界；为不存在的数据量加机制） |
| 累计进度条的「历史最好」标注 | **只在动作详情给，列表行不给** | 列表行给（一行塞不下口径，挤掉的是动作名） |

---

## 9. 已知限制（明确接受）

- **e1RM 曲线会缺点**：整场次数都 > 10 的训练没有点。不补 0、不补估算，只加一句说明。
- **数据少时只有两三个点**，看起来不像「曲线」。**真话比好看的图重要**，空态与稀疏态都有专门文案。
- **x 轴不表示时间**：看不出两次训练之间歇了多久。取舍见 §2.2。
- **y 轴不从 0 起**：变化的视觉幅度比实际大。所以**不画刻度**，数值只由卡片头的文字给出。
- **Phase 2 仍然没有备份**：数据只有设备本地一份。备份是 Phase 3，且它的验收必须是对抗性的。
