# Flutter 健身记录 App —— 设计（Phase 1：骨架与能记一次训练）

- **日期**：2026-10-08
- **状态**：待实施
- **项目目录**：`C:\ccproject\restart_gymtool`
- **上游规格**：[`2026-10-08-gym-tracker-design.md`](./2026-10-08-gym-tracker-design.md)（旧项目总纲，React Native 版；2026-10-08 由项目根目录移入本目录，内容未改）
- **旧项目**：`C:\ccproject\gym`（Expo / React Native，93 个 TS/TSX 文件、18,578 行、已达 M8）
- **本文的定位**：这是**换栈重写**的第一份 spec。它同时承担两件事 —— 一份跨全部 Phase 的**架构总纲**，以及 **Phase 1 的详细范围**。后续 Phase 各写各的 spec。

---

## 1. 为什么重做，以及这次不再付的代价

旧项目已经能用，2026-09-16 起就真的带去健身房练过，库里有过 6 场真实训练。**这次重做不是因为它坏了，是因为要换技术栈。**

因此有一条贯穿全文的原则：

> **凡是旧文档用真机反馈换来的结论，一律保留；凡是旧文档为绕开平台限制而做的妥协，一律重新审视。**

这条原则有两处立刻兑现（§2.5、§5.4），不是口号。

### 1.1 选型翻转的如实记账

旧文档 §3.1 把技术栈选在 Expo，明确记下了代价："界面渲染在手机上，开发过程中看不到画面，UI 迭代依赖用户真机反馈"，并且**另一条否决原生 Android 的理由是"环境需约 10GB 工具链"**。

换 Flutter 就是把这两笔账重新结算：工具链的代价（§8，约 3–4 GB）重新买回来，换来"看不到画面"这条代价的彻底消失。旧项目从"看不到画面"到用网页预览补上，前后用了 19 天（§3.1 原文）；Flutter 的热重载在**第一天**就有，且在**真机上**也有。

### 1.2 红线不变

旧文档的三条红线原样继承，Phase 1 就要守住前两条：

| # | 红线 | 在 Phase 1 的落地 |
|---|---|---|
| 1 | **训练记录永不丢失** | 每完成一组立刻写 SQLite；休息计时用时间戳不用累加器 |
| 2 | **绝不伪造数据** | 算不出的点不画、没有的分留空（Phase 1 主要体现为 e1RM 的 `null` 处理） |
| 3 | 不把估算说成实测 | Phase 1 的总结页文案必须带「粗略参考」 |

---

## 2. 架构与分层

### 2.1 目录结构

```
lib/
  main.dart
  app/                     路由 + 四标签外壳
    router.dart
    app_shell.dart
  features/                界面层，按功能分目录
    workout/               记录页 / 休息 / 总结 / 训练首页
    history/               占位
    progress/              占位
    settings/              外观（主题三态）
  ui/                      纯视觉层：不碰数据库、不含状态
    tokens.dart            颜色 / 字号 / 间距的唯一来源
    theme.dart             ThemeData 装配
    widgets/               基础组件（按钮 / 卡片 / 分段控件…）
  domain/                  纯逻辑，无 IO，且**不得 import Flutter**
    types.dart
    metrics.dart           容量负荷、e1RM
    rest.dart              30 分钟闸门
    rest_advice.dart       组间休息提示
    format.dart            时长 / 重量 / 日期格式化（「今天 15:43」）
  data/
    db/
      sql_executor.dart    接缝接口
      sqflite_executor.dart
      ffi_executor.dart    测试用
      schema.dart          建表 SQL
      migrations.dart      只追加的版本化迁移
    repositories/          ← SQL 只允许出现在这一层
      exercise_repo.dart
      session_repo.dart
      set_repo.dart
      settings_repo.dart
  state/                   编排层
    active_session_controller.dart
    theme_controller.dart
test/
  domain/  data/  state/  e2e/  layering_test.dart
web/                       Chrome 预览的 sqlite3.wasm + sqflite_sw.js
android/
```

**与旧项目分层的一处对应关系**，照着旧代码找位置时用得上：旧项目有 `src/lib/`（无状态工具：格式化、图表几何、文件读写…）这一层。新结构**取消了独立的 `lib/` 层**，按"是不是纯逻辑"拆开归位 ——

| 旧 `src/lib/` 里的东西 | 新位置 | 依据 |
|---|---|---|
| `format.ts`、`sessionLabel.ts` | `domain/` | 纯函数、可单测 → 符合 §2.2 规则 3 |
| `chartGeometry.ts` | 后续 Phase 再定 | 进步曲线是 Phase 2 |
| `backupFile.ts`、`deleteConfirm.ts` | 后续 Phase 再定 | 备份是 Phase 3、删除是 Phase 4 |
| `id.ts` | 由 `uuid` 包取代 | §2.4 |
| `keepAwake.ts` | 由 `wakelock_plus` 取代 | §2.4 |
| **`preview.ts` / `preview.web.ts`** | **删除** | §2.5 |

> 少一层不是目的，**是"纯逻辑必须可单测"这条规则推导出来的结果** —— 旧的 `lib/` 里混着纯函数和有副作用的东西，分不清哪条能被 `dart test` 直接跑到。归位之后，`domain/` 整层都是纯的。

### 2.2 三条分层规则 —— 这次由**会失败的测试**守

旧文档 §5.1 把这三条写成"硬性规则"，但旧项目**只靠约定**：

1. `features/` 与 `ui/` 永不直接 import `data/db/`，只经 `data/repositories/`
2. SQL 只出现在 `data/repositories/`
3. 纯逻辑只出现在 `domain/`

本次改为 `test/layering_test.dart` —— 扫描源文件 import 的一项测试，违反即失败。

**理由不是洁癖，是旧文档 §4.2 记下的一条教训**："判据两边同时错的时候，只有端到端测试能发现"。约定守不住的东西，让测试守。

### 2.3 `domain/` 不得 import Flutter

旧文档说"可单测是纯逻辑必须留在 `domain/` 的理由"。在 Flutter 里这条能更进一步：**`domain/` 不依赖 Flutter，就能用纯 `dart test` 跑**，不必启动 widget binding，快得多。

因此 `layering_test.dart` 同时断言：`lib/domain/**` 里不出现 `package:flutter/`。

### 2.4 技术选型

| 层 | 选择 | 理由 |
|---|---|---|
| 数据 | `sqflite` + `sqflite_common_ffi` + `sqflite_common_ffi_web` | 三后端同源；见 §3.1 |
| 路由 | `go_router` | 声明式，使用感最接近 expo-router |
| 状态 | `ChangeNotifier` + `provider` | 形状与 Zustand 一致（一个 store 对象带方法）；测试时不需要 widget 树 |
| ID | `uuid` | 对应旧 `lib/id.ts` |
| 常亮 | `wakelock_plus` | 对应旧 `lib/keepAwake.ts` |
| 触感 | **内置 `HapticFeedback`** | 旧项目需装 `expo-haptics`，这里不必 |
| 数字等宽 | **`FontFeature.tabularFigures()`** | 对应旧 `fontVariant: ['tabular-nums']` |

### 2.5 从旧项目整块删掉的东西

| 删掉 | 原因 |
|---|---|
| `db/demoExecutor.ts`（**660 行**） | 按 SQL 形态分发的内存假库。Chrome 预览现在跑真 SQLite，假库没有存在理由 |
| `lib/preview.ts` / `preview.web.ts`（`isWebPreview`） | 它存在是为了**隐藏**假库跑不了的功能。真库能跑就不必藏 —— 计划管理 / 删除 / 导入在预览里将**第一次真正可用** |
| jest / babel / metro 配置 | 换栈 |
| expo-router typedRoutes 的生成顺序绕路（旧文档 §7.3） | 不存在了 |

> **一个保留的例外**：备份的导出/导入要读写**文件**，web 上走下载/上传而非文件系统。所以 web 平台分支不会彻底消失，但会从"藏功能"缩小成"换实现"。这属于 Phase 2+ 的问题，此处仅记录以免遗忘。

### 2.6 `SqlExecutor` 保留，但理由变了

旧文档把它当作"仓储不依赖 expo-sqlite"的关键。在 Flutter 里 **sqflite 自身就有 `DatabaseExecutor` 接口，且三个后端实现的是同一个**，所以"隔离具体实现"这层价值下降了。

**仍然保留，但理由换成两条**（这两条必须写进代码注释，否则后人看到会以为它多余）：

1. 它承载**两条自定义语义**：
   - **无参数时要能跑多语句** —— 迁移脚本是多条 `CREATE` 拼成的
   - `first` 一行都没有时返回 `null`（不是 `undefined`/异常），`all` 返回 `[]`（不是 `null`）
2. 它让仓储层完全不出现 sqflite 的类型 —— 将来加云同步时改动面不扩散

接口保持三个方法：

```dart
abstract class SqlExecutor {
  Future<void> run(String sql, [List<Object?>? params]);
  Future<List<T>> all<T>(String sql, [List<Object?>? params]);
  Future<T?> first<T>(String sql, [List<Object?>? params]);
}
```

---

## 3. 数据层

### 3.1 三个后端

| 场景 | 后端 | 说明 |
|---|---|---|
| Android 真机 | `sqflite` | 生产 |
| 单元测试 | `sqflite_common_ffi` + 内存库 | 对应旧项目 `node:sqlite` 的角色，同一套仓储代码两边都跑 |
| Chrome 预览 | `sqflite_common_ffi_web` | 真 SQLite wasm，落 IndexedDB |

**Chrome 预览的定位（继承旧文档 §4.5 的结论，但结论更强）**：

- 旧版预览跑的是**假库**，所以计划管理/删除/导入"点了没反应"，只能把入口藏起来
- 新版预览跑的是**真仓储代码**，这些功能第一次真正可用
- **但它仍然不是验收**。理由从"假库不准"变成"平台差异"：触感、字体度量、息屏行为、以及实验性 web 后端自身的 bug
- ⚠️ `sqflite_common_ffi_web` 被官方标为 **experimental 且 slow，有已知 bug，IndexedDB 绑端口**。这些限制要在文档里写明，避免后人把预览里的异常当成产品 bug

### 3.2 Schema v1

与旧项目 v1 完全一致，四张表。**SQL 原文照搬**（旧文档的原则："公式/SQL 一旦确定不得中途更改"）：

`exercise` / `session` / `session_exercise` / `set_entry`，加 `app_meta`（版本号表，必须是最先建出来的表）。

三点全局约定：

- 三个外键写 `ON DELETE CASCADE`，但**级联生效必须先开 `PRAGMA foreign_keys = ON`**（连接级，建库后立刻打开；测试适配器同样打开）
- 时间一律存**毫秒时间戳**（INTEGER）
- 布尔一律存 0/1

三行索引不可省（`idx_session_finished`、`idx_session_exercise_session`、`idx_set_entry_session_exercise`）。

> **Phase 1 建到 v3**（2026-10-08 修正 —— 本节初版写的是「v3 留给后续 Phase」，与 Task 7 的代码矛盾，实施时被证伪）：
>
> | 版本 | 内容 | 为什么在 Phase 1 |
> |---|---|---|
> | v1 | 四张表 + `app_meta` | 地基 |
> | v2 | `app_setting` | 主题三态要用（§6.5） |
> | **v3** | `ALTER TABLE session ADD COLUMN template_id TEXT` | **Task 7 的仓储代码逐字沿用旧项目，一直在读写这一列**；`WorkoutSession.templateId` 在 Task 1 就进了域类型。不加这一列，Task 7/8 的每一条测试都在 prepare 阶段就炸 |
>
> **注意 v3 只含 `ALTER TABLE` 一句，不含计划的两张表**。分化计划的 `split_template` / `template_exercise` 留到 Phase 4，届时**追加 v4**（不是并进 v3）—— 这正是「只追加，绝不修改已发布的项」那条规则的应用：v3 一旦发布过，再去改它，升到 v3 的库就永远拿不到那两张表。
>
> 与上游设计文档 §4.4 的迁移表编号因此不同（那里 v3 把 `ALTER` 与两张表并在一起）。**是我们拆 Phase 造成的差异，不是抄错**；那边记录的是旧项目一次性做到 M6 的历史。
>
> ⚠️ **一处已知弱点**（实施时记录、未修）：`ALTER TABLE ... ADD COLUMN` 在 SQLite 里**没有 `IF NOT EXISTS`**，不幂等；而 `migrate()` 的语句之间没有事务。若 ALTER 成功、写版本号那步失败，下次启动会以 `duplicate column name` 抛错。窗口只有两条语句之间。Phase 4 加 v4 时若也要 `ALTER TABLE`，这个窗口会再出现一次。

### 3.3 迁移框架

照搬旧实现，规则不变：

- `schema_version` 存在 `app_meta`
- `migrate()` 只跑 `version > current` 的项，升序，每项跑完写入新版本号
- **绝不修改已发布的迁移项** —— 库里 `schema_version` 已是 N 的库不会再跑 vN，改了等于新列永远加不上
- 每项的多条语句**逐条执行、不在同一事务里**，所以单条必须幂等（`CREATE ... IF NOT EXISTS`）
- 全新库 `getSchemaVersion` 返回 0（`app_meta` 都还不存在）

### 3.4 那些不能省的 SQL 细节

**① `rowid` 兜底**

所有按 `started_at` / `finished_at` 排序的查询一律补 `rowid`：

```sql
ORDER BY s.started_at DESC, s.rowid DESC
```

时间戳只有毫秒精度，同毫秒的两场训练会完全并列，此时 SQLite 按扫描顺序返回（**先插入的在前，语义正好反了**）。

> 对应测试**故意不 sleep**，并先断言两行时间戳确实相等，让并列成为**确定事件**。旧项目曾有一条赌时钟的测试，实测 **20 次全量闪 2 次**（差 1 毫秒），改成显式设同一时间戳后 25 次 0 失败。**一条会随机变红的测试比没有测试更危险。**

**② 完成一组要分四步，顺序不可反**

```sql
UPDATE set_entry SET weight = ?, reps = ? WHERE id = ?;   -- 先写数值
UPDATE set_entry SET is_completed = 1, completed_at = ? WHERE id = ?;
UPDATE set_entry SET rest_started_at = ? WHERE id = ?;
INSERT INTO set_entry (...) VALUES (...);                  -- 预建下一组
```

顺序反了（先标完成再写数值），中途失败就会留下"已完成但数值是旧的"记录。

**③ 休息用时间戳相减**

```sql
UPDATE set_entry SET rest_seconds = ?, rest_started_at = NULL WHERE id = ?
-- seconds = max(0, round((now - rest_started_at) / 1000))
```

**绝不用累加器** —— App 被系统挂起后累加器会停，时间戳不会。旧项目真机实测：息屏前 `18:20`，息屏 35 秒后 `19:01`（Δ41 秒 vs 实测等待 40 秒，吻合）。

`endRest` 在该组本来就没在休息时**静默返回**（不写、不抛）—— 界面重复点「开始下一组」不留下脏数据。

**④ 30 分钟闸门走 `cancelRest`，不写 `rest_seconds`**

```sql
UPDATE set_entry SET rest_started_at = NULL WHERE id = ?
```

它与 `endRest` 的区别是刻意的：那段荒唐时长**不是真实休息**，不该作为数据留下来 —— 休息建议要算平均休息时长，一条 8 小时的记录足以把平均值彻底带偏。

闸门判定在 `domain/rest.dart`（纯函数，阈值 30 分钟），清理动作挂在 `loadExercises` 上 —— 因为 `resume` / `startNew` / `addExercise` / `endWorkout` 全都会经过它，**一处覆盖全部**。

---

## 4. 领域层（口径与规则）

### 4.1 容量负荷（volume load）

```dart
/// 只累加 isCompleted 的组
double totalVolumeLoad(List<SetLike> sets) =>
    sets.fold(0, (sum, s) => s.isCompleted ? sum + s.weight * s.reps : sum);
```

**这是口径问题，不是精度问题。** 文献中 "volume" 用法不统一，本 App 一律采用含重量的 volume load 口径，命名上必须叫 `volumeLoad` 而不是 `volume`。界面标注「**总容量（重量 × 次数）**」，且**不与采用其他口径的 App 或研究数据做横向比较**。

### 4.2 估算 1RM

```
e1RM = (Epley + Brzycki + Lombardi) ÷ 3
Epley    w × (1 + r/30)
Brzycki  w × (36 / (37 − r))
Lombardi w × r ^ 0.10
```

| 条件 | 返回 |
|---|---|
| `r < 1` | `null` |
| `r == 1` | `weight`（实测值） |
| `2 ≤ r ≤ 10` | 三公式平均 |
| `r > 10` | **`null`** —— 外推严重失真，**调用方必须不显示** |

取平均是为了**降低单一公式的偏差，不代表更准**。**公式一旦确定不得中途更改** —— 换了公式，进步页的历史曲线会出现无解释的断层（Phase 2+ 的问题，但实现上现在就只留一份）。

返回 `null` 时**不能当 0 处理** —— 0 会被读成"练得很差"，而事实是"这一组不适合换算"。

### 4.3 组间休息提示

**这是粗略参考，不是科学结论。** 只比较本次训练内首组与末组，不跨训练推断、不建统计模型。

| 条件 | kind | 文案 |
|---|---|---|
| `drop ≤ 0` 且（`avgRest ≤ 180s` 或 `null`） | `positive` | `{次数数组} 全程稳住了，节奏合适` |
| `drop ≤ 0` 且 `avgRest > 180s` | `addWeight` | `{次数数组} 全程稳定，平均歇了 X 分 Y 秒 —— 还有余力，可以考虑加重量` |
| `drop == 1` | `extend15` | `末组 {first} → {last}，下次这个动作可以多歇 15 秒` |
| `drop == 2` | `extend30` | `末组 {first} → {last}，下次可以多歇 30 秒` |
| `drop ≥ 3` | `extend30CheckWeight` | `末组 {first} → {last}，多歇 30 秒试试；如果还是掉，可能是重量偏大` |

四条**强制性要求**：

1. **次数数组必须原样显示** —— 只给结论不给原始数字，用户无法核对，也不会相信
2. **必须标注「粗略参考」** —— 不得表述为科学建议或个性化处方
3. 建议增量固定 **15 / 30 秒**两档，不做百分比、不输出"最佳休息时长"
4. 已完成组数 **< 3 时明确沉默**，界面上显示"组数不足 3 组，暂不判断"

**`avgRest` 一条数据都没有时返回 `null` 而不是 0** —— 0 会被判成"歇得很短"，从而给出错误的"加重量"建议。

**为什么必须含正反馈分支**：只挑毛病、从不肯定，用两周就会被无视。

界面按 `kind` 上色/配图标，**不要去解析 `message`** —— 文案改了类型还在，解析文案的代码会静默失效。

---

## 5. 编排层（`ActiveSessionController`）

### 5.1 职责

这一层是**唯一**允许判定"能不能改这场训练"的地方（每个写操作先查 `finishedAt != null`）。界面只管调，不自己判断。

与旧实现的一处**简化**：旧 store 的每个方法都收一个 `exec` 参数，原因是"store 在 React 之外，拿不到 Context"。**Flutter 里没这个限制** —— 在构造函数注入即可，调用签名更干净。

### 5.2 状态与操作

```dart
class ActiveSessionController extends ChangeNotifier {
  bool loading;
  WorkoutSession? session;
  List<ActiveExercise> exercises;   // { sessionExercise, exerciseName, sets }
  int currentIndex;

  Future<bool> resume();
  Future<StartResult> startNew({String? name, String? templateId});
  Future<void> addExercise(String exerciseId);
  Future<void> removeExercise(String sessionExerciseId, RemoveMode mode);
  void setCurrentIndex(int index);
  Future<void> completeCurrentSet(double weight, int reps);
  Future<void> beginNextSet();
  Future<String?> endWorkout();
  void reset();
}
```

Phase 1 只实现其中的 `resume` / `startNew`（不含 template 分支，计划是后续 Phase）/ `addExercise` / `completeCurrentSet` / `beginNextSet` / `endWorkout` / `reset` / `setCurrentIndex`。

> `startNew` 在 Phase 1 走"复制上一次**已结束**训练的动作组合"这条路径。轮转（`domain/rotation.dart`）留到计划那一期，但**调用顺序的约束现在就遵守**（见 5.3），免得后续改动时踩坑。

### 5.3 `startNew` 的调用顺序不可反

```
先探冲突  →  再定计划  →  才建 session
```

旧文档原文：**"定完计划再一次建，是唯一不需要推理的顺序。"** 若先建这一场，它 `finished_at` 还是 NULL、不会污染"最近一场已结束训练"那个查询，但"先建后定"很容易在后续改动里被误用 `listSessions` 之类的接口把这一场算进去。

冲突分支的两个细节：

- **不新建任何东西**，返回 `conflict`
- **必须把那一场连动作带组装进 store**（复用 `resume` 而不是只返回一个 id）—— 只返回 id 的话，界面选「接着练」后记录页会因为 store 里没有 `exercises` 而误判成"这次训练还没有动作"，给用户一个空屏

### 5.4 冲突对话：三按钮的原始设计**可以还原了**

旧文档 §5.2 记着：设计里写的是 `[接着练] [结束它，开始新的] [取消]`，实现被迫改成**两按钮 + cancelable**，原因是 **Android `Alert` 最多三个按钮，且 RN 的映射顺序是 `[neutral, negative, positive]`，三个按钮时必有一个落进加粗主按钮位**——"无论放哪个都是误导"。

**Flutter 里对话框由我们自己绘制，没有这个限制。** 因此本次**还原三按钮的原始设计**。

> 这是 §1 那条原则的第一次兑现：**为绕开平台限制而做的妥协，换栈后要重新审视，而不是照搬。** 两按钮版本之所以"能用"，只是因为被迫；原始设计的信息结构更清楚（"取消"与"结束它"是两个不同性质的选项，值得各占一个按钮）。

### 5.5 `endWorkout` 立刻清内存

```dart
await finishSession(id, now);   // 写 finished_at
reset();                        // 立刻清空内存，不等用户在总结页点"完成"
```

**这不是优化，是修 bug。** "已结束但还是当前训练"这个中间态正是旧项目"主页一直显示继续上次训练"的直接原因 —— 用户从总结页按系统返回键离开时永远走不到清空那一步，而主页只看 store 里有没有 session。

**总结页不受影响**：它按路由参数 `id` **从库里读**，不依赖 store。这样"结束了但没保存"这个中间态就此消失。

收尾细节：结束前若正处于休息中，**把那段休息丢掉（`cancelRest`），不要 `endRest`**。

> 这一句在 2026-10-09 被实测推翻了，原文写的是「先 `endRest`，否则那一组的
> `rest_seconds` 永远是 NULL」。看起来合理，但 `completeCurrentSet` 给**每一组**
> 都开了休息 —— 刚做完最后一组时必然有一段在进行，它的时长是「做完最后一组到
> 按下结束」的间隔，而这个间隔**不可知**（用户可能在收杠铃，也可能已经揣兜里了）。
> 把它写成 `rest_seconds` 就是伪造：实测落库 `[300, 300, 3]`，屏幕上显示
> 「平均歇了 3 分 21 秒」，而用户真歇了 5 分 00 秒；另一组数字里它还把 200 秒那次
> 从 `addWeight` 压成了 `positive`。
>
> 用户若真的歇够了，会先按「开始下一组」—— 那一按把这段休息结掉（`beginNextSet`
> 走 `endRest`），值由用户确认过，此后 `endWorkout` 已经找不到进行中的休息。
> 所以「丢掉」只影响那段不可知的时长。
>
> 与旧设计文档 §503「没有真实的组间休息数据，编一个平均值比留空更糟」一致。

### 5.6 `resume` 恢复练到哪个动作

取这场训练里 **`completed_at` 最大的那一组**，它归属的 `session_exercise` 在列表里的下标就是当时在练的动作（一组都没完成 → 0）。

**纯查询，不加字段、不做迁移。** 正在休息的情况自动落在同一个答案上（`startRest` 就是对刚完成的那一组调用的），不需要第二条判定。

**已知不精确、明确接受**：切到第 4 个动作但一组都没做就被杀 → 会回到第 3 个动作。

`Math.max(0, ...)` 兜住 `findIndex` 返回 -1 的情况 —— 直接拿去当 `currentIndex` 会让记录页取到 `exercises[-1]`，一片空白。

### 5.7 加动作必须预建第一组

```dart
Future<void> addExerciseWithFirstSet(String exerciseId) async {
  final se = await sessionRepo.addExerciseToSession(sessionId, exerciseId);
  final last = await setRepo.getLastPerformance(exerciseId, sessionId);
  await setRepo.addSet(se.id, last.firstOrNull?.weight ?? 20, last.firstOrNull?.reps ?? 8);
}
```

**预建第一组不是可选项。** 记录页靠"还没完成的那一组"确定当前该记哪一组，没有这条待完成记录，`completeCurrentSet` 会直接 `return` —— **用户点「完成这组」毫无反应，一个静默的假死按钮**。

抽成私有函数让 `startNew`（复制上一次）与 `addExercise`（手动加）共用同一条路径。两处各写一遍必然漂移。

### 5.8 防御性闸门

`addExercise` / `completeCurrentSet` / `beginNextSet` 入口加一句"`session.finishedAt != null` 就直接返回"。

正常情况下 `endWorkout` 已清空 store，这一层防的是**将来有人把已结束的训练塞回 store** —— 旧项目那个"同一场训练被接上第二次、第三次"的 bug 就是这么来的。

---

## 6. 界面层

### 6.1 记录页：聚焦当前组

屏幕上只呈现**当前这一组**，拇指永远停在同一个位置，不需要瞄准。

| 布局 | 结论 |
|---|---|
| **B. 聚焦当前组** | ✅ 选定 |
| A. 全览列表（所有组摊开，点行内 ✓） | 点击目标小；单手够不到顶部；改数值需跳转 |
| C. 列表 + 底部常驻操作条 | 屏幕空间紧张，收益不足以抵消复杂度 |

配套：

- 新的一组**预填上次该组的数值**
- 动作名下方常驻「上次这个动作的成绩」（渐进超负荷最需要的信息）
- 「第 N / M 组」的 M 默认沿用上次组数
- 完成时**一次轻微震动**，让用户不用盯着屏幕确认
- 记录全程**屏幕常亮**

### 6.2 数值调整：拖动 + 步进器**并存**

旧文档 §2.2 记着一次被现实推翻的设计：

> 当初设计：大数字拖动调值 → 现实：手上有汗、屏幕可能湿，纯拖动会"想调 2.5kg 却滑过头" → 修正：保留一对缩小的 +/− 做精确微调。

**二者互补而非重复**：拖动管大跨度（20→60），步进器管微调。只是把步进器降为次级视觉。

### 6.3 动作条 + `＋` 弹层

顶部横向动作条（对应旧项目的"换不了动作"功能性缺口）+ `＋` 打开动作选择弹层：**按肌群分组、拼音序、带搜索**。

**`SafeArea` 从第一版就在** —— 旧项目在隐藏导航栏后出现过"动作条压住状态栏"。

### 6.4 视觉规范：力量感 · 暗色仪表盘

**概念**：把界面当成一台测量仪器来设计 —— 核心信息全是数字，**数字就是界面，其余都是标尺**。

**配色：铸铁 + 信号橙**。刻意避开 `#2b7fff` 蓝 / 紫蓝渐变（AI 生成界面的最典型特征）与荧光绿（与健身"安全色"语义冲突）。信号橙同时是杠铃片、警示带、力量器械的颜色。

```dart
// 深色
background #0B0C0E   // 近黑，不用纯黑 —— 纯黑在 OLED 上和边框糊在一起
surface    #141619 / #1C1F24   // 二级 / 按压态
accent     #FF6A1A
success    #32D74B
danger     #FF453A
text       #F2F4F7 / #9BA1AC / #656B76
border     #2A2E35

// 浅色：同色相映射，不是简单反色
background #FAFAF8   // 暖白
accent     #E4580A  // 略深一档的橙
```

**字体：系统优先 + `FontFeature.tabularFigures()`，不引第三方字体文件。** 中文字体动辄 5–10MB 会拖慢启动；引拉丁数字字体则会制造中西混排差异。**品牌感靠排版、间距、颜色做，不靠字体文件。**

字号尺度（`ui/tokens.dart` 是唯一来源，**界面不写裸数值**）：

```
display 84  记录页那个超大数字     clock 76  休息计时的钟面
stat 30     统计块里的主数字       h1 30     页面大标题
h2 22       区块标题              title 17  列表行主文本、按钮
body 15     正文                  caption 13 次要说明、元信息
label 11    分组小标题、单位标注（通常配 letterSpacing）
```

> 设计阶段写的是 `display 88`，落地时收敛到 **84**，并**多出一档 `clock 76`** —— 休息计时的钟面与记录页的大数字是两个不同尺寸，共用一个 `display` 会让其中一处偏大或偏小。

**动效只做两处，不做入场动画**（健身房要的是"立刻可用"，不是"好看地出现"）：

1. 数字变档的微反馈（补足触觉反馈的视觉确认）
2. 休息计时的呼吸点（告诉用户"它真的在走"，而不是静止的 `00:00`）

两者都**尊重系统"减弱动态效果"**（Flutter 里用 `MediaQuery.disableAnimations`）。

### 6.5 主题三态（Phase 1 交付）

```
system | light | dark
```

**必须是三态，不是布尔**：布尔（深/浅）表达不了"跟随系统"，而它才是默认值、也是大多数人想要的；做成布尔就得额外加一个"是否自动"的开关，两个控件互相耦合，比一个三选一更难用。

四条实现约定（照搬旧文档 §5.6）：

1. 偏好存 `app_setting`（迁移 v2）
2. **非法值退回 `system`** —— 主题读不出来不该让 App 起不来
3. **先改内存再写库**，写库失败不回滚（用户在设置页点一下必须立刻变色）
4. 偏好读出来之前**不放行子树** —— 否则每次启动都会闪一帧

---

## 7. 测试与验收

### 7.1 三层验证

| 层 | 规模目标 | 跑法 | 能抓 | 抓不到 |
|---|---|---|---|---|
| **分层单测** | domain / repositories / state | `flutter test` + `sqflite_common_ffi` 内存库 | 各层各自的正确性 | 层与层之间假设不一致 |
| **端到端回归** | 一条链串起 5 条主旅程 | `flutter test test/e2e/` | 用户实际走的那条链 | 渲染、手势、原生模块 |
| **真机验收** | 见 §7.3 | adb 驱动 + 截图取证 | 手感、原生差异、真实数据 | 费时且不可自动化 |

**为什么必须有第二层**（旧文档 §6.1）："按计划开训练 → 练完 → 结束 → 再看轮转"这一条链跨了 5 处模块，而没有任何一个分层测试覆盖它。旧项目**第一次跑就抓出一个分层测试没抓到的问题**（判据写岔，且分层测试里那条用例同时写错了同一个判据）—— **两边同时错的时候，只有端到端能发现。**

**规模基准**：旧项目 M2 结束时是 **10 套件 / 79 条断言**。这次的 Phase 1 覆盖同等边界，**以 79 条为下限参考**，但不为凑数而写。

### 7.2 测试纪律（每条都是踩出来的）

- **不写会随机变红的测试** —— 时间相关断言必须显式固定时间戳，不依赖"两次调用恰好落在同一毫秒"
- **纯逻辑不留在带 Widget 的文件里** —— 旧项目对应的是"纯逻辑留在带 JSX 的文件里等于永远测不到"；遇到这种情况是把函数移进 `domain/`，不是去改测试基础设施
- **分层规则由 `layering_test.dart` 守**（§2.2）
- 端到端测试放在 `test/e2e/`，日常 `flutter test` 可以排除它以免拖慢反馈

### 7.3 验收标准 = 旧 M2 那份清单逐条重跑

旧项目 `m2-acceptance-checklist.md` 是它**唯一一份全部勾完**的验收清单，且标准本身可判定，直接沿用：

**成功标准 1 — 一组做完到记录完成 ≤ 2 次点击**
- 点「✓ 完成这组」即完成记录（1 次点击）
- 点「开始下一组」回到记录态（1 次点击）
- 全程无需手动输入数字（数值预填上一组）
- 数值可用**拖动**调整，不必一下下点加减

**成功标准 2 — 记录过程不打断训练节奏**
- 训练期间屏幕保持常亮
- 完成一组有轻微震动反馈
- 组间休息是**正计时**，不催促
- 换动作不必退出记录界面

**成功标准 3 — 训练记录永不丢失 ⭐**
- 完成 3 组后强杀 App，重开后「继续上次训练」出现
- 进入后已完成的组数正确
- **息屏挂起后计时仍然准确**（旧项目实测：息屏前 `18:20`，息屏 35 秒后 `19:01`，Δ41 秒 vs 实测 40 秒）

**成功标准 4 — 结束后能看到次数对比与粗略提示**
- 顶部三个数字：时长 / 总组数 / 总容量
- 卡片第一行是**原始次数数组**
- 提示文案与次数数组一致
- 页面标注了**「粗略参考」**
- 少于 3 组显示「组数不足 3 组，暂不判断」

**数据落地检查**
- 点「保存这次训练」后回到训练页
- 训练页**不再显示**「继续上次训练」
- 重启 App 后无残留进行中的训练
- 从零建库：清空 App 数据后重新打开，4 张表 + 52 个动作全部建出

### 7.4 真机验收的两条方法论（照搬，别重踩）

```powershell
adb shell svc power stayon usb     # USB 连接时不息屏
adb shell uiautomator dump         # 拿节点树核对前台窗口
```

> **真机自动化截图会被息屏骗到。** 手机自动锁屏后 `adb shell screencap` 会返回**上一帧而不是报错** —— 旧项目因此拿到过一张和半小时前**哈希完全相同**的"新"截图，并一度据此得出错误结论。

另外：`adb shell screencap` 拉回本地看图，**不要用 `exec-out ... > file.png`**（PowerShell 会破坏二进制流）。

---

## 8. 环境搭建（Phase 1 的前置）

这台机器上 **Flutter / Dart / JDK / Android SDK 四样全无**，磁盘 166 GB 可用，Flutter 官方源、pub.dev、国内镜像均可达（支持断点续传）。

| 组件 | 版本 | 备注 |
|---|---|---|
| Flutter SDK | **3.47.6 stable**（Dart 3.13.5，2026-10-01） | 官方源已验证可达 |
| JDK | 17+ | Android 构建需要 |
| Android SDK | cmdline-tools + platform + build-tools | 用 `sdkmanager` 装，避免 Android Studio |
| Chrome | 已有则直接用 | Chrome 预览通道 |

**已知风险**（继承旧文档 §9，需在实施时逐条验证是否仍然成立）：

- 子进程管道 stdio 可能被禁 → `flutter test` 可能需要 `--concurrency=1`
- 沙箱外的家目录可能不可写 → 需要把 `USERPROFILE` / `HOME` / `APPDATA` / `LOCALAPPDATA` 指向工作区内目录（旧文档记着踩过五个位置：`.expo`、`.android`、`.gradle`、`AppData\Roaming\eas-cli-nodejs`、`_npx`）
- 网络下载量上限 → 大件下载（Flutter SDK ~1GB、Android SDK ~2–3GB）需分段验证

**真机调试的标准流程**（旧文档流程的 Flutter 版）：

```
adb 常驻后台 → flutter devices 确认 → flutter run -d <device> → 改代码走热重载
                                              ↓
                              adb shell screencap 拉回本地看图
```

---

## 9. Phase 1 明确不做 / 已知限制

### 9.1 不做（各自后续开 spec）

| 项 | 归属 |
|---|---|
| 历史列表 / 详情 | Phase 2 |
| 进步曲线（三张卡） | Phase 2 |
| 备份导出 / 导入（格式 v2） | Phase 3 |
| 分化计划与轮转、计划管理界面 | Phase 4 |
| 删除训练 / 删除训练里的动作 | Phase 4 |
| CSV 导入（Strong / Hevy / 训记） | Phase 3 |
| 饮食热量、云同步、账号、社交、排行榜 | 明确划到范围外 |

### 9.2 已知限制（明确接受）

- **Chrome 预览不是验收**（§3.1）—— 触感、字体度量、息屏行为、web 后端自身的 bug 都覆盖不到
- **`sqflite_common_ffi` 与 `sqflite` 的实现差异**覆盖不到
- **`resume` 的不精确场景**：切到第 4 个动作但一组都没做就被杀 → 会回到第 3 个动作（§5.6）
- **Phase 1 没有备份** —— 数据只有设备本地一份。用户已知悉并选择按旧项目顺序推进（导入/备份在 Phase 3）
- **「进行中的训练」不加时间上限** —— 这条旧文档 §10.1 记的**未解决问题**原样继承。理由是"正常流程下不会留下未结束的训练"，但**存量异常数据是例外**。新 App 从空库开始，不存在存量问题，因此**本 Phase 不受影响**；但这条决定本身仍未被解决，若后续出现同类现象需重新考虑

---

## 10. 后续 Phase 的拆分原则

沿用旧文档的原则：**每一段单独可用**，各自有可判定的验收项。

顺序不可颠倒的理由（若将来调整，需重新论证）：

- 备份导入格式需要先有稳定的 schema
- 进步曲线依赖已完成组的口径（§4.1、§4.2 的公式必须先冻结）
- 计划的删除依赖与计划同一次的迁移

> **一处与旧项目顺序的偏离，已由用户确认并记录**：旧项目是 M3历史 / M4进步 → M5备份 / M8导入。本次**保持同样顺序**，不提前导入。代价是用户在 Phase 1–2 期间新练的数据没有备份 —— 这是被明确知悉并接受的（§9.2）。

---

## 附：口径速查

写代码、改文案时，这一节是查证口径的唯一去处。

| 说法 | 精确定义 | 界面必须带的话 |
|---|---|---|
| **容量负荷 / volume load** | `Σ(weight × reps)`，只累加 `is_completed = 1` 的组 | 「总容量（重量 × 次数）」 |
| **估算 1RM（e1RM）** | `(Epley + Brzycki + Lombardi) ÷ 3`，只在 `2 ≤ r ≤ 10` 计算 | 「估算 · 仅供参考」+ 来自哪一组 |
| **个人最好** | 只用于最大重量与 e1RM | 容量那张卡写「最高」，**不写「个人最好」** |
| **组间休息** | 本组做完到下一组开始之间的时长，存在**本组**上；用时间戳算 | 「粗略参考」；建议增量固定 15 / 30 秒 |
| **进行中的训练** | `session.finished_at IS NULL` 且 controller 里 `finishedAt == null` 的那场 | 「继续 \<日期时间\> 的训练」 |
