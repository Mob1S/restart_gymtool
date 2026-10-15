# Phase 3A：JSON 备份与恢复设计

**状态（2026-10-16）**：用户已要求接续实施；文件层、controller、设置入口和恢复刷新已实现，304 条测试与 Web 文件往返通过。Android 真机文件验收仍因设备未连接而待执行，本期尚未满足全部完成定义。准确进度见[当前状态](../plans/2026-10-15-current-state.md)与[实施计划](../plans/2026-10-15-phase3a-backup-and-restore.md)。
**日期**：2026-10-15。
**上游**：[Flutter 总体设计](./2026-10-08-flutter-gym-tracker-design.md) §9–10、[旧项目总纲](./2026-10-08-gym-tracker-design.md) §5.9。
**基线**：Phase 1、Phase 2 完成；schema v3；225 条测试通过。

## 1. 范围与推进顺序

Phase 3 分成两个独立交付：

1. **3A（本设计）**：JSON 导出、严格校验、预览确认、事务恢复、Android 与 Web 文件入口、对抗性验收。
2. **3B（后续独立设计）**：Strong / Hevy / 训记 CSV 导入与手动补记；必须有预览、真实行号、单位换算和整批事务。

先让已有训练能备份、能完整恢复，再增加外部记录来源。Phase 4 的计划管理、轮转和删除界面仍后续实施。

本期恢复采用**整库业务数据替换**，不提供合并恢复、自动去重、云同步或加密密码。文件由用户通过系统文件选择器保存到自选位置；应用不上传文件。

## 2. 方案比较与建议

| 方案 | 优点 | 代价 |
|---|---|---|
| **A：先完整备份恢复，提前补计划存储（推荐）** | 旧格式 v1 / v2 均可完整恢复，含旧计划；现有训练先得到保护 | 提前增加两张计划表，但不增加计划界面或轮转逻辑 |
| B：只备份当前四张训练表 | 改动较少 | 旧 v2 含计划时只能拒绝，不能宣称完整兼容旧备份 |
| C：备份、CSV、计划管理一起做 | 一次覆盖更多功能 | 数据恢复、CSV 解析、计划交互三类问题混在一轮验收，范围明显增大 |

推荐 A。已只读核对旧项目实际源码 `C:/ccproject/gym/src/domain/backup.ts`、`src/repositories/backupRepo.ts` 和 `src/domain/types.ts`，不是根据文档猜字段。

### 需要用户确认的范围调整

旧 v2 备份含 `templates`、`templateExercises` 和 `session.templateId`，当前 Flutter 库只有最后一列。为避免丢弃旧计划，**将计划的两张存储表提前到 Phase 3A**，作为追加迁移 v4；计划编辑、轮转和删除功能仍在 Phase 4。原总体设计中「两张表在 Phase 4 才追加 v4」的时间安排随本设计调整，迁移只追加的规则保持。

## 3. 用户流程

设置页沿用现有卡片与按钮，在外观下增加「数据备份」：

- 「导出备份」：读取一致的数据库快照，生成 JSON，打开系统保存界面。文件名为 `gym-backup-YYYY-MM-DD-HHmmss.json`，使用同一个导出时间生成文件内容和文件名。
- 「从备份恢复」：选择文件 → 读取与校验 → 显示预览 → 明确确认替换 → 事务恢复 → 刷新内存与页面。

预览显示文件名、导出时间、备份格式版本、训练场数、已完成场数、动作数、组数、计划数，以及本机将被替换的训练场数。若本机有进行中训练，要明确写出它也会被替换。

确认文案：「将用备份中的 N 场训练替换本机的 M 场训练。建议先导出当前数据。」按钮为「取消」和「替换并恢复」。空备份必须明确显示「此备份没有训练记录，恢复后本机现有训练将被清空」。

取消选择、取消保存、关闭预览、按返回键均结束当前操作，不弹错误、不写库、不留下禁用状态。处理期间阻止重复提交；真正写库时禁止退出当前恢复流程。

成功后回到训练首页，历史、进步与主题立即反映恢复结果，不要求用户杀进程。若恢复了未结束训练，按现有继续训练与长休息确认规则处理，不替用户结束或编造休息时长。

## 4. 文件协议与旧版兼容

固定标识和字段沿用旧项目：

```json
{
  "format": "gym-tracker-backup",
  "version": 2,
  "schemaVersion": 4,
  "exportedAt": 1792051200000,
  "data": {
    "exercises": [],
    "sessions": [],
    "sessionExercises": [],
    "sets": [],
    "templates": [],
    "templateExercises": [],
    "settings": []
  }
}
```

- JSON 使用 UTF-8，允许文件开头 UTF-8 BOM；不执行文件中的 SQL。
- 导出格式为 v2；v1 和 v2 都可导入，版本大于 2 拒绝并提示更新应用。
- `schemaVersion` 是来源信息，必须为正整数且不大于本机支持版本；恢复绝不把它写回 `app_meta`，本机结构版本由自身迁移维护。
- 六个实体数组使用现有领域实体的 **camelCase 字段**，布尔值用 JSON `true / false`，所有可空字段显式为 `null`，时间戳为整数毫秒。
- v1 的 `templates` / `templateExercises` 缺失时取空数组，`session.templateId` 缺失时取 `null`。显式为错误类型不按缺失放行。
- v2 的计划数组必须存在，已有旧项目 v2 导出器始终输出这两个数组。
- `settings` 是 v2 的可选扩展，形状为 `[{"key":"theme_mode","value":"dark"}]`；本应用导出时总是包含。旧文件缺失该字段时保留本机偏好，存在时替换全部用户偏好。旧 RN 导入器会忽略该扩展，因此向旧 RN 恢复不能迁移主题偏好，但训练和计划字段保持兼容。
- 不导出 `android_metadata` 等平台表；不导入应用结构元数据或任意表名。
- `rowid` 不作为协议字段；各表按原 `rowid ASC` 导出，按数组原顺序插入，保留同毫秒训练和同位置记录的相对次序。

### 4.1 实体字段

| 数组 | 字段 |
|---|---|
| exercises | id, name, muscleGroup, equipment, isCustom, isArchived, createdAt |
| sessions | id, name, startedAt, finishedAt, note, templateId |
| sessionExercises | id, sessionId, exerciseId, position, note |
| sets | id, sessionExerciseId, position, weight, reps, isCompleted, restSeconds, restStartedAt, completedAt |
| templates | id, name, position, createdAt |
| templateExercises | id, templateId, exerciseId, position |
| settings | key, value |

预置与自建动作、归档动作、未结束训练和未完成占位组全部保留。空训练是当前应用可产生的合法数据，备份恢复不删除它；这与 CSV 导入应拒绝无有效组的记录是两个不同契约。

## 5. 校验与资源边界

任何删表记录操作之前，完整校验文件，并生成不可变的规范化对象。仓储恢复入口也校验传入对象，不能只信任界面。错误指向具体路径，例如 `data.sets 第 3 条的 reps 必须是非负整数`。

必须拒绝：

- 非 JSON、根节点不是对象、错误 format、未知 version、非法来源 schema 版本。
- 缺失必需数组、数组元素不是对象、字段缺失或类型错误、布尔值伪装成 0 / 1。
- 空白 ID、数组内重复 ID、重复设置键、孤儿训练动作、孤儿组、孤儿计划动作；非空 `session.templateId` 必须引用存在的计划。
- 非有限重量、负重量、负次数或位置；次数、位置、休息秒数与时间戳必须为整数。时间戳限制为 `0..8640000000000000` 毫秒。
- 两场及以上未结束训练，避免破坏本应用「同时至多一场」的状态约定。
- 超过 20 MiB 的 UTF-8 文件，或总实体记录数超过 100,000。通过可用长度预检与实际分块读取累计双重限额，超限立即停止，不先无限制读入内存。

未知附加字段不透传到 SQLite，规范化只保留协议字段。已结束训练、完成状态和休息原始值不作推断或重算；计算口径不变。

导出也执行同样的记录数与字节数限制；超过限额时不生成无法被本应用恢复的文件，而是明确显示「当前数据超过单份备份上限，未导出」，保留所有本机记录。

## 6. 数据库与事务

### 6.1 追加 v4

v1–v3 的已发布语句不改动。v4 新建：

- `split_template(id TEXT PRIMARY KEY, name TEXT NOT NULL, position INTEGER NOT NULL, created_at INTEGER NOT NULL)`。
- `template_exercise(id TEXT PRIMARY KEY, template_id TEXT NOT NULL REFERENCES split_template(id) ON DELETE CASCADE, exercise_id TEXT NOT NULL REFERENCES exercise(id), position INTEGER NOT NULL)`。
- `template_exercise(template_id)` 索引。

`session.template_id` 沿用现有 v3 列，不重复 ALTER。导入时校验其引用；Phase 4 删除计划时再按计划业务规则维护它。

### 6.2 正式事务接口

为 `SqlExecutor` 增加 `transaction<T>(Future<T> Function(SqlExecutor tx) action)`。Android 和 FFI / Web 均使用底层 `Database.transaction`，回调里的所有 SQL 只通过对应的事务执行器调用。事务内部不再使用外层 Database，也不手工拼 `BEGIN / COMMIT`。底层库明确要求事务内使用 Transaction 对象，异常逃出回调时回滚并重抛。[sqflite 官方说明](https://pub.dev/packages/sqflite#transaction)

导出各表在同一个只读快照事务中完成，避免正在记录训练时读到互不一致的父子表。文件选择、保存和用户确认都在事务之外，避免长时间占用数据库。

恢复在单一事务中：

1. 核对本机仍符合预览时显示的数据状态：预览时保留本机全部业务表与设置的规范 JSON（实体按 rowid、设置按 key 排序，不含 exportedAt）；恢复事务首先按同一规则重读并比较字符串。本机数据变化时要求重新预览，不直接应用过期确认。
2. 删除顺序：`set_entry → session_exercise → session → template_exercise → split_template → exercise`。
3. 插入顺序：`exercise → split_template → template_exercise → session → session_exercise → set_entry`，均用参数化 SQL。
4. 文件存在 settings 时，替换 `app_setting`；不存在时保持本机偏好。
5. 检查外键完整性，提交。任何一步异常必须逃出事务；原数据库内容全部恢复，界面才能显示「数据未改动」。

不恢复 `app_meta.schema_version` 或其他来源元数据，不重建数据库文件，不关闭外键，不为导入重新播种。为保证恢复空动作库后重启仍保持备份原貌，`app_meta` 增加本机内部标记 `seed_initialized=1`。首次安装的播种与标记写入在同一事务完成；已有动作的存量库首次启动补写标记；恢复事务同样写入该标记，保证空库往返不变。事务故障测试也核对该标记是否回滚。

该标记属于本应用结构元数据，不接受备份控制；不更改已发布迁移项。

## 7. 模块边界

| 单元 | 职责 | 依赖 |
|---|---|---|
| domain/backup.dart | 协议、不可变快照、字段与引用校验、预览计数 | Dart 核心库与领域实体；无 Flutter / IO / SQL |
| domain/backup_codec.dart | JSON、UTF-8 BOM、编码与错误位置 | domain/backup.dart；无 Flutter / IO |
| data/repositories/backup_repo.dart | 一致导出、事务恢复、SQL 参数映射、预览状态复核 | SqlExecutor 与领域快照 |
| data/files/backup_file_store.dart | 文件选择、有限读取、保存、取消结果 | 平台文件插件；不依赖数据库 |
| state/backup_controller.dart | 选择、校验、预览、确认、恢复、busy 与错误状态 | 仓储与可注入文件接口 |
| features/settings/backup_section.dart | 设置入口、中文提示与预览确认 | controller 与现有 UI；不碰 db/ |
| app/providers.dart | 装配文件适配器和 controller；提交后刷新依赖 | 既有启动与 Provider 模式 |

恢复后必须清除 ActiveSessionController 的旧 session / exercises / currentIndex，再从数据库恢复，并重新读取 ThemeController。仅调用当前的 resume 不够：它在没有活动训练时不会清掉旧内存引用。历史与进步页面在恢复后必须重新加载，不能继续显示缓存行。

文件层拟新增 `file_picker 13.1.0`，使用单文件读取与保存字节接口；具体平台依赖由解析后的 lockfile 固定。官方支持矩阵包含 Android 与 Web 的 pick / save，13.x 使用 `pickFile()` 和文件实例的读取方法，不照抄旧版 `FilePicker.platform` 示例。[file_picker 13.1.0 官方文档](https://pub.dev/packages/file_picker/versions/13.1.0)

Android 使用系统文件界面，不申请管理全部文件权限。Web 使用上传 / 下载，不把浏览器路径当本机磁盘路径。保存完成的提示按平台实际能力表达，不能把「已触发下载」写成「已校验文件持久保存」。

实施准备已核对到具体差异：锁定的 file_picker_web 4.1.0 在触发下载后返回 null。文件接口因此区分 `saved / downloadRequested / canceled`；不能把 Web 的 null 当成用户取消。这是已有平台语义要求的实现细化，完整接口与代码起点见实施计划 Task 4。

## 8. 验收与故障注入

### 8.1 纯逻辑与真实 SQLite

- v1、旧 v2（含非空计划）、当前 v2（含设置）三个固定 fixture；逐字段校验与往返。
- 自定义 / 归档动作、同毫秒训练、并列 position、进行中训练、占位组、空训练、空备份全部覆盖。
- 坏 JSON、错误标识、未来版本、重复 ID、孤儿引用、错误布尔、负数、超大文件、取消行为分别验证。
- 真实 FFI 库恢复后逐表逐字段比对，保留行序；容量、e1RM 与历史明细保持相同。
- 在删除之后、插入中途、设置替换之后分别注入异常；断言所有业务表及用户偏好都与恢复前一致。
- 人为移除事务、引用检查、rowid 顺序或取消判断，各自至少有一条测试实际变红，再恢复实现。
- v3 → v4 与全新库迁移均通过；v1–v3 原迁移内容不变，既有 225 条测试继续全绿。

### 8.2 界面与端到端

- 实际点击导出、选择恢复、预览、取消、确认；预览前不得调用写库，点击两次不得并发恢复。
- 切换文件后不能恢复上一个预览对象；预览期间本机变化必须重新确认。
- 恢复成功后活动训练、主题、历史与进步即刻刷新；失败与取消后原页面仍可操作。
- Web 发布构建真实下载 JSON，再上传到另一个隔离浏览器数据库，检查完整恢复；不只测试序列化函数。

### 8.3 Android 真机

使用独立 `.acceptance` 包，不清空或替换主应用训练数据：

1. 创建含正常训练、未结束训练、自定义动作及计划引用的 fixture。
2. 通过系统文件界面导出并检查文件不是空壳，解析其真实字段。
3. 在独立包清空后选择文件、预览、确认恢复；核对原始次数、容量、时长、休息空值、计划数据与继续训练。
4. 重启后复核持久化；恢复偏好后主题正确。
5. 对坏 JSON、合法 JSON 但错误协议、孤儿引用分别通过文件界面导入，原记录逐字段保持不变。
6. 取消选择、取消保存、取消确认各走一次，按钮恢复可用。
7. 单独恢复旧格式 v1 与含计划的 v2；记录每项证据，未运行的项不能写成通过。
8. 卸载独立包，保留主应用现有数据，产出默认包名的 release APK。

## 9. 完成定义

1. 用户能在 Android 保存真实 JSON 备份，并恢复到独立空库。
2. 旧 v1 / v2 与当前格式均按本设计保留训练、动作、计划和可用偏好。
3. 坏文件不触发写库；写入中途失败全量回滚；上述故障验证有实际记录。
4. 同毫秒排序、占位组、活动训练与休息值往返不变。
5. 恢复后无需重启即可使用，取消与失败后也可继续操作。
6. 静态检查、全量测试、Web 实际文件往返、Android 真机文件往返及构建全部通过并回填计划。

## 10. 设计推进记录

- [x] 阅读现行规格、数据库接缝、启动流程与旧项目协议源码。
- [x] 比较三种范围方案并提出明确建议。
- [x] 写出协议、事务、文件入口、失败处理、验证和范围调整草案。
- [x] 自查并明确元数据标记的例外、时间戳范围、导出限额及过期预览的比较方法；当前无占位实现要求。
- [x] 用户确认方案与计划存储提前的调整（「按推荐设计继续」）。
- [x] 已提交规格与初版实施计划（a70e692），随后按最新要求补充详细交接与剩余计划。
- [x] 完成本期文件层、controller、UI、304 条测试与 Web 平台文件验收。
- [ ] 完成 Android 真机文件往返验收后，再形成 Phase 3B 独立规格；当前未连接设备。
