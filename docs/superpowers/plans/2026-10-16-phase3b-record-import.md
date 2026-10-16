# Phase 3B：CSV 导入与手动补记录 Implementation Plan

> **状态：2026-10-16 已按用户「开始实现」接入功能，自动化与真实浏览器通过；Android 真机验收待设备。实际任务分组、合并测试位置和未执行项见 [执行记录](./2026-10-16-phase3b-phase4-execution.md)。以下细项保留原实施方案，不将未按原命令逐条执行的步骤追记为通过。**
>
> **For agentic workers:** 按 Task 0–8 顺序实施，每个任务先写会失败的测试、确认失败，再实现并验证。复选框必须按实际结果回填。工作区中的用户文件不能混入提交。

**Goal:** 把 Strong、Hevy、训记 CSV 与手动补记转换为同一种训练结构，经可核对的预览后追加到本机；整批成功或全部回滚，并可在历史、进步和下次预填中使用。

**Architecture:** 有行号的 CSV 扫描 → 来源映射与数值解析 → 统一 ImportedWorkout → 动作匹配及重复提示预览 → 单一事务写入 → 共享数据刷新。文件读取复用 Phase 3A 已实现能力；不调用整库恢复接口来导入历史。

**Tech Stack:** Flutter 3.47.6 / Dart 3.13.5、现有 SqlExecutor.transaction、SQLite / FFI / wasm、file_picker 13.1.0、Provider、go_router；不为 CSV 解析新增运行时包。

### 2026-10-16 实际交付检查

- [x] 统一模型、扫描器、三来源解析、动作匹配与重复预览。
- [x] 单事务追加、容量回滚、异步取消和提交后刷新。
- [x] CSV 页面、手动补记、设置入口与详情说明。
- [x] 自动化、真实浏览器文件往返、Android 构建。
- [ ] Android 真机文件 / 键盘 / 活动训练保留矩阵；需连接设备。

## 1. 依据、起点和范围

### 1.1 当前基线

- HEAD 记录为 `3a34c6c`；实际实施前重新读取 git log，不能把这个提交号当固定回滚点。
- [Phase 3A 执行结果](./2026-10-16-phase3a-execution.md)：功能、格式、静态检查、304 条测试、浏览器备份 6/6 和原训练 7/7 已通过；Android 构建成功，真机 A1–A9 仍待设备。
- schema **v4**，现有 8 张应用表足够，本期不新增迁移或备份格式版本。
- `PlatformBackupFileStore.pick()` 已有有限读取和取消处理；`SqlExecutor.transaction` 已有真实事务；动作选择器已有实现。
- `.claude/settings.local.json`、`.tmp/` 为用户已有改动，不能提交或清理。

3A 的真机缺口不妨碍编写本计划或实现纯逻辑，但本期发布前要连同 3A A1–A9 一起补验，不能把构建成功等同于原生文件验收完成。

### 1.2 规格与源码依据

- [总体规格](../specs/2026-10-08-flutter-gym-tracker-design.md) §9–10。
- [旧项目总纲](../specs/2026-10-08-gym-tracker-design.md) §5.8。
- 已只读核对 `C:/ccproject/gym/src/domain/csv.ts`、`importRecords.ts`、`src/repositories/importRepo.ts` 和旧计划管理设计。
- 旧代码仅供理解契约；不复制旧项目的手写 BEGIN、按天合并和补 60 秒时长做法。

### 1.3 本期做什么

1. 三种既定 CSV 列布局、UTF-8 文件选择、来源和单位预览。
2. 可追溯到物理行号的坏行说明、有效训练选择、动作匹配确认。
3. 日期、时间、动作、组数值的手动补记；使用同一预览和写入入口。
4. 追加导入、疑似重复提示、事务、错误与取消、提交后刷新。
5. 浏览器与独立 Android 包真实文件导入和备份往返。

不做 XLSX、任意列拖拽映射、自动识别所有第三方版本、同义动作自动合并、后台监听文件夹、云导入、导入后的历史编辑；编辑既有历史另行设计。

## 2. Global Constraints 与产品规则

### 2.1 三个需要在实现中坚持的区别

| 功能 | 写入语义 | 当前训练 / 计划 / 偏好 |
|---|---|---|
| JSON 恢复（3A） | 整体替换 | 按备份契约恢复 |
| CSV / 手动补记（本期） | **只追加所选已结束训练** | 活动训练、计划、主题不改；新 session.template_id 一律 NULL |
| 删除记录（Phase 4） | 只删明确目标 | 不得用清库替代 |

### 2.2 本计划采用的具体策略

以下是为计划可执行而明确的默认方案，属于本期拟实现行为；编写计划本身不表示功能已经交付。

| 问题 | 采用方案 | 不采用的方案与原因 |
|---|---|---|
| 同日多场 | 以来源、精确开始时间、训练名分组；保留首次出现顺序 | 只按自然日会把早晚两场合并 |
| 缺少结束时间 | finishedAt 使用 startedAt 占位，预览明确「时长未知」，session.note 保存可读来源说明 | 不编造 1 分钟、平均组间休息或整场测量时长 |
| 重复训练 | 预览标出结构完全相同的疑似重复，默认不选中；用户可明确勾选追加 | 不静默删记录，也不未经提示重复追加 |
| 同名多个本机动作 | 展示候选并要求选一个，或取消相关训练 | 不随意拿第一条，不做中文同义词猜测 |
| 文件有部分坏行 | 预览保留好行，列明坏行；有坏行时须勾选「已了解将跳过 N 行」 | 仓储收到已确认批次后不得再静默跳过 |

对于没有精确时间、同名且同日的源数据，无法推断是否两场训练：预览必须提示会合为一场；用户可取消并补齐源时间 / 训练名。不能声称能无损识别源文件没有的信息。

缺结束时间时，详情新增说明区域读取已有 session.note 列，显示「来源未提供结束时间，时长未知」；当前详情尚未展示该备注，不能当成现有能力。列表的 0 秒是占位值，预览先说明该限制。本期不为此新增隐藏标记列或改变备份协议。手动补记要求用户填写实际开始、结束时间。

### 2.3 不变量

- domain 无 Flutter / IO / SQL；SQL 仅数据层，界面经 state / 仓储访问。
- 复用原容量、e1RM、时长计算；不改既有公式或把无法换算的 e1RM 补 0。
- 文件最多 20 MiB，最多 100,000 条逻辑 CSV 记录，候选数据创建前先限额。
- 写入后总库仍须满足当前备份 100,000 条记录 / 20 MiB 上限；超限整个事务回滚。
- 全部 ID 本机生成，不接受 CSV 指定主键；所有 SQL 参数化。
- 新组全部 `is_completed=1`、`completed_at=finishedAt`、两个休息字段均 NULL；不生成未完成占位组。
- 次数为正整数，重量为有限非负数；自重 / 空重量可为 0。导入至少一场，每场至少一个动作，每个保留动作至少一组。
- 提交成功之后界面刷新失败要报告「记录已导入」，不得宣称已回滚。

## 3. 目录、接口与依赖图

| 新增 / 修改文件 | 职责 |
|---|---|
| Create `lib/domain/import_records.dart` | 不可变统一训练类型、名字规范化、整批校验、指纹 |
| Create `lib/domain/csv_records.dart` | 引号 / 换行扫描、逻辑记录与物理起始行号 |
| Create `lib/domain/workout_csv.dart` | 来源、列映射、日期 / 单位 / 次数、组装训练 |
| Create `lib/domain/import_preview.dart` | 动作匹配、疑似重复、训练选择与确认批次 |
| Create `lib/data/repositories/import_repo.dart` | 一次查动作、预览快照、单事务追加、容量边界 |
| Modify `lib/data/repositories/backup_repo.dart` | 提供可在现有事务内调用的只读快照，避免嵌套事务 |
| Create `lib/state/data_revision.dart` | 提交后的通用刷新通知，供导入和 Phase 4 复用 |
| Create `lib/state/import_controller.dart` | 文件、手动草稿、预览、busy、确认与结果 |
| Create `lib/features/import/import_page.dart` | 文件入口与导入流程 |
| Create `lib/features/import/import_preview_view.dart` | 场数 / 日期 / 动作 / 单位 / 坏行 / 重复选择 |
| Create `lib/features/import/manual_workout_form.dart` | 手动日期、动作、组编辑 |
| Modify `lib/app/{providers,router,app_shell}.dart` | 装配、路由、通用 revision |
| Modify `lib/features/settings/settings_page.dart` | 「追加训练记录」入口 |
| Modify `lib/features/history/session_detail_page.dart` | 展示来源 / 时长未知说明，不复制总结逻辑 |
| Create `test/fixtures/import/` | 三种来源、混合坏行、跨日、同日多场、引号跨行 |
| Create `scripts/browser_import_smoke.mjs` | 真实上传、确认、取消、追加后备份重导出 |

所有新源码都对应同名 domain / data / state / widget 测试；具体文件名在各任务给出。

执行依赖：`0 统一模型与刷新 → 1 CSV 扫描 → 2 来源解析 → 3 预览 → 4 仓储 → 5 编排 → 6 界面 → 7 平台验收 → 8 收尾`。

## 4. 固定数据契约

保存到 `domain/import_records.dart`，所有 List 在构造时 unmodifiable；下列类型是本期新增，不应误认为已经存在：

```dart
class ImportedSet {
  final double weight;
  final int reps;
  const ImportedSet({required this.weight, required this.reps});
}

class ImportedExercise {
  final String name;
  final List<ImportedSet> sets;
  ImportedExercise({required this.name, required List<ImportedSet> sets})
      : sets = List.unmodifiable(sets);
}

class ImportedWorkout {
  final int sourceRow;
  final int startedAt;
  final int finishedAt;
  final String? name;
  final String? note;
  final List<ImportedExercise> exercises;
  ImportedWorkout({
    required this.sourceRow,
    required this.startedAt,
    required this.finishedAt,
    this.name,
    this.note,
    required List<ImportedExercise> exercises,
  }) : exercises = List.unmodifiable(exercises);
}

class ImportValidationException implements Exception {
  final String message;
  const ImportValidationException(this.message);
  @override
  String toString() => message;
}

String normalizeExerciseName(String input) {
  final half = String.fromCharCodes(input.runes.map((r) {
    if (r == 0x3000) return 0x20;
    return r >= 0xff01 && r <= 0xff5e ? r - 0xfee0 : r;
  }));
  return half.replaceAll(RegExp(r'\s+'), '').toLowerCase();
}
```

名字规范化只用于匹配，保留首次原始名字用于显示；不将「卧推」和「杠铃卧推」视作同义词。来源行不落库成特殊身份，导入后数据与本机训练同构。

其他公开接口固定为：

| 文件 | 接口 |
|---|---|
| import_records.dart | `void validateImportedWorkouts(List<ImportedWorkout> workouts)` |
| import_records.dart | `String workoutFingerprint(ImportedWorkout workout)`，固定顺序 JSON，不使用随机 hashCode |
| csv_records.dart | `List<CsvRecord> scanCsv(String text)`；CsvRecord 含 `int line`、`List<String> fields` |
| workout_csv.dart | `CsvParseResult parseWorkoutCsv(String text, {WeightUnit defaultUnit = WeightUnit.kg})` |
| import_preview.dart | `ImportDraft buildImportDraft(CsvParseResult parsed, ImportCatalog catalog)` |
| import_preview.dart | `ConfirmedImport confirmImportDraft(ImportDraft draft, ImportSelection selection)` |
| import_repo.dart | `Future<ImportCatalog> loadImportCatalog(SqlExecutor exec)` |
| import_repo.dart | `Future<ImportResult> importWorkouts(SqlExecutor exec, ConfirmedImport batch)` |
| backup_repo.dart | `Future<BackupFile> readBackupSnapshot(SqlExecutor tx, {required int exportedAt})`：不自行开事务，调用方持有 tx |

`ImportCatalog` 包含完整动作（含归档）、已结束训练指纹及本机业务快照 token；`ImportDraft` 包含 catalog token、原候选、匹配结果、疑似重复索引和坏行；`ImportSelection` 包含被选训练索引、动作规范名→既有 ID / 新建选择、坏行知悉标记；`ConfirmedImport` 是确认函数生成的不可变对象，仓储再次校验，不开放可变 Map 绕过预览。

`ImportResult` 包含 `sessionIds`、`sessions`、`sets`、`usedExercises`、`createdExercises`。`sourceRow` 只参与错误位置，不参与指纹；指纹包含时间、训练名、按顺序规范化后的动作名和重量 / 次数，不含 note、UUID 和来源文件名。

类型归属固定：ImportedSet / Exercise / Workout、ImportResult、ImportValidationException 在 `import_records.dart`；CsvRecord 在 `csv_records.dart`；CsvSource、WeightUnit、CsvParseResult、WorkoutImportStats 在 `workout_csv.dart`；ImportCatalog、ImportDraft、ImportSelection、ConfirmedImport 在 `import_preview.dart`。仓储只消费这些领域类型，domain 不得为了拿 ImportCatalog 反向 import 数据层。

ImportCatalog 的 token 使用 3A 固定顺序业务快照 data 的 JSON，排除 exportedAt；动作索引可直接由该快照 exercises 数组构建，天然包含归档动作。ConfirmedImport 保存 token、所选 workouts、规范名到既有 ID / 明确新建的映射，以及所选子集统计，不能只保存可变 UI 索引。

## Task 0：接续基线、统一校验和刷新通知

**Files:** Create `lib/domain/import_records.dart`、`lib/state/data_revision.dart`；Modify `lib/app/providers.dart`、`lib/app/app_shell.dart`；Test `test/domain/import_records_test.dart`、`test/state/data_revision_test.dart`、`test/app/router_test.dart`。

- [ ] **Step 1：只读确认现场。** 阅读 3A 执行结果，记录当前 HEAD 和 git status；确认导入 / 计划功能尚不存在。3A A1–A9 留作发布前置，不伪造已验收。
- [ ] **Step 2：写失败用例。** 校验结束早于开始、空批次、空动作、空组、负重量、NaN、0 次、时间戳越界；断言无副作用。次数类型已是 int，小数文本的拒绝在 Task 2 解析层测试，不用强制类型转换伪造领域输入。

```dart
test('a workout without sets is rejected before any SQL', () {
  final input = ImportedWorkout(
    sourceRow: 2, startedAt: 1000, finishedAt: 2000,
    exercises: [ImportedExercise(name: '深蹲', sets: [])],
  );
  expect(() => validateImportedWorkouts([input]),
      throwsA(isA<ImportValidationException>()));
});
```

- [ ] **Step 3：实现 §4 类型、规范化与整批校验。** 校验每一层，并在生成候选前限制总量；数字必须有限，时间戳为 `0..8640000000000000` 的整数毫秒，finishedAt ≥ startedAt。
- [ ] **Step 4：增加通用 revision，保留 backup 原接口兼容。**

```dart
class DataRevision extends ChangeNotifier {
  int _value = 0;
  int get value => _value;
  void changed() {
    _value++;
    notifyListeners();
  }
}
```

AppShell 优先读 DataRevision.value；无该 provider 的旧独立测试可回退 BackupController.revision。3A 进入 onRestored 回调的第一步调用 changed（此时事务已提交），再保留 reset / resume / theme.load / 原 router；刷新失败也不能漏掉已提交的数据变化。导入在 SQL 成功后调用 changed 并进入历史，不 reset 正在练的 session。
- [ ] **Step 5：验证与提交。** `flutter test --no-pub test/domain/import_records_test.dart test/state/data_revision_test.dart test/app/router_test.dart`，全绿后明确清单提交，消息 `feat(import): define records and shared data revision`。

## Task 1：CSV 扫描器与真实行号

**Files:** Create `lib/domain/csv_records.dart`、`test/domain/csv_records_test.dart`、`test/fixtures/import/quoted-multiline.csv`。

- [ ] **Step 1：写失败测试。** 字段中的逗号、双引号转义、跨行、CRLF / LF / CR、末尾无换行、空字段均锁定。下例第二条数据的物理起始行为 4：

```dart
test('quoted newlines preserve physical source rows', () {
  final rows = scanCsv('a,b\r\n"line1\nline2",8\r\nnext,9');
  expect(rows.map((r) => r.line), [1, 2, 4]);
  expect(rows[1].fields, ['line1\nline2', '8']);
});
```

- [ ] **Step 2：状态机逐字符扫描。** 状态为字段起始 / 普通字段 / 引号内 / 闭引号后；CRLF 只计一次行。`""` 只在引号内解释为引号；非法闭引号后字符、未闭合引号作为文件级错误，不尝试错误恢复后猜行边界。
- [ ] **Step 3：限额。** 最多 100,000 条逻辑记录，超过立即抛中文异常；文件 20 MiB 在已有流读取层限制。空行由来源解析层忽略，扫描器不静默丢位置。
- [ ] **Step 4：验证。** `flutter test --no-pub test/domain/csv_records_test.dart`；移除 CRLF 特判或引号内换行计数应使真实行号用例变红。
- [ ] **Step 5：提交。** 明确添加这三个文件，消息 `feat(import): scan CSV records with physical line numbers`。

## Task 2：来源映射、日期、单位与训练分组

**Files:** Create `lib/domain/workout_csv.dart`、`test/domain/workout_csv_test.dart` 和 `test/fixtures/import/{strong,hevy,xunji,same-day,mixed-errors}.csv`。

### 2.1 来源与表头

| 来源 | 日期（必需） | 训练名（可选） | 动作（必需） | 重量（必需） | 次数（必需） | 结束时间（可选） |
|---|---|---|---|---|---|---|
| Strong | Date | Workout Name | Exercise Name | Weight | Reps | 不推测未约定列 |
| Hevy | start_time | title | exercise_title | weight_kg | reps | end_time |
| 训记 | 日期 | 训练名称 | 动作名称 | 重量(kg) | 次数 | 不推测未约定列 |

先统一全角、trim、连续空白与大小写，表内列名也用同一规则；重复必需列或同时匹配多种来源时拒绝，不随便取第一列。行中重复表头、空行不计 skipped。组序列不读取，组顺序依文件顺序。

### 2.2 日期与结束时间

- 接受 `yyyy-MM-dd` / `yyyy/M/d` / `M/d/yyyy`，可带 `HH:mm[:ss]`，月在前形式可带 AM / PM；只有日期取当地 12:00。
- 显式带 Z / UTC offset 的完整 ISO 时间可按给定时区解析；无时区不走宽松 DateTime.parse，以字段构造本地 DateTime 并逐字段回验，拒绝 2 月 31 日、25 点和无效 AM / PM。
- 两位年份、`15/1/2024`、未约定的自然语言月份不猜；错误带真实行号和字段名。
- 预览写明无时区按当前设备 UTC offset 解释；不声称源文件保存了时区。跨夏令时的无时区数据按当前设备时区规则，歧义写进限制。
- 有合法 end_time 就用它；已提供但非法则整行报错。缺失时结束等于开始，预览与 note 写明时长未知，不补一分钟。

### 2.3 重量与次数

- 数字 kg、`60kg`、`135 lb` / lbs、`BW` / 空重量；自重返回 0 且不计坏行。
- 明确 `weight_kg` / `重量(kg)` 表头按公斤；与值显式 lb 冲突则该行报错。
- Strong 的裸数字使用预览可切换的「无单位按 kg / lb」，默认 kg，并明确显示假设；显式行单位优先。
- lb × **0.45359237**，库中不提前四舍五入；预览格式化不能改变落库值。
- 只统计被接受行里的磅换算行数；坏行不进入换算计数。次数必须为正整数，`8次` 可按明确后缀规则接受，其他文本拒绝。

### 2.4 分组与返回值

`CsvParseResult` 含 source、columns、workouts、skipped（line / reason）、poundsConverted、unknownDurationCount、statsByWorkout；所有列表不可变。枚举 `CsvSource { strong, hevy, xunji, unknown }`、`WeightUnit { kg, lb }` 在本文件定义。

`WorkoutImportStats` 与 workouts 一一对应，保存该场所有有效 sourceRows、poundsConverted 和 durationUnknown；选中子集后按该元数据重算换算数 / 未知时长数。不能只保留整文件汇总后再根据 kg 值反推某一行原来是否为磅。

分组键固定为来源 + 精确 startedAt + 规范化训练名；同键有不同显式结束时间时拒绝该组并列出涉及行，避免静默挑一个。组内动作按首次出现顺序合并同规范名，组按原行序追加。输出训练按 startedAt 升序，相同时间按最早 sourceRow，不能按随机 ID 排。

训练名的规范化为全角转半角、trim、连续空白折为一个空格；不使用动作名的「删去所有空白」来混同不同训练名。同组只有一个合法显式结束时间时全组采用它；全部缺失才标未知。重复表头不是场次边界；不对数值完全一样的组逐行去重，因为连续两组同重量同次数是正常数据。重复提示比较的是分组后的完整训练，无法识别源文件未标识的重复组，这一限制在预览帮助中说明。

- [ ] **Step 1：建立三种来源 fixture 和真实行号期望。** 同一天 `09:00 推日` 与 `19:00 拉日` 必须两场，不因日期相同合并。
- [ ] **Step 2：分别实现日期、重量、次数的纯函数，写各自边界测试。** 无法解析的普通数据行进入 skipped；扫描结构错误中止整文件。
- [ ] **Step 3：实现来源识别与分组。** unknown 返回空候选和来源提示；不能给「确认导入」。
- [ ] **Step 4：验证单位数字。** `135 lb` 应为 `61.23496995 kg`，测试用容差比较；`20 × 8` 容量仍为 160。
- [ ] **Step 5：执行 `flutter test --no-pub test/domain/workout_csv_test.dart` 并提交。** 消息 `feat(import): parse supported workout CSV formats`。

## Task 3：匹配、疑似重复与不可变确认批次

**Files:** Create `lib/domain/import_preview.dart`、`test/domain/import_preview_test.dart`。

- [ ] **Step 1：失败测试覆盖匹配唯一性。** 大小写 / 全角 / 空白归一后复用；两条已有同规范名必须显示冲突，未选 ID 时不能确认；归档动作可明确匹配，不自动解档。
- [ ] **Step 2：一次构造名字索引。** `Map<String,List<Exercise>>` 包含归档动作，不仅调用默认过滤归档的 listExercises。缺失名称提出一次新建建议，整个批次复用；同一训练重复动作合并为一个有序组列表。
- [ ] **Step 3：计算指纹。** 只比较已结束训练的时间、训练名、动作顺序 / 规范名和组值；统一 weight 为 double，不能以 CSV 文件名或随机 UUID 判断重复。已存在与文件内重复分别标注。
- [ ] **Step 4：确认选择。** 索引越界、候选被换文件、未解决动作冲突、未知悉坏行、零选中均拒绝。默认取消疑似重复勾选；手动选择「仍要追加」必须保留，不重新偷偷去重。
- [ ] **Step 4a：重算所选子集统计与容量预估。** 取消一场后，组数、磅换算数、未知时长数与待新建动作数同步减少；根据父 / 子表数量预检全库记录上限，事务末尾仍执行精确备份边界检查。
- [ ] **Step 5：测试反例。** 同时同名但组重量不同不是完全重复；同一天不同开始时间不重复；0 kg 自重是有效组。

重复提示不等于第三方唯一 ID 去重：舍入方式或源时间变动后不保证识别同一训练，用户在预览核对。不能在 README 宣称杜绝所有重复导入。
- [ ] **Step 6：运行 `flutter test --no-pub test/domain/import_preview_test.dart`，提交 `feat(import): prepare explicit import selections`。**

## Task 4：单一事务追加仓储

**Files:** Create `lib/data/repositories/import_repo.dart`、`test/data/import_repo_test.dart`；Modify `lib/data/repositories/backup_repo.dart`。

### 4.1 读写顺序

1. `loadImportCatalog` 读取完整本机业务快照和动作名称，构建预览 token；复用 3A 快照读法，不写库。
2. `importWorkouts` 先重新 validate 确认批次；进入一次 `exec.transaction((tx) async {...})`。
3. 用同一 tx 重读规范业务快照，与预览 token 比较；本机在预览后变化则要求重做预览，不用过期匹配。
4. 名字缓存一次读入，按确认映射复用 ID；新动作在这个事务创建并立即加入缓存，归档状态不自动修改。
5. 逐场插入已结束 session，name / note 保留，template_id=NULL；逐动作、逐组按数组顺序插入连续 position。
6. 末尾 `encodeBackup(await readBackupSnapshot(tx, exportedAt: now))`，使新增数据也可备份，超限或引用不完整则回滚。
7. 返回实际 IDs 与计数。异常不在 tx 内吞掉，保留原异常；提交后才发布刷新事件。

`readBackupSnapshot` 是 3A 私有快照的公开事务内读取入口，不再调用 exportBackup(tx) 以免触发嵌套事务。原 exportBackup / restoreBackup 接口和已有测试保持。

固定组写入语义：

```sql
INSERT INTO set_entry
  (id, session_exercise_id, position, weight, reps, is_completed,
   rest_seconds, rest_started_at, completed_at)
VALUES (?, ?, ?, ?, ?, 1, NULL, NULL, ?);
```

### 4.2 仓储测试

- [ ] 42 场中同一个新动作出现 300 次，只新增一个动作；动作 SELECT 不随行数线性增长。
- [ ] 同一训练同规范名两块数据合为一条 session_exercise，组序与输入一致。
- [ ] 已有活动训练完整保留；导入不会结束它，也不会增加第二场活动训练。
- [ ] 断言 completed_at 非空，历史 / 进步直接读到新组，rest 字段均为 NULL。
- [ ] 在新动作后、第 2 场中途、末尾备份大小检查处注入错误；原训练、动作、计划、偏好逐字段不变。
- [ ] 预览后新建动作 / 修改组值，事务拒绝旧 token，不创建临时动作。
- [ ] 文件与手动输入走相同 importWorkouts；不能各有一套 INSERT。
- [ ] 同毫秒的多场插入和重导出保留选择顺序，不丢来源先后。
- [ ] `flutter test --no-pub test/data/import_repo_test.dart test/data/backup_repo_test.dart` 全绿，提交 `feat(import): append workouts atomically`。

## Task 5：编排、手动草稿与提交后刷新

**Files:** Create `lib/state/import_controller.dart`、`test/state/import_controller_test.dart`。

公开接口：

| 接口 | 行为 |
|---|---|
| `Future<bool> selectCsv({WeightUnit defaultUnit = WeightUnit.kg})` | 选文件、严格解码、解析、加载 catalog、生成 draft；取消清旧草稿 |
| `Future<bool> previewManual(List<ImportedWorkout> workouts)` | 同一校验与 catalog；不直接写库 |
| `void updateSelection(ImportSelection selection)` | 重新生成确认批次，不修改原候选 |
| `Future<ImportCommitOutcome> commit()` | 仅当前有效确认批次可提交 |
| `void cancel()` | 非写入时清预览；提交中不取消已开始的事务 |

构造参数 `SqlExecutor exec`、`BackupFileStore files`、`Future<void> Function(ImportResult) onCommitted`；回调负责 DataRevision.changed 和导航，CSV 只用 files.pick。状态暴露 busy、committing、draft、selection、message；内部处理选择序号与 disposed，遵循 3A 异步防回写模式。

`ImportCommitOutcome { committed, refreshFailed, notCommitted }`：SQL 失败显示「未导入，本机数据未改动」；提交后导航 / 刷新失败显示「已导入 N 场，请重新打开查看」，禁止自动重试插入。

- [ ] 使用 Completer 验证重复选择 / 双击确认只执行一次；所有出口 finally 释放 busy。
- [ ] 选择 A 后取消 B、页面关闭后异步 A 返回，不能复活旧预览或写已销毁 controller。
- [ ] 切换裸重量单位时重新解析缓存原 bytes，并重建 preview token；不能对已转 kg 的结果再乘一遍。
- [ ] 有坏行但未知悉、动作冲突未解、全部重复未选中时不能 commit。
- [ ] 手动草稿改变后，旧确认批次失效，必须重新预览。
- [ ] SQL 成功后仅发一次数据变化通知；活动训练内存与当前编辑值不重置。
- [ ] `flutter test --no-pub test/state/import_controller_test.dart` 全绿，提交 `feat(import): orchestrate preview and append`。

## Task 6：文件导入页与手动表单

**Files:** Create §3 的三个 import 界面文件；Modify settings、router、providers、history/session_detail_page；Test `test/widget/import_pages_test.dart`、`test/widget/manual_workout_form_test.dart`、`test/app/router_test.dart`。

### 6.1 路由与入口

- 设置「记录管理」卡片中独立的「从 CSV 追加记录」与「手动补记录」；JSON 恢复仍在数据备份区。
- `/records/import` 为全屏带返回的文件页；`/records/manual` 为手动表单，均在 ShellRoute 之外。
- 使用 `context.push` 从设置进入；不替换整个导航栈，不在路由 extra 放大份 CSV 字符串。

### 6.2 预览

必须能核对：来源、文件名、场数与日期范围、每场动作 / 组数、单位假设 / 转换数、未知时长数、已有与待新建动作、冲突选择、疑似重复、坏行数和可展开真实行号 / 原因。

全坏 / 来源 unknown / 无选中时仅取消或重新选文件；不能显示可点确认。确认按钮写「追加 N 场训练」，不写容易与恢复混淆的「替换」。坏行确认复选框和疑似重复选择是预览的一部分，最终结果显示实际新增场数 / 组数 / 自建动作数。

### 6.3 手动补记

用户填写名字（可空）、开始 / 结束本地日期时间，用现有 showExercisePicker 选已有动作，或输入明确的新动作名；每个动作编辑有序 weight / reps 组，删除草稿行只影响内存。

表单已选中的既有 exerciseId 用于预填 ImportSelection 的动作映射，不因统一模型只含名字而丢失用户的明确选择；输入新名字则预填明确新建，仍在预览显示。

未完成草稿离开时提示丢弃或继续编辑；新动作未确认前不进动作库。保存先产生 ImportedWorkout，再走相同预览；不从表单直接 INSERT。

### 6.4 实际点击测试

- [ ] 点真实选择按钮而不是测试直接调用仓储，预览前导出数据库快照始终不变。
- [ ] 单位切换、坏行知悉、重复勾选、冲突动作选择均改变最终批次，界面数量与结果相同。
- [ ] 取消 / 返回不写库；提交中 PopScope 阻止退出与重复点击。
- [ ] 手动 20×8 + 30×10 确认后容量 460；未提供任何组时只报校验，不创建空训练。
- [ ] 详情显示导入说明；现有 SessionSummaryView、容量和 e1RM 口径不复制重写。
- [ ] 导入后历史有新增、进步出现对应点、当前训练继续卡片保持；下次该动作预填能用到导入成绩。
- [ ] 320×480、横屏、大字号、键盘和长错误列表可滚动，确认可达。
- [ ] `flutter test --no-pub test/widget/import_pages_test.dart test/widget/manual_workout_form_test.dart test/app/router_test.dart`，提交 `feat(import): add CSV preview and manual entry pages`。

## Task 7：回归、变异与真实平台验收

### 7.1 固定 fixture 与预期

| fixture | 内容 | 验收 |
|---|---|---|
| strong.csv | 20×8 一组、训练名带逗号 | 1 场、1 组、160；时长未知明示 |
| hevy.csv | 50×8 四组，有开始 / 结束 | 容量 1600、e1RM 屏显 62，时长来自源 |
| xunji.csv | 中文表头、全角括号、日期无时间 | 按当天 12:00，名字匹配既有动作 |
| same-day.csv | 同日两场不同开始时间 | 历史两场，不合并成一天 |
| mixed-errors.csv | 好行、非法日期、负重量、空行、重复表头 | 只坏数据计 skipped，物理行号正确 |
| quoted-multiline.csv | 多行备注 / 名称字段 | 后续坏行的行号不偏移 |

### 7.2 变异验证

| 临时破坏 | 必须失败 |
|---|---|
| 不乘磅系数 | 135 lb 精确值断言 |
| CRLF 或引号内换行少计一行 | 真实行号用例 |
| 按自然日分组 | 同日两场用例 |
| 名字缓存删除 / 不更新新动作缓存 | 300 次名称只建一动作与查询数检查 |
| is_completed 写 0 或漏 completed_at | 实际历史 / 进步读取断言 |
| 休息写虚构 60 秒 | rest NULL 断言 |
| 不用事务 | 中途失败全库快照比较 |
| 取消选择不清旧确认批次 | A→取消 B→commit 不可写库用例 |

逐个保存原文、修改、测试、记录 Expected / Actual，再原样还原；不能用 git restore 丢弃未提交的正常实现。

### 7.3 本机与浏览器

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
```

新浏览器驱动使用 CDP fileChooserOpened + DOM.setFileInputFiles 真实上传：先留一条现有记录和一场活动训练，再上传 / 取消 / 确认三种 fixture；导出备份核对追加数量和原字段。再次导入同文件先展示重复，默认不新增；主动选择重复才新增。手动页也走真实按钮。results.json 必须记录 errors 和每项截图。

### 7.4 Android 独立包

沿用 3A `.acceptance` 包和 `adb install --user 0 -r`；只给测试包导入、清库和删除。fixture 放公共 Download。执行：

1. 补完 3A A1–A9，再保留其结果文件。
2. 系统文件界面分别选择三种 CSV，核对单位、行号、同日两场和时长说明。
3. 取消选择 / 取消预览，不产生任何训练或动作。
4. 导入时已有活动训练，返回仍能继续原组；导入均已结束，不制造冲突。
5. 手动补一场，核对历史 / 进步 / 下一场预填；重启后仍在。
6. 再次选同文件，默认疑似重复不追加，明确勾选后才增加。
7. 错文件、全坏、部分坏三种路径实际走一次，失败后导出与原库比较。
8. 导出 JSON，在隔离空库恢复后逐字段一致，特别是 rest NULL 与 templateId NULL。
9. 卸载独立包，去掉 GYM_ACCEPTANCE_BUILD / GYM_ACCEPTANCE_PACKAGE，重建默认 release，核对主包名、大小、SHA-256。

证据统一存 `build/acceptance/phase3b-<时间>/`；设备缺失时明确未做，不能标本期全部验收完成。

## Task 8：文档、提交和完成定义

- [ ] 更新 README 的支持来源与格式范围，不声称可自动适配所有最新版第三方导出。
- [ ] 记录日期解释、裸重量单位选择、同日分组、重复策略、缺结束时间的限制。
- [ ] 保存 fixture、变异实际错误、发布构建、真实浏览器和 Android 检查证据。
- [ ] `git diff --check`；按各任务的明确文件清单提交，不包含 `.claude/settings.local.json`、`.tmp/` 或 build 证据大文件。
- [ ] 执行以下完成表后再进入 Phase 4，不按测试数量替代场景覆盖。

| 完成条件 | 对应任务 |
|---|---|
| 三种 CSV 的列映射、真实行号和单位正确 | 1–2 |
| 同日多场不混，未知时长不伪造 | 2、6 |
| 预览可信：动作冲突、坏行、重复均由用户明确选择 | 3、5–6 |
| 文件与手动补记只用一条事务落库 | 4–6 |
| 失败全回滚，活动训练 / 计划 / 偏好不受追加影响 | 4–5 |
| 历史、进步、预填直接消费导入组 | 4、6–7 |
| 备份仍可导出 / 恢复新增数据 | 4、7 |
| 格式、静态、全量、变异、Web 和 Android 均有实际结果 | 7–8 |

## 需求覆盖与自查

来源 / 表头 / 引号 / BOM / 行号 → 1–2；日期 / 单位 / 组序 → 2；名字缓存 / 不猜动作 → 3–4；统一落库 / 不伪造休息 → 4；全坏不可确认 / 部分坏明示 → 3、5–6；手动补记 → 5–6；取消 / 重复提交 → 5–7；真机 / 备份 → 7；完成记录 → 8。

2026-10-16 已接入本期新增模块，本机验证与真实浏览器通过；Android 真机矩阵待设备。实际完成情况见上方检查与执行记录。
