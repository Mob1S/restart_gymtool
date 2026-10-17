# 训练导航、多天计划与器械重量输入 Implementation Plan

执行结果见[本轮执行记录](2026-10-17-training-redesign-execution.md)。本文件保留实施前的步骤清单；最终验证、集成提交和平台待测状态以执行记录为准。

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> 执行方式由用户选择。本计划编写阶段没有启动子代理，也没有修改应用代码。若选择的执行技能未安装，先检查本地技能目录及插件目录；不能把未加载的技能报告为已使用。可在用户授权的当前会话顺序实施，各任务结束审查实际 diff 和验证结果。

**Goal:** 交付默认月历且主按钮居中的训练首页、按日定位并增删记录的历史页、可配置多天分化的计划，以及按器械 kg／lb 原始读数工作的方向锁定输入。

**Architecture:** 保留现有模板作为训练日，在上层增加父计划；通过追加的 schema 6 和备份 v4 保留旧训练、组和动作偏好。重量同时保留原始十进制读数／单位和标准 kg，现有统计仍消费 kg；页面通过仓储、现有 controller 和 DataRevision 联动。

**Tech Stack:** 当前锁定 Flutter 3.47.6 / Dart 3.13.5、Provider、go_router、SqlExecutor、SQLite FFI／Web／Android；不增加运行时依赖。

## Global Constraints

- 唯一产品依据：[已确认设计](../specs/2026-10-17-training-navigation-plans-and-input-design.md)。应用基线 `bd1b09f`，设计提交 `a5b99b8`。
- 数据库目标 schema 6，备份目标版本 4；不改写已发布的 v1–v5 迁移。
- 默认月历，主按钮在常规竖屏的可用训练内容区域中间；窄屏、横屏、大字号可滚动且不遮挡。
- 计划 → 多个训练日 → 有序动作项；无固定三分化、固定训练日数量或星期绑定。
- 新建整套计划只从“管理计划”进入；记录查看、补加、删除归历史。
- 每套计划独立顺序轮换，允许手选；完成整场才推进，自由训练／补加／CSV 不推进。
- 重量上下、次数左右；起手区域持有锁，活动值高亮，跨区和斜滑不切换。
- 默认重量 16 逻辑像素／档，次数 24 逻辑像素／次；无惯性、无速度加成；取消恢复起始值。
- 去掉记录页两对加减按钮；保留键盘及读屏增减能力。
- 主数值跟随器械 kg／lb 读数；切换单位保持正在填写的数字，不从 kg 回算产生器械没有的默认刻度。
- 可选 kg 辅助值显示两位小数；换算使用 1 lb = 0.45359237 kg，统计使用未按展示精度舍入的 kg。
- 单位、各单位步长、换算展示按动作 ID 保存；保存面板确认才生效。
- 已完成组读取保存时的单位；偏好变化不得改写过去的重量。
- 保留用户修改 `.claude/settings.local.json`、`.tmp/`；`.superpowers/` 为讨论草图，不混入业务提交。
- 写入沿用事务、冲突 token、串行队列和 generation；事务中只用 tx，不嵌套 transaction。
- 不删除用户数据库、不清理用户浏览器数据；自动化使用项目现有独立 profile／origin。

## 批次、依赖和检查约定

顺序为 A：任务 1–3 数据兼容 → B：任务 4–5 多天计划 → C：任务 6–8 重量输入 → D：任务 9–11 日期导航与集成验收。它们服务同一条训练流程，使用同一份设计；不拆出会重复改版本号的独立计划。

每个任务的每个复选步骤为一次具体动作。修改大文件时分多个小步骤，不在单个步骤同时重写仓储、controller 和页面。任务 2 的迁移与旧调用适配须作为同一个可运行提交；任务 3 开放新版备份导出，先保持旧格式兼容读取。

执行测试命令前在当前 PowerShell 加载环境：

```powershell
. .\scripts\env.ps1
flutter pub get --offline --enforce-lockfile
```

预期离线依赖解析成功且 `pubspec.lock` 不变。遇到实际依赖缺失再按权限流程处理，不预先升级包。本文命令针对仓库根目录 `C:\ccproject\restart_gymtool`。每次命令失败先停止当前步骤，记录实际原因；不得把编译失败误报为某个行为测试已先红。

## 文件与接口地图

| 文件 | 变更／职责 |
| --- | --- |
| `lib/domain/weight_value.dart`（新） | 唯一 WeightUnit、精确十进制读数和 kg 换算 |
| `lib/domain/workout_csv.dart` | 重导出共享 WeightUnit，保留原 CSV 调用方可编译 |
| `lib/domain/types.dart`、`exercise_preferences.dart` | 组来源重量、会话计划快照、单位偏好 |
| `lib/data/db/training_v6_migration.dart`（新） | v6 的事务迁移和旧模板归组 |
| `lib/data/db/migrations.dart` | 仅追加 v6 分支，旧迁移顺序不变 |
| `lib/domain/backup_upgrade.dart`（新） | 旧格式到 v4 的纯内存归一化 |
| `lib/domain/backup.dart`、`lib/data/repositories/backup_repo.dart` | 新版字段、关联校验、恢复写入顺序 |
| `lib/domain/training_plans.dart`（新） | 父计划、训练日草稿、选择和推荐类型 |
| `lib/data/repositories/training_plan_repo.dart`（新） | 父计划／训练日事务保存与删除 |
| `lib/data/repositories/workout_plan_repo.dart` | 按当前父计划推荐，沿用原子开训的读取边界 |
| `lib/state/plan_controller.dart` | 父计划草稿及训练日编辑 |
| `lib/features/plans/plan_list_page.dart`、`plan_editor_page.dart` | 整套计划列表和嵌套训练日编辑 |
| `lib/features/plans/day_editor_sheet.dart`（新） | 当日名称、动作选择及排序 |
| `lib/features/workout/adjustment_gesture.dart`（新） | 可独立测量的指针锁和方向计算 |
| `lib/features/workout/workout_value_input.dart`（新） | 重量／次数输入、可访问语义和高亮 |
| `lib/domain/local_date.dart`（新） | 日期参数校验、本地日边界与月份网格 |
| `lib/features/workout/training_calendar.dart`（新） | 月份切换、今天和完成标记 |
| `lib/features/workout/workout_home_page.dart` | 自适应布局、计划选择及日期导航 |
| `lib/features/history/history_page.dart` | 显式日期筛选、补加和行内删除 |
| `lib/features/import/import_page.dart`、`manual_workout_form.dart` | 日期预填及组单位输入 |
| `lib/app/router.dart` | 既有路由扩展查询参数，保持详情返回栈 |

所有新类型均在下面任务中定义；不要在后续任务再次定义相同 WeightUnit、第二套计划游标或第二套 kg 计算。

### Task 1: 共享重量单位与原始十进制读数

**Files:** Create `lib/domain/weight_value.dart`, `test/domain/weight_value_test.dart`; Modify `lib/domain/workout_csv.dart`。

**Interfaces:**

```dart
enum WeightUnit { kg, lb }

// 所有字段不可变；text 是无补零的十进制普通记法。
class DecimalReading {
  factory DecimalReading.parse(String text);
  String get text;
  double get asDouble;
  DecimalReading plusSteps(DecimalReading step, int count);
}

class EquipmentWeight {
  EquipmentWeight(this.amount, this.unit);
  factory EquipmentWeight.kg(double value);
  final DecimalReading amount;
  final WeightUnit unit;
  double get kilograms;
  String get label;
  String get kgReference;
  EquipmentWeight withUnit(WeightUnit next);
  EquipmentWeight plusSteps(DecimalReading step, int count);
}
```

- [ ] **Step 1: 写重量语义的失败测试。** `weight_value_test.dart` 使用如下完整用例；补充自定义 0.1 重复十次得到 1、1.25、不带小数的整数、科学记法、负值、NaN／Infinity 拒绝。

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/domain/weight_value.dart';

void main() {
  test('器械单位选择保留数字，kg 只做参考', () {
    final input = EquipmentWeight.kg(40).withUnit(WeightUnit.lb);
    expect(input.label, '40 lb');
    final next = input.plusSteps(DecimalReading.parse('10'), 1);
    expect(next.label, '50 lb');
    expect(next.kilograms, closeTo(22.6796185, 1e-12));
    expect(next.kgReference, '≈ 22.68 kg');
    expect(next.plusSteps(DecimalReading.parse('2.5'), 1).label, '52.5 lb');
  });
}
```

- [ ] **Step 2: 运行并记录缺失接口失败。** `flutter test --no-pub test/domain/weight_value_test.dart --reporter expanded`；预期新文件／类型尚不存在，不将此结果称为行为已验证。
- [ ] **Step 3: 实现 DecimalReading 的解析与格式化。** 用 `BigInt coefficient` 和 `int scale` 表示十进制；正则匹配符号、整数、小数及可选指数，将指数折入 scale；去掉系数的尾零，scale 为负时乘 10 的相应幂。先检查输入可解析为有限 double；禁止重量负数，步长在调用边界检查严格大于 0。核心实现如下，构造函数为私有 `DecimalReading._(this.coefficient,this.scale)`：

```dart
DecimalReading plusSteps(DecimalReading step, int count) {
  final common = scale > step.scale ? scale : step.scale;
  final a = coefficient * BigInt.from(10).pow(common - scale);
  final b = step.coefficient * BigInt.from(10).pow(common - step.scale);
  return DecimalReading._normalized(a + b * BigInt.from(count), common);
}

static DecimalReading _normalized(BigInt coefficient, int scale) {
  if (coefficient == BigInt.zero) return DecimalReading._(BigInt.zero, 0);
  if (scale < 0) {
    coefficient *= BigInt.from(10).pow(-scale);
    scale = 0;
  }
  while (scale > 0 && coefficient % BigInt.from(10) == BigInt.zero) {
    coefficient ~/= BigInt.from(10);
    scale--;
  }
  return DecimalReading._(coefficient, scale);
}

String get text {
  final negative = coefficient.isNegative;
  final digits = coefficient.abs().toString().padLeft(scale + 1, '0');
  final split = digits.length - scale;
  final result = scale == 0 ? digits
      : '${digits.substring(0, split)}.${digits.substring(split)}';
  return negative ? '-$result' : result;
}
```

这里 `coefficient`、`scale` 是 DecimalReading 的私有存储，`_normalized(BigInt,int)` 必须完成上述尾零归一化；不是把 double 的浮点尾数转成主读数。`text` 在系数前补足小数位后插入小数点，0 始终输出 `0`。
- [ ] **Step 4: 实现 EquipmentWeight 的完整换算规则。** `withUnit` 仅重建单位，`plusSteps` 仅改变原读数；`kilograms` 在单位为 lb 时乘 `0.45359237`，否则原值；`label` 为 `${amount.text} ${unit.name}`，`kgReference` 为 `≈ ${kilograms.toStringAsFixed(2)} kg`。将原 CSV 的枚举删除并通过 `export 'weight_value.dart' show WeightUnit;` 保持兼容，解析实现本身 import 共享文件。
- [ ] **Step 5: 运行领域和原 CSV 测试。** `flutter test --no-pub test/domain/weight_value_test.dart test/domain/import_pipeline_test.dart --reporter expanded`；预期新用例及原磅换算全部通过。
- [ ] **Step 6: 仅提交本任务三个文件。** 提交信息 `feat: model native equipment weight readings and shared units`。

### Task 2: 原子 v6 迁移及旧调用兼容

**Files:** Create `lib/data/db/training_v6_migration.dart`, `test/data/training_v6_migration_test.dart`; Modify `lib/data/db/migrations.dart`, `lib/domain/types.dart`, `lib/domain/exercise_preferences.dart`, `lib/data/repositories/set_repo.dart`, `session_repo.dart`, `exercise_preferences_repo.dart`, `template_repo.dart`, `lib/domain/backup.dart`, `lib/data/repositories/backup_repo.dart`。

**Interfaces:** 新增 `Future<void> migrateTrainingV6(SqlExecutor tx)`；`SetEntry` 新增可空 `EquipmentWeight? recordedWeight`，`equipmentWeight` getter 对旧记录回退 `EquipmentWeight.kg(weight)`；保留 `weight` 为标准 kg。`WorkoutSession` 增加可空 `planId`, `planNameSnapshot`, `dayNameSnapshot` 及 `origin` 默认 `legacy`，不破坏现有 const 构造。

偏好新字段：`WeightUnit weightUnit`、`DecimalReading kgStep`、`DecimalReading lbStep`、`bool showKgEquivalent`；兼容既有 `weightStepMilli` 构造参数和 getter，新的输入不依赖该旧精度。

- [ ] **Step 1: 从已有 migrations 列表手工执行到 v5，插入两个并列 position 模板、重复动作项、关联训练、kg 组和 1.25 kg 偏好。** 在新测试中断言迁移后只产生一个父计划，模板 ID、动作出现项 ID 和原始顺序不变，组为原 kg，收藏和备忘逐字保留；再测没有模板时没有默认父计划。
- [ ] **Step 2: 运行迁移测试，预期查询 `training_plan` 失败。** `flutter test --no-pub test/data/training_v6_migration_test.dart --reporter expanded`。
- [ ] **Step 3: 在 v6 事务内执行以下结构变更。** 新建父表，给旧模板和会话追加字段，组保留可空 source_weight 以便原有低层 SQL fixture 正常工作。

```sql
CREATE TABLE training_plan (
  id TEXT PRIMARY KEY, name TEXT NOT NULL,
  position INTEGER NOT NULL, created_at INTEGER NOT NULL
);
ALTER TABLE split_template ADD COLUMN plan_id TEXT;
ALTER TABLE session ADD COLUMN plan_id TEXT;
ALTER TABLE session ADD COLUMN plan_name_snapshot TEXT;
ALTER TABLE session ADD COLUMN day_name_snapshot TEXT;
ALTER TABLE session ADD COLUMN origin TEXT NOT NULL DEFAULT 'legacy';
ALTER TABLE set_entry ADD COLUMN source_weight TEXT;
ALTER TABLE set_entry ADD COLUMN source_unit TEXT NOT NULL DEFAULT 'kg'
  CHECK(source_unit IN ('kg','lb'));
CREATE INDEX idx_template_plan ON split_template(plan_id,position);
CREATE INDEX idx_session_plan_finished ON session(plan_id,finished_at);
CREATE INDEX idx_session_started_finished ON session(started_at,finished_at);
```

`source_weight` 保存 DecimalReading.text。NULL 仅表示旧 kg 行；新写入总是同时设置原读数、单位和标准 weight。不能把已舍入的 kg 写进 source_weight。
- [ ] **Step 4: 重建偏好表以移除原五档 CHECK，复制所有旧行。** 新表字段为 `exercise_id` 主外键、`weight_unit TEXT DEFAULT 'kg'`、`kg_step TEXT DEFAULT '2.5'`、`lb_step TEXT DEFAULT '5'`、`show_kg_equivalent INTEGER DEFAULT 0`、原有 `is_favorite` 与 `equipment_note`。旧 `weight_step_milli / 1000.0` 格式化为 kg_step；检查成功后同一事务内替换旧表。
- [ ] **Step 5: 将现有模板归入一个新父计划。** 仅在模板非空时生成一次 newId，父名“我的训练计划”；`UPDATE split_template SET plan_id=?`，原 position 不重排；按已有模板 ID 补 session.plan_id 和名称快照，孤立来源保持 NULL。新表不使用会删除历史的级联外键，删除关联由 Task 4 的仓储明确解除。
- [ ] **Step 6: 仅为 v6 扩展迁移调度。** 在 migrate 的 pending 循环中，version 6 分支把 `migrateTrainingV6(tx)` 和写版本号放入同一次 transaction；v1–v5 路径保持原状。故障注入在 ALTER 后、偏好复制后和版本号写入前抛错，检查整批回滚后重启可成功。
- [ ] **Step 7: 适配 row mapper 和兼容写入。** `SetRow.fromMap` 同时读取 source_weight/source_unit；给 `addSet`、`updateSetValues` 添加可选命名参数 `EquipmentWeight? reading`，缺省按调用方传入的标准 kg 构建 kg 来源；SQL 同时更新三列。`createSession` 增加上述会话字段，正式开训 origin=live，原读取列列表全部扩展。
- [ ] **Step 8: 兼容旧模板创建和旧快照。** 给 saveTemplate 增加可选命名参数 planId，新建日时先使用该父 ID；旧调用未传时在事务内调用新增 `Future<String> ensureLegacyTrainingPlan(SqlExecutor tx)`，复用已有首个父计划，没有时创建“我的训练计划”，因此迁移后新建旧模板也不会成为孤立训练日。此任务维持导出 v3 的外部字段形状；在偏好快照 SQL 中临时以 kg_step 计算旧 weightStepMilli，旧字段数值与基线一致，且本任务尚不开放 lb／自定义单位 UI。Task 3 随即替换为无损 v4；不得在两个任务之间发布安装包。
- [ ] **Step 9: 运行迁移及现有持久化测试。** `flutter test --no-pub test/data/training_v6_migration_test.dart test/data/migrations_test.dart test/data/set_repo_test.dart test/data/exercise_preferences_repo_test.dart test/data/backup_v3_test.dart --reporter expanded`；预期全部通过。旧备份校验中 schema 上限须接受 schema 6 的现有 v3 快照，但不得接受未知高版本。
- [ ] **Step 10: 提交完整兼容批次。** 信息 `feat: migrate existing workouts into multi-day plan storage`；检查 diff 未修改旧迁移声明。

### Task 3: 无损备份 v4、CSV 与补记单位

**Files:** Create `lib/domain/backup_upgrade.dart`, `lib/domain/workout_csv_export.dart`, `lib/data/repositories/csv_export_repo.dart`, `lib/data/files/csv_file_store.dart`, `test/domain/workout_csv_export_test.dart`, `test/data/backup_v4_test.dart`; Modify `lib/domain/backup.dart`, `backup_codec.dart`, `import_records.dart`, `workout_csv.dart`, `import_preview.dart`, `lib/data/repositories/backup_repo.dart`, `import_repo.dart`, `test/domain/import_pipeline_test.dart`。

**Interfaces:** `Map<String,Object?> upgradeBackupToV4(Map<String,Object?> root)`；`ImportedSet` 保留标准 kg 的 weight，并新增可空 `EquipmentWeight? recordedWeight`。导入时 sourceWeight/sourceUnit 与 canonical weight 一起写入。新增导出接口：`Future<List<WorkoutCsvRow>> readWorkoutCsvRows(SqlExecutor,{int? startInclusive,int? endExclusive})`、`String encodeWorkoutCsv(List<WorkoutCsvRow>)` 和 `Future<BackupSaveResult> saveWorkoutCsv(String name,List<int> bytes)`。`WorkoutCsvRow` 在 workout_csv_export.dart 定义为不可变记录：sessionId、sessionName、startedAt、finishedAt、exerciseName、setPosition、EquipmentWeight reading、reps。备份字段如下：

| 数据组 | v4 新字段 |
| --- | --- |
| `plans` | id, name, position, createdAt |
| `templates` | 原字段加 planId |
| `sessions` | 原字段加 planId, planNameSnapshot, dayNameSnapshot, origin |
| `sets` | 原字段加 sourceWeight（可空文本）, sourceUnit |
| `exercisePreferences` | exerciseId, weightUnit, kgStep, lbStep, showKgEquivalent, isFavorite, equipmentNote |

- [ ] **Step 1: 写真实数据库导出／恢复往返测试。** 含两个父计划、不同训练日数、50 lb 组、自定义 lb 步长、kg 偏好、收藏备忘；备份恢复后检查原始标签 `50 lb`、标准重量 `22.6796185`、计划来源和名称均一致。再准备旧 v1/v2/v3 文件升级，检查旧模板只归入一个父计划。
- [ ] **Step 2: 运行新测试，预期当前 v3 丢字段失败。** `flutter test --no-pub test/data/backup_v4_test.dart --reporter expanded`。
- [ ] **Step 3: 实现内存升级函数并接入校验。** 先验证旧输入版本的原结构／限额，再增加默认字段并按旧 templates 生成一个确定且不冲突的 legacy 父 ID；相同备份重复预览必须得到相同结果。禁止先归一化而掩盖非法输入。v4 直接严格校验，不猜单位、不自动修复悬空父子关系。
- [ ] **Step 4: 将导出版本改为 4 并移除 Task 2 的 v3 投影。** 新字段全部进入 snapshot/token/20 MiB/100,000 条限额；恢复先删除 sets、session_exercises、sessions、template_exercises、templates、plans、preferences、exercises，再依赖顺序插入。设置缺省兼容继续遵守旧恢复约定。
- [ ] **Step 5: 校验原始读数与 kg 的一致性。** 标准 weight 与 EquipmentWeight.kilograms 的误差仅允许 `max(1e-9, abs(weight)*1e-12)`；sourceWeight=NULL 只接受 kg。NaN、负读数、无效单位、0／负步长、跨计划训练日关联拒绝，不能以读取失败后改单位来修复。
- [ ] **Step 6a: CSV 导入保留原值并使用同一换算。** 将原 WeightUnit 引用换为 Task 1 重导出；每行 ImportedSet 同时保存解析前的原始重量和单位，weight 仍为 kg。指纹仍基于标准 weight，不能因增加单位字段让同一历史被重复导入。增加 CsvSource.gymTracker，用明确表头 `session_id,start_time,end_time,title,exercise_title,set_index,weight,weight_unit,weight_kg,reps` 识别本应用导出；只有旧格式无明确单位列时才使用原 defaultUnit 语义，Hevy的weight_kg始终为kg。
- [ ] **Step 6b: 新建无损 CSV 编码与保存适配器。** 当前项目只有 CSV 导入，不能修改不存在的导出文件。新仓储查询已完成训练中的已完成组，按 session 开始时间、动作 position 和组 position 稳定排序；查询日期范围与 Task 9 共用 startInclusive/endExclusive。编码将逗号、双引号和换行字段用双引号括起，内部双引号翻倍，行结束使用CRLF；原读数与单位照写，weight_kg使用未展示舍入的kilograms，时间写带偏移的ISO字符串。本应用导入按session_id分组，不能把同时开始但ID不同的两场合并。CSV保存适配器直接用现有file_picker的 `FilePicker.saveFile(fileName:name,bytes:Uint8List.fromList(bytes),mimeType:'text/csv',dialogTitle:'导出训练记录')`，Web返回downloadRequested，原生取消返回canceled，不复用写死JSON MIME的PlatformBackupFileStore.save。
- [ ] **Step 7: 让导入写 origin 并保持历史语义。** importWorkouts 接收新增命名参数 `String origin = 'csv'`；手动路径明确传 manual；不得写计划关联。source 字段加入全库 token，使单位变化也能触发预览失效。
- [ ] **Step 8: 运行兼容与错误注入。** `flutter test --no-pub test/data/backup_v4_test.dart test/domain/workout_csv_export_test.dart test/data/backup_repo_test.dart test/data/backup_repo_boundaries_test.dart test/domain/backup_boundaries_test.dart test/domain/import_pipeline_test.dart test/data/import_repo_test.dart --reporter expanded`；预期新版往返、CSV原值往返及旧文件恢复均通过。
- [ ] **Step 9: 提交。** 信息 `feat: preserve equipment units and plan hierarchy in backups and imports`。

### Task 4: 父计划仓储与每套计划独立推荐

**Files:** Create `lib/domain/training_plans.dart`, `lib/data/repositories/training_plan_repo.dart`, `test/data/training_plan_repo_test.dart`, `test/domain/training_rotation_test.dart`; Modify `lib/data/repositories/template_repo.dart`, `workout_plan_repo.dart`, `session_repo.dart`, `lib/state/active_session_controller.dart`。

**Interfaces:**

```dart
class TrainingPlanDraft {
  final String? id, expectedToken;
  final String name;
  final List<TrainingDayDraft> days;
  TrainingPlanDraft({this.id, this.expectedToken, required this.name,
    required List<TrainingDayDraft> days}) : days = List.unmodifiable(days);
}
class TrainingDayDraft {
  final String? id;
  final String name;
  final List<String> exerciseIds;
  TrainingDayDraft({this.id, required this.name,
    required List<String> exerciseIds}) : exerciseIds = List.unmodifiable(exerciseIds);
}
```

同文件定义 `TrainingDay`：`String id,name` 和不可变 `List<String> exerciseIds`，以及 `TrainingDayDraft toDraft()`；已保存的日 ID 非空。定义 `TrainingPlanDetail`：`String id,name,token`、`int position,createdAt` 和不可变 `List<TrainingDay> days`。仓储签名为 `listTrainingPlans(SqlExecutor)` → `Future<List<TrainingPlanDetail>>`，`getTrainingPlan(SqlExecutor,String)` → `Future<TrainingPlanDetail?>`，`saveTrainingPlan(SqlExecutor,TrainingPlanDraft)` → `Future<TrainingPlanDetail>`，`deleteTrainingPlan(SqlExecutor,String,{required String expectedToken})` → `Future<void>`。

原 `PlannedWorkout` 增加 planId／planName／dayName；原 templateId 始终表示训练日。`loadNextWorkout` 和 `readPlannedWorkout` 增加 `String? planId, String? preferredDayId, bool freeTraining=false`，保留 `preferredTemplateId` 兼容参数作为 preferredDayId 别名；同时传不同值要拒绝。

- [ ] **Step 1: 写两套计划的隔离测试。** A 有三天，B 有两天；完成 A2 后推荐 A3，切 B 仍推荐 B1；活动训练、补记、CSV 不改变任一推荐；完成 B2 回 B1。重复动作项保持独立，删除 A 不删除训练或组。以下为仓储用例的可直接运行内容，文件顶部 import flutter_test、FfiExecutor、training_plans.dart、training_plan_repo.dart、workout_plan_repo.dart；db在setUp用FfiExecutor.openMigrated建立并在tearDown关闭：

```dart
test('完成 A2 不影响 B 的推荐', () async {
  final a = await saveTrainingPlan(db, TrainingPlanDraft(name: 'A', days: [
    TrainingDayDraft(name: 'A1', exerciseIds: []),
    TrainingDayDraft(name: 'A2', exerciseIds: []),
    TrainingDayDraft(name: 'A3', exerciseIds: []),
  ]));
  final b = await saveTrainingPlan(db, TrainingPlanDraft(name: 'B', days: [
    TrainingDayDraft(name: 'B1', exerciseIds: []),
    TrainingDayDraft(name: 'B2', exerciseIds: []),
  ]));
  await db.run(
    'INSERT INTO session(id,started_at,finished_at,template_id,plan_id,origin) '
    'VALUES(?,?,?,?,?,?)', ['done-a2', 1, 2, a.days[1].id, a.id, 'live'],
  );
  expect((await loadNextWorkout(db, planId: a.id)).templateId, a.days[2].id);
  expect((await loadNextWorkout(db, planId: b.id)).templateId, b.days[0].id);
});
```
- [ ] **Step 2: 运行并确认缺少父计划仓储失败。** `flutter test --no-pub test/data/training_plan_repo_test.dart test/domain/training_rotation_test.dart --reporter expanded`。
- [ ] **Step 3: 实现整份草稿事务保存。** 验证父名及日名非空、引用动作存在，原有归档动作允许保留；新 ID 仅在保存事务分配。先比较包含整套父子和动作项的 token，再逐 ID 更新／增删，保存时将顺序重排为连续 position。日内动作项按exerciseId构建旧出现项ID队列，新清单依次复用对应队首ID，新增才newId、未保留项才删除；不能照搬saveTemplate整批删动作项再重建的实现。测试更名、重排与重复动作的既有项ID保留。删除旧日先解除关联，再删动作清单；已有训练快照不变。
- [ ] **Step 4: 实现推荐领域函数。** `String? recommendDay(List<String> orderedDayIds, String? latestDayId)` 的完整逻辑如下，并测试空列表、找不到来源和末尾循环。

```dart
String? recommendDay(List<String> orderedDayIds, String? latestDayId) {
  if (orderedDayIds.isEmpty) return null;
  final index = orderedDayIds.indexOf(latestDayId ?? '');
  return orderedDayIds[index < 0 ? 0 : (index + 1) % orderedDayIds.length];
}
```

- [ ] **Step 5: 只读取当前父计划最近完成来源。** 不在查询中提前过滤已删除日，否则会错误跳到更早的历史；找到最后来源已失效时回首日。

```sql
SELECT template_id FROM session
WHERE plan_id=? AND finished_at IS NOT NULL AND origin IN ('live','legacy')
ORDER BY finished_at DESC, rowid DESC LIMIT 1
```

删除训练日时保留 session.plan_id 和名称快照，仅置 template_id=NULL，使上面规则仍知道最后完成的日已失效；删除整套父计划时同时解除 plan_id。若 origin=legacy 且本来无有效来源，不凭空推断。
- [ ] **Step 6: 扩展开训和选择 token。** ActiveSessionController.startNew 增加 planId/preferredDayId/freeTraining；保留先冲突检查、事务内再检查活动训练、再读取选择与复制动作的顺序。token 包含父 ID、当前顺序、日详情及最近来源，避免编辑或删除后的旧选择继续开训；createSession 同事务写 live 和名称快照。
- [ ] **Step 7: 测试删除、排序和故障回滚。** 在第二个日动作插入时报错，应恢复旧计划和全部动作库。回归 `test/data/plans_and_records_test.dart`、`test/e2e/plan_library_preservation_test.dart`，只调整“旧模板现在属于一个父计划”的新语义，不删失效预览和动作库保留断言。
- [ ] **Step 8: 提交。** 信息 `feat: manage multi-day plans and rotate days independently`。

### Task 5: 多天计划管理及首页选择

**Files:** Create `lib/features/plans/day_editor_sheet.dart`, `test/widget/multiday_plans_test.dart`; Modify `lib/state/plan_controller.dart`, `lib/features/plans/plan_list_page.dart`, `plan_editor_page.dart`, `plan_picker.dart`, `lib/features/workout/workout_home_page.dart`, `lib/app/router.dart`, `lib/app/providers.dart`, `test/state/plan_controller_test.dart`。

**Interfaces:** PlanController 保留 `busy,dirty,message,loadList,loadDraft,saveDraft,discardDraft`，draft 改为 TrainingPlanDraft；新增 `addDay(TrainingDayDraft)`、`updateDay(int,TrainingDayDraft)`、`removeDay(int)`、`moveDay(int,int)`。`showDayEditor(BuildContext,TrainingDayDraft)` 返回 `Future<TrainingDayDraft?>`。父选择和日选择分别返回稳定 ID，不用列表下标。

- [ ] **Step 1: 写 UI 流程测试。** 从“管理计划”新建父计划，添加两个不同训练日，各选不同动作，保存；再次打开可独立编辑。取消日编辑／父编辑不污染已存值；首页没有第二个“新建计划”。
- [ ] **Step 2: 运行目标测试，预期当前编辑页只有动作清单而失败。** `flutter test --no-pub test/widget/multiday_plans_test.dart test/state/plan_controller_test.dart --reporter expanded`。
- [ ] **Step 3: 将 controller 草稿更新改为不可变的父／日集合更新。** 每个新增日的临时 key 仅用于本地 Widget identity；数据库 ID 在 Task 4 保存时分配；取消时丢弃整份草稿。保留现有 busy 防重复保存及 saved-but-refresh-failed 文案。
- [ ] **Step 4: 计划编辑页显示父名称和有序训练日卡片。** 每行包含日名称、动作数、编辑／上移／下移／删除；新增日按钮在父编辑页，新增整套计划按钮只在列表页。日编辑弹层调用现有 showExerciseMultiPicker，保留选择顺序与重复出现项规则；不在日编辑中再创建父计划。providers中的onDeleted不再把父ID传给session.detachTemplate；controller提供明确的onDayDeleted与onPlanDeleted回调，并分别解除活动session的对应关联，不删除其动作或组。
- [ ] **Step 5: 首页使用当前父计划卡片与两个选择器。** 卡片只显示本次计划／日／摘要；切父计划从其独立推荐日开始，手选只影响本次，提供自由训练。使用 `app_setting` 键 `active_training_plan_id` 保存父选择；无效 ID 回首项，无计划自由训练；不要持久化 nextIndex。
- [ ] **Step 6: 运行选择、草稿和 viewport 用例。** `flutter test --no-pub test/widget/multiday_plans_test.dart test/widget/import_and_plans_test.dart test/widget/legacy_plan_start_test.dart test/state/plan_controller_test.dart --reporter expanded`；0／1／8 套计划、0／1／4／8 个训练日和长名称必须可操作。
- [ ] **Step 7: 提交。** 信息 `feat: edit multi-day plans and select the next training day`。

### Task 6: 单位与偏好贯穿组写入、休息和历史

**Files:** Create `test/data/equipment_weight_persistence_test.dart`; Modify `lib/data/repositories/workout_write_repo.dart`, `workout_edit_repo.dart`, `exercise_replacement_repo.dart`, `set_repo.dart`, `exercise_preferences_repo.dart`, `lib/state/active_session_controller.dart`, `exercise_preferences_controller.dart`, `lib/features/workout/edit_set_sheet.dart`, `completed_sets_sheet.dart`, `rest_view.dart`, `next_set_weight.dart`, `lib/features/history/session_detail_page.dart`, `lib/features/workout/summary_page.dart`, `lib/ui/widgets/session_summary_view.dart`。

**Interfaces:** 兼容旧 double 方法，同时新增 typed 方法：`completeCurrentReading(EquipmentWeight,int)` → `Future<void>`、`stagePendingReading(String,EquipmentWeight)` → `void`。旧 `completeCurrentSet(double,int)` 委托前者并构建 kg；旧 `stagePendingWeight` 同理。队列的 payload 是 EquipmentWeight，generation 和 pendingSetId 保持原职责。

仓储 `completeWorkoutSet`、`savePendingWeight`、`updateCompletedSet` 继续保留旧标准 kg 参数，增加可选 `EquipmentWeight? reading`；两者同时传入时必须相符，否则拒绝写入。读取和克隆下一组时保留来源重量，不能只复制标准 kg。

- [ ] **Step 1: 写 50 lb 完成、下一组、休息、重载、编辑、撤销测试。** 检查 source_weight='50'、source_unit='lb'、weight=22.6796185；修改动作偏好到 kg 后已完成组仍为 50 lb。注入延迟写入，完成后旧 lb 草稿不能覆盖下一组。
- [ ] **Step 2: 运行并确认当前 double-only 路径丢单位失败。** `flutter test --no-pub test/data/equipment_weight_persistence_test.dart --reporter expanded`。
- [ ] **Step 3: 改造完成与待填写入的三列更新。** SQL 的 source 字段必须与 weight 在同一个 UPDATE／INSERT 中；所有入口都调用 Task 1 的 kilograms。队列在换动作、完成、开始下一组、预览更正、恢复备份前照旧 flush，typed payload 纳入冲突 token。
- [ ] **Step 4: 修改首组和动作替换默认值。** 读取目标动作偏好，查找最近同单位已完成记录；没有时使用 20 kg 或 45 lb 和现有默认次数 8。不得从另一单位历史换算再设为器械输入。动作替换保留已有完成组的单位，只给目标待填组应用目标动作偏好。
- [ ] **Step 5: 更新更正、撤销和历史展示。** CompletedSetEdit.original 的 equipmentWeight 驱动单位字段；撤销回写原单位和原读数。上一组、休息“刚完成”、已记列表、总结详情均显示原 label，容量汇总和进步图继续用 weight kg；相同单位才可直接比较器械读数。
- [ ] **Step 6: 回归串行与替换。** `flutter test --no-pub test/data/equipment_weight_persistence_test.dart test/data/workout_edit_repo_test.dart test/data/exercise_replacement_repo_test.dart test/state/pending_weight_queue_test.dart test/state/pending_weight_test.dart test/state/complete_set_test.dart --reporter expanded`。
- [ ] **Step 7: 提交。** 信息 `feat: preserve original equipment readings throughout workout writes`。

### Task 7: 按起手区域锁定的重量与次数输入

**Files:** Create `lib/features/workout/adjustment_gesture.dart`, `workout_value_input.dart`, `test/widget/workout_value_input_test.dart`; Modify `lib/features/workout/record_page.dart`, `lib/features/workout/drag_number.dart`（保留其他调用点兼容）、`test/widget/viewport_test.dart`。

**Interfaces:** `AdjustmentTarget { weight,reps }`；`AdjustmentGesture` 提供 `bool begin(int pointer,AdjustmentTarget,Offset origin)`、`int ticks(int pointer,Offset position)`、`bool end(int pointer)`，公开只读 activeTarget。第一次 begin 成功后其他指针被拒绝；ticks 永远相对起点计算。`WorkoutValueInput` 为受控组件，输入 EquipmentWeight、reps、DecimalReading step，输出 onWeightChanged/onRepsChanged 和 onGestureActiveChanged。

- [ ] **Step 1: 写真实指针 widget 用例。** 起点40kg×8，重量斜滑 `(72,-48)` 得47.5kg且次数8；次数斜滑 `(72,-60)` 得11且重量不变；跨区不换对象；pointer2无效；cancel恢复起点；键盘和 Semantics 增减符合各自轴。

测试组件给重量和次数区分别设置 `ValueKey('weight-adjuster')` 与 `ValueKey('reps-adjuster')`。用下面事件序列而不是调用组件内部方法：

```dart
final start = tester.getCenter(find.byKey(const ValueKey('weight-adjuster')));
final gesture = await tester.startGesture(start, pointer: 1);
await tester.pump();
await gesture.moveBy(const Offset(72, -48));
await tester.pump();
expect(find.text('47.5'), findsOneWidget);
expect(find.text('8'), findsOneWidget);
await gesture.cancel();
await tester.pump();
expect(find.text('40'), findsOneWidget);
```
- [ ] **Step 2: 运行，预期缺少统一指针锁失败。** `flutter test --no-pub test/widget/workout_value_input_test.dart --reporter expanded`。
- [ ] **Step 3: 实现轴向档数计算。** 在该类中使用完整公式：

```dart
int ticks(int pointer, Offset position) {
  if (_pointer != pointer || _target == null) return 0;
  final delta = _target == AdjustmentTarget.weight
      ? _origin.dy - position.dy : position.dx - _origin.dx;
  return (delta / (_target == AdjustmentTarget.weight ? 16 : 24)).truncate();
}
```

`_pointer` 是持锁指针、`_target` 是锁定对象、`_origin` 是 begin 保存的 Offset；end 仅释放匹配指针，额外提供 `cancel()` 清空全部锁用于 dispose／页面中断。
- [ ] **Step 4: 用 Listener 处理 pointer 生命周期。** 触点必须落在重量或次数矩形内才调用 begin；不在更新时重新 hit-test。parent 在 active 时忽略滚动和完成按钮，锁定数值高亮、另一数值弱化；pointerCancel、应用失活或 dispose 回传起始值。每次更新使用起始 EquipmentWeight.plusSteps(step,ticks)，不是累计给当前值叠加。
- [ ] **Step 5: 处理边界与反向。** 基础范围为重量0至等效500kg、次数0至100，初始超范围时有效范围扩展包含起始值；只钳制本次结果，不修改持有的原始基线。使用 Task 1 十进制操作，纯水平重量手势输出与起始读数完全相同。
- [ ] **Step 6: 替换记录页两组输入。** 移除两处 NumberStepper 和旧重量 DragNumber 调用，改接统一 WorkoutValueInput；记录页本地重量改为EquipmentWeight，完成调用Task6的completeCurrentReading，不能把50lb的原读数50作为旧completeCurrentSet的kg参数。可访问角色为 slider，重量↑↓、次数←→，提供 onIncrease/onDecrease。其他表单或休息页原有 stepper 不在此次“记录页两对按钮”的移除范围内。
- [ ] **Step 7: 回归小屏和系统取消。** `flutter test --no-pub test/widget/workout_value_input_test.dart test/widget/viewport_test.dart test/state/pending_weight_queue_test.dart --reporter expanded`；在320×480、640×360、字号2.0不溢出且主操作可达。
- [ ] **Step 8: 提交。** 信息 `feat: lock weight and rep gestures to their starting regions`。

### Task 8: 明确选择调重幅度、单位和换算显示

**Files:** Create `lib/data/repositories/workout_settings_repo.dart`, `test/widget/weight_settings_test.dart`; Modify `lib/features/workout/exercise_settings_sheet.dart`, `lib/features/workout/record_page.dart`, `lib/state/exercise_preferences_controller.dart`, `lib/data/repositories/exercise_preferences_repo.dart`, `test/data/exercise_preferences_repo_test.dart`。

**Interfaces:** 复用现有 showExerciseSettingsSheet，面板本地暂存 weightUnit/kgStep/lbStep/showKgEquivalent；保存 controller 必须返回 WorkoutWriteResult。记录页仅在 saved 后更新待填组单位／步长；取消、过期 token 或 busy 保留原输入和偏好。

新增组合事务接口 `Future<ExercisePreference> applyPendingWeightSettings(SqlExecutor exec,{required String sessionId,required String pendingSetId,required String exerciseId,required String expectedPreferenceToken,required EquipmentWeight reading,required DecimalReading kgStep,required DecimalReading lbStep,required bool showKgEquivalent})`。偏好仓储抽出 `writeExercisePreference(SqlExecutor tx,ExercisePreference value)`，仅写当前事务、不发通知；原 saveExercisePreference 也调用该函数。

- [ ] **Step 1: 写确认与取消测试。** 点击幅度只打开面板；选10lb和显示kg但取消，原40kg、2.5kg步长不变；确认后主读数40lb；上滑一档50lb，下方≈22.68kg。另一个动作保持kg；返回第一个动作保留偏好。
- [ ] **Step 2: 运行新 widget 测试。** `flutter test --no-pub test/widget/weight_settings_test.dart --reporter expanded`；预期原面板缺少单位控件失败。
- [ ] **Step 3: 在原面板增加单位 ChoiceChip 和两套步长。** kg：[0.5,1,1.25,2.5,5,10]，lb：[1,2.5,5,10,20]；选中态按当前单位；选择单位保留当前数值，只换待填组的 EquipmentWeight.unit。原收藏、器械备忘编辑和token比较保持。
- [ ] **Step 4: 增加自定义输入与可选换算复选框。** 自定义解析使用 DecimalReading，必须大于0且asDouble有限；取消不写。showKgEquivalent仅在lb模式显示控件，切回kg时隐藏参考但保留该偏好。显示值由 kilograms.toStringAsFixed(2) 生成，主值使用 amount.text。
- [ ] **Step 5: 将偏好和当前待填组放进同一个事务。** 打开面板前flush原队列，确认时由applyPendingWeightSettings先requirePendingSet并校验所属exerciseId和expectedPreferenceToken，再writeExercisePreference及updateSetValues(reading:reading)。事务失败两处均不改；成功仅发一次DataRevision，controller从返回值更新偏好并重载待填组。手势活跃时面板入口禁用，确认过程中阻止完成组和开始下一组；不能先保存全局偏好再异步赌待填单位写入成功。
- [ ] **Step 6: 运行。** `flutter test --no-pub test/widget/weight_settings_test.dart test/data/exercise_preferences_repo_test.dart test/domain/exercise_preferences_test.dart --reporter expanded`；预期独立偏好、1.25显示和原器械备忘用例通过。
- [ ] **Step 7: 提交。** 信息 `feat: choose equipment units and weight increments explicitly`。

### Task 9: 本地日期查询、历史补加和删除归位

**Files:** Create `lib/domain/local_date.dart`, `test/domain/local_date_test.dart`, `test/data/history_date_test.dart`; Modify `lib/data/repositories/session_repo.dart`, `lib/features/history/history_page.dart`, `lib/features/import/import_page.dart`, `manual_workout_form.dart`, `lib/state/import_controller.dart`, `lib/app/router.dart`, `lib/features/settings/settings_page.dart`, `test/widget/history_pages_test.dart`, `test/app/router_test.dart`。

**Interfaces:** `LocalDate.tryParse(String?)`→`LocalDate?`，字段 year/month/day；getters key/start/nextStart；`listSessionSummaries(SqlExecutor,{LocalDate? date})` 保持现有不带筛选调用可用；`HistoryPage({LocalDate? date,bool invalidDate=false})`；ImportPage／ManualWorkoutForm 增加 `LocalDate? initialDate`。已有 `/records/manual` 与 `/records/import` 透传查询日期，不删旧 URL。

- [ ] **Step 1: 写真实日期和路由用例。** 2026-02-30拒绝、10-16的本地起点含入、次日起点排除；同日两场只筛当天，进行中训练排除。从筛选列表push详情再返回仍在当天；补加默认当天，修改日期后返回新日期，取消不写。

```dart
test('日期溢出拒绝且边界来自次日本地零点', () {
  expect(LocalDate.tryParse('2026-02-30'), isNull);
  final day = LocalDate.tryParse('2026-10-16')!;
  expect(day.key, '2026-10-16');
  expect(day.start, DateTime(2026, 10, 16));
  expect(day.nextStart, DateTime(2026, 10, 17));
});
```
- [ ] **Step 2: 运行目标用例。** `flutter test --no-pub test/domain/local_date_test.dart test/data/history_date_test.dart test/app/router_test.dart --reporter expanded`。
- [ ] **Step 3: 实现严格日期值与边界。** 不用 Duration(days:1) 计算本地次日起点；以下代码为 start/nextStart 的完整定义：

```dart
DateTime get start => DateTime(year, month, day);
DateTime get nextStart => DateTime(year, month, day + 1);
```

tryParse仅接受 `^\d{4}-\d{2}-\d{2}$`，构造后逐字段回验年／月／日相同，避免DateTime自动进位；key按两位月日输出。DST测试在独立进程的已配置时区跑，不依赖把Asia/Shanghai的23／25小时天凭空造出来。
- [ ] **Step 4: 扩展原聚合SQL的WHERE。** 在原 `finished_at IS NOT NULL` 后可选增加 `started_at>=? AND started_at<?`，参数分别start和nextStart毫秒；保持汇总算法及原 started_at,rowid 倒序。无日期时SQL语义不变。
- [ ] **Step 5: 历史页加入筛选提示和操作入口。** `context.go('/history?date=${date.key}')` 定位；“查看全部”go普通history；行内调用现有delete_session_dialog按明确ID删除，行tap仍push详情；无记录也显示补加按钮。设置移除计划管理及导入入口，历史次级菜单提供CSV导入与“导出当前列表”；导出调用Task3的readWorkoutCsvRows、encodeWorkoutCsv及saveWorkoutCsv，按当前筛选传起止边界，取消保存不显示成功。
- [ ] **Step 6: 手动补记预填日期和组单位。** 以initialDate初始化开始／结束字段的日期部分，实际时分仍由用户确认；每组 `_SetDraft` 增加WeightUnit。ImportedSet保留reading并从kilograms赋weight；commit返回新增sessionIds，成功后读取新场实际日期再go对应history，刷新失败不重复导入。
- [ ] **Step 7: 保留旧路由及回归删除。** `flutter test --no-pub test/widget/history_pages_test.dart test/app/router_test.dart test/data/session_summary_list_test.dart test/state/import_controller_test.dart test/e2e/plans_and_deletion_test.dart --reporter expanded`。
- [ ] **Step 8: 提交。** 信息 `feat: manage workout records from date-filtered history`。

### Task 10: 月历、居中主操作与最终训练首页

**Files:** Create `lib/features/workout/training_calendar.dart`, `test/widget/training_home_test.dart`; Modify `lib/features/workout/workout_home_page.dart`, `lib/data/repositories/session_repo.dart`, `test/widget/viewport_test.dart`。

**Interfaces:** `listCompletedTrainingDates(SqlExecutor,LocalDate month)`→`Future<Set<String>>`，键为本地日期；`TrainingCalendar({required DateTime displayedMonth,required Set<String> completedDates,required ValueChanged<LocalDate> onDateSelected,required ValueChanged<DateTime> onMonthChanged})`。只查询显示月份，不逐天发SQL。

- [ ] **Step 1: 写首页布局和日期导航widget测试。** 覆盖28／29／30／31天以及六行月份、跨年切月、今天标记、同日多场、删除最后一场；360×780时主按钮中心与可用内容区中心误差不超过2逻辑像素。
- [ ] **Step 2: 运行，预期现首页缺月历失败。** `flutter test --no-pub test/widget/training_home_test.dart --reporter expanded`。
- [ ] **Step 3: 生成周一开头月网格。** leading=`(first.weekday+6)%7`；count=`DateTime(year,month+1,0).day`；cellRows=`((leading+count)/7).ceil()`，空格不可选。日期Semantics明确含“有已完成训练”，不能只靠颜色表示。
- [ ] **Step 4: 接入月完成日期查询。** 按当前月first.start至下月first.start取已结束session的started_at，再在Dart用本地DateTime生成日期键；不使用SQLite UTC date函数分组。DataRevision更新时重载当前月和当前计划摘要，旧异步结果用generation防止覆盖新月份。
- [ ] **Step 5: 完成正常竖屏布局与溢出回退。** LayoutBuilder计算标题＋日历高度和底部计划卡片高度；有空间时用Stack分别放top日历、Alignment.center主按钮、bottom卡片。需要空间超过内容高度时切SingleChildScrollView垂直布局，不用固定780px手机壳尺寸。进行中主操作保持继续训练，其他按钮不建立第二场。
- [ ] **Step 6: 点击日期只导航。** 使用Task9的history?date路由；不能把所点日期写入开训now、父计划或训练日推荐；切月返回本月不影响本次选择。
- [ ] **Step 7: 运行首页和全部视口回归。** `flutter test --no-pub test/widget/training_home_test.dart test/widget/viewport_test.dart test/app/router_test.dart --reporter expanded`；320×480、640×360、字号2.0主按钮可滚动到且无overflow。
- [ ] **Step 8: 提交。** 信息 `feat: center workout start beneath a navigable training calendar`。

### Task 11: 真实应用联动验证与交付证据

**Files:** Create `test/e2e/training_redesign_test.dart`, `scripts/browser_training_redesign_smoke.mjs`, `docs/superpowers/plans/2026-10-17-training-redesign-execution.md`; Modify `scripts/browser_plans_smoke.mjs`, `browser_import_smoke.mjs`, `browser_workout_efficiency_smoke.mjs`, `backup_mutation_check.mjs`, `import_plans_mutation_check.mjs`, `README.md`。

**Interfaces:** 浏览器新套件遵守现有 `export async function run(h)`；h提供check、clickText、clickAt、expectText、send、exportFile、semantics等；通过 `GYM_BROWSER_FEATURE='training_redesign'` 复用现有browser_backup_smoke驱动。所有数据核验读取真实下载的v4文件，不调用仓储代替UI。

- [ ] **Step 1: 写Flutter联动用例。** 经真实UI建立两套多天计划，选其中一天开训；设置lb与5lb步长，滑动后完成两组、撤销／编辑一组、临时替换动作、结束。断言原单位、kg统计、计划未被训练替换篡改、下次推荐日和另一计划独立进度。
- [ ] **Step 2: 写浏览器套件并适配旧套件定位。** 新套件覆盖下表；旧“增加／减少”按钮操作改为CDP pointer滑动或可访问键盘，保留原队列、更正、撤销和替换结果断言；旧计划单层创建步骤改父计划＋训练日；导入路径改从历史进入。不通过减少断言数让旧套件变绿。

新脚本文件的直接运行入口与现有套件保持一致，顶部import node:path、fileURLToPath，定义run(h)后增加：

```javascript
if (process.argv[1] && path.resolve(process.argv[1]).toLowerCase()
    === fileURLToPath(import.meta.url).toLowerCase()) {
  process.env.GYM_BROWSER_FEATURE = 'training_redesign';
  import('./browser_backup_smoke.mjs').catch(error => {
    console.error(error);
    process.exitCode = 1;
  });
}
```

| ID | 浏览器检查 |
| --- | --- |
| R01 | 默认月历、切月、回今天和居中主按钮 |
| R02 | 点击有记录日期定位历史，详情返回保留日期 |
| R03 | 空日补加预填、修改日期后可见、删除刷新月历 |
| R04 | 0／1／多计划及不同训练日数，没有重复父新建入口 |
| R05 | 手选日、完成整场推荐下一日、另一计划进度独立 |
| R06 | 斜滑／跨区的方向锁定、高亮、松手和取消 |
| R07 | 幅度打开不改值，取消不改值，确认生效 |
| R08 | 40lb→50lb→52.5lb与可选kg辅助，动作偏好独立 |
| R09 | 重载后待填单位／重量保留，过去完成组不被偏好改写 |
| R10 | CSV／手动lb录入、原生导出和标准kg一致 |
| R11 | v4真实文件恢复全部层级和单位，旧备份升级 |
| R12 | 360窄屏和横屏截图无关键操作遮挡 |

- [ ] **Step 3: 运行一次适当范围的完整静态与自动化检查。**

```powershell
. .\scripts\env.ps1
dart format --output=none --set-exit-if-changed lib test
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
flutter analyze --no-pub
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
flutter test --no-pub --reporter expanded
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
flutter build web --no-pub --no-wasm-dry-run
```

预期format退出0、analyze无问题、全量测试通过、Web构建成功；保存实际测试数，不将旧396条写作本次结果。代码再次变化或发现新问题时再复跑受影响检查。
- [ ] **Step 4: 运行真实浏览器及变异守卫。**

```powershell
node scripts/browser_smoke.mjs
node scripts/browser_backup_smoke.mjs
node scripts/browser_import_smoke.mjs
node scripts/browser_plans_smoke.mjs
node scripts/browser_workout_efficiency_smoke.mjs
node scripts/browser_training_redesign_smoke.mjs
node scripts/backup_mutation_check.mjs
node scripts/import_plans_mutation_check.mjs
```

各命令单独检查退出码并记录JSON／截图目录。变异脚本必须在finally恢复源文件，新字段校验增加“丢原单位／丢父关联／绕过预览token”拒绝用例；禁止在脚本之间并行修改同一源文件。
- [ ] **Step 5: 构建Android并记录产物。** `flutter build apk --debug --no-pub`、`flutter build apk --release --no-pub`，核对包名`com.mobis.gym_tracker`；对最终release APK运行`Get-FileHash -Algorithm SHA256 -LiteralPath 'build\app\outputs\flutter-apk\app-release.apk'`。不将旧APK哈希照抄进本次记录。
- [ ] **Step 6: 检查设备并如实记录触摸验收。** `adb devices -l`；有已授权设备时按用户已授权范围覆盖安装并验收重量／次数斜滑、跨区、多指、打断、kg/lb器械读数、小屏、熄屏和强杀恢复。没有设备时记录未执行的真实触摸项，自动化结果不替代触感与汗手灵敏度实测。
- [ ] **Step 7: 写执行记录并提交业务最终修正及文档。** 记录每个任务真实状态、测试命令／结果、浏览器证据、迁移与旧备份结果、APK路径与哈希、设备未执行项。提交信息`test: verify training navigation plans and equipment input end to end`；最终status保留用户原文件和讨论目录，不提交profile或build产物。

## 计划自检与覆盖映射

| 设计章节 | 实现任务 |
| --- | --- |
| §2.1 月历、居中、继续训练、计划卡片 | 5、10 |
| §2.2 历史入口、日期定位、补加删除、CSV归位 | 3、9、10 |
| §3.1 多天计划、编辑草稿、排序、删除保留历史 | 2、4、5 |
| §3.2 每计划独立推荐、手选、活动冲突 | 4、5、11 |
| §4.1 手势锁定、方向、取消、边界、可访问性 | 6、7、11 |
| §4.2 幅度选择、自定义、确认和偏好 | 1、2、8 |
| §5 原始器械读数、单位、可选kg、历史保真 | 1、3、6、8、9 |
| §6 数据迁移、备份、事务与DataRevision | 2、3、4、6、9、10 |
| §7 回归、浏览器、真机边界 | 11 |

执行前再次核对实际HEAD；文件责任可在代码审查中小幅调整，但不能删掉产品行为、旧数据兼容或验证断言。应用实现完成以全部自动化和实际可执行的平台检查为证据；真机未执行时明确保留未完成项。
