# 渐进式插件架构 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **本轮执行边界：用户要求“写一个计划然后停下来”。本文件只记录计划，所有实施任务均未开始。不得因上述技能提示自动启动实施或子代理。** 用户以后要求实施时，再按当时可用的技能与授权执行；缺少上述技能时，不假定其已安装。

**Goal:** 将现有应用逐步改造成支持用户启停的内置插件体系，新安装默认基础训练，升级保留当前功能，并为社区插件未来独立安装建立可复用的协议、数据与执行边界。

**Architecture:** 使用“宿主基础层 + 内置插件目录 + 插件运行管理 + 公共业务协议 + Flutter 界面适配层”。首期插件随 App 编译发布，只实现进程内执行；插件描述、调用协议与数据格式不依赖 Flutter。先接入饮料热量，再接入动作分析，训练事务保留在宿主，避免一次性重写已有业务。

**Tech Stack:** 当前 Flutter 3.47.6 / Dart 3.13.5、Provider、go_router、SQLite、现有 Android MethodChannel 与 Web JavaScript 桥接；首期不引入新的执行引擎或插件平台依赖。

## Global Constraints

- 本计划以提交 `f4969fa`、数据库 schema 11、JSON 备份 v7 为检查基线；实施前重新确认版本，若其他工作已占用版本号，应顺延新增版本并同步测试，不能覆盖已发布迁移。
- 新用户默认启用“训练记录、训练计划、历史、进步统计”；底栏为“训练／历史／进步”。既有备份恢复、CSV 导入与补记仍属于基础能力。
- 热量与动作分析随安装包提供，新安装默认停用；已有用户升级首次进入插件版时，两项功能均启用，之后以用户选择为准。
- 插件入口为“设置 → 插件管理”。首期基础训练显示为必需能力，不提供停用开关。
- 首期插件 ID 固定为 `gym.training`、`gym.calories`、`gym.motion`，发布后不得随显示名称变化。
- 插件停用保留数据库记录、媒体和设置；重新启用可以继续访问。首期不提供卸载插件或删除插件数据功能。
- 界面入口、路由访问、事件订阅和后台活动均受插件状态控制；仅隐藏底栏不算完成。
- 官方功能界面使用公共能力接口。现有 SQL 和原生桥接由宿主适配层封装，不能把数据库执行器或完整宿主对象传入插件。
- 同进程接口约束不构成对恶意代码的安全沙箱。未来独立安装还需要验证执行环境、权限执行和分发机制。
- 通用协议使用可序列化数据、稳定 ID、资源句柄；Flutter `Widget`、`BuildContext`、Provider 与原生纹理对象留在平台/UI 适配层。
- 独立安装预留的是可替换的发现、执行、通信、数据与 UI 边界；不承诺现有 Dart/Flutter 插件无修改即可转换为动态插件。
- 保持 Android 与 Web；现有跨平台限制继续如实显示。构建通过不等于真机验收通过。
- 保留备份 20 MiB 和 100,000 条记录上限，新增插件数据也计入。数据恢复继续预览确认、事务写入、失败整批回滚。
- 用户原有未提交文件不纳入本计划的修改或提交。本轮只新增计划文档，不运行应用测试、构建、安装或发布。

---

## 1. 已确认的设计与首期范围

### 产品状态

| 情况 | 基础训练 | 热量 | 动作分析 |
|---|---|---|---|
| 全新安装 | 启用且不可停用 | 停用 | 停用 |
| 从插件化以前的版本升级 | 启用且不可停用 | 启用 | 启用 |
| 已有插件偏好的安装 | 启用且不可停用 | 沿用选择 | 沿用选择 |
| 恢复训练备份 | 保持可用 | 保留本机启用选择 | 保留本机启用选择 |

启用两项可选插件时保留现有顺序“训练／热量／动作分析／历史／进步”；停用后按相同顺序过滤。选中位置根据路由对应的稳定 ID 计算，不能依赖旧的固定数字索引。

插件管理显示名称、说明、版本、支持平台、所需能力与当前状态。用户主动打开相机或选择文件时才请求对应系统权限，启用插件本身不弹相机授权。

### 首期交付

1. 公共协议、内置目录、兼容检查、生命周期管理、持久化启用状态。
2. 插件管理页、动态底栏、路由守卫、训练组动作扩展入口。
3. 饮料热量和动作分析接入同一套机制。
4. 不依赖功能启用状态的数据保存与备份适配。
5. 一个仅用于开发测试的示例插件，证明增加插件只需实现接口并加入内置目录，无需修改宿主控制流程。
6. SDK 接口说明、兼容和故障恢复约定、Android/Web 验收记录模板。

### 后续独立项目

社区目录与下载、签名/来源验证、独立升级与回退、隔离执行环境、外部插件 UI 渲染、可独立导入的计划内容包分别作为后续项目。本期记录它们的接入点，不制作无法工作的安装按钮或空壳市场。

## 2. 当前代码中的实际接入点

| 现状 | 实施时的处理 |
|---|---|
| `lib/app/app_shell.dart` 固定五个底栏入口 | 从启用的 UI contributions 生成目的地、标题和选中状态 |
| `lib/app/router.dart` 集中注册全部页面，并直接引用全局 `analysisExitGuard` | 路由由内置 UI adapters 提供；统一守卫检查启用状态；退出检查归注册实例所有 |
| `lib/app/providers.dart` 启动时构造所有控制器及 `VideoReviewCleanup` | 基础训练继续启动；可选运行时按状态启动；恢复前协调活动任务 |
| `lib/data/db/migrations.dart` 统一 schema 11 | 只追加 schema 12，保留历史迁移；插件偏好与扩展数据有独立表 |
| `lib/data/repositories/backup_repo.dart` 管理全库备份并直接处理饮料字段 | 接入独立存储适配器；停用不影响饮料导出/恢复；扩展数据独立版本化 |
| `lib/data/repositories/beverage_repo.dart` 写入时通过完整备份计算容量 | 提取宿主容量检查入口，插件不依赖整个备份实现；仍在同一写事务内校验 |
| 热量页面直接读 `SqlExecutor`，分析页面构造 `MotionProjectRepo` | 改为注入有限能力客户端；SQL 留在宿主兼容适配器 |
| `lib/features/workout/completed_sets_sheet.dart`、`lib/features/history/session_detail_page.dart` 固定显示复盘入口 | 查询 `training.set.actions` 扩展点，分析插件停用时不提供该入口 |
| `web/index.html` 无条件引用 motion/beverage runtime | 改为宿主按首次能力调用加载对应脚本，停用时关闭已创建的活动资源 |
| Android `ReviewPlugin.onAttachedToEngine` 立即创建纹理和 Surface，现有 close 只取消任务与关闭相机 | 通道注册保持轻量，媒体资源延迟创建；增加可等待的插件级 deactivate，完成任务收尾并释放资源 |

现有数据库表无需立即全部迁移成通用文档表。旧饮料/分析表通过宿主兼容适配器继续使用；新增普通插件私有 JSON 数据使用命名空间存储。公共插件代码不能依赖这些表名。

## 3. 文件职责图

下表中“新增”为规划路径；“修改”为已存在文件。实施时每个文件只承担表中职责。

| 路径 | 操作与职责 |
|---|---|
| `lib/plugins/api/plugin_manifest.dart` | 新增，纯 Dart 清单、兼容范围、依赖、平台与能力声明 |
| `lib/plugins/api/plugin_protocol.dart` | 新增，调用、事件、错误、数据封装类型 |
| `lib/plugins/api/plugin_runtime.dart` | 新增，宿主接口和运行实例生命周期 |
| `lib/plugins/runtime/plugin_catalog.dart` | 新增，目录接口与已编译插件定义，不执行插件 |
| `lib/plugins/runtime/plugin_manager.dart` | 新增，状态机、依赖解析、启停和错误隔离 |
| `lib/plugins/runtime/in_process_runner.dart` | 新增，进程内实例创建和资源回收 |
| `lib/plugins/runtime/plugin_scope.dart` | 新增，按实例管理可撤销注册、任务和订阅 |
| `lib/plugins/host/plugin_host.dart` | 新增，按授权能力分派请求，绑定调用者身份 |
| `lib/plugins/host/legacy_feature_services.dart` | 新增，组装饮料/分析存储与平台兼容适配器；不放 UI |
| `lib/plugins/host/scoped_plugin_store.dart` | 新增，仅允许读写绑定插件 ID 的私有数据 |
| `lib/plugins/flutter/plugin_ui_adapter.dart` | 新增，Flutter 页面、导航、训练组操作扩展点 |
| `lib/plugins/bundled/bundled_catalog.dart` | 新增，唯一的生产插件组合入口 |
| `lib/plugins/bundled/training_plugin.dart` | 新增，声明基础训练已有入口，复用现有事务实现 |
| `lib/plugins/bundled/calories_plugin.dart` | 新增，热量清单、能力客户端和 UI 注册 |
| `lib/plugins/bundled/motion_plugin.dart` | 新增，动作分析清单、运行会话及 UI 注册 |
| `lib/data/db/plugin_migration.dart` | 新增，schema 12 表和默认偏好初始化 |
| `lib/data/repositories/plugin_state_repo.dart` | 新增，安装起源、启用偏好读写；不启动插件 |
| `lib/data/repositories/plugin_document_repo.dart` | 新增，宿主内部命名空间 JSON 存储 |
| `lib/data/repositories/plugin_backup_adapter.dart` | 新增，备份协调接口及已知/未知插件数据处理 |
| `lib/domain/plugin_backup.dart` | 新增，插件备份封装的纯数据校验 |
| `lib/features/settings/plugin_management_page.dart` | 新增，插件列表、详情与启停反馈 |
| `lib/app/providers.dart`、`router.dart`、`app_shell.dart` | 修改，宿主接线和启用状态驱动的导航 |
| `lib/features/settings/settings_page.dart` | 修改，增加插件管理入口 |
| `lib/features/calories/`、`lib/state/beverage_search_controller.dart` | 修改，替换直接存储/平台调用，保留现有业务行为 |
| `lib/features/analysis/`、`lib/state/motion_analysis_controller.dart` | 修改，能力注入、退出检查和可等待的关闭流程 |
| `lib/state/video_review_cleanup.dart` | 修改，将清理工作注册到动作分析运行实例 |
| `lib/domain/backup.dart`、`backup_codec.dart`、`backup_upgrade.dart` | 修改，增加 v8 封装并保持 v1–v7 兼容 |
| `lib/data/repositories/backup_repo.dart`、`lib/state/backup_controller.dart` | 修改，插件存储协调与恢复前任务协调 |
| `web/plugin_runtime_loader.js` | 新增，现有脚本按需加载、失败重试和并发复用 |
| `web/index.html`、`web/motion/runtime.js`、`web/beverage/runtime.js` | 修改，注册加载与明确关闭资源 |
| `android/app/src/main/kotlin/com/mobis/gym_tracker/review/ReviewPlugin.kt` | 修改，原生能力激活状态、纹理/Surface/worker 延迟创建和可等待释放 |
| `android/app/src/main/kotlin/com/mobis/gym_tracker/review/MotionCamera.kt` | 修改，相机关闭完成信号，与插件 deactivate 协调 |
| `lib/data/files/motion_bridge_native.dart`、`lib/data/files/beverage_ocr_native.dart` | 修改，接入宿主资源生命周期，保留平台错误语义 |
| `docs/plugins/development.md` | 新增，SDK、示例接入、版本与权限规则 |
| `test/support/plugin_fakes.dart` | 新增，生命周期计数、故障注入和宿主能力替身 |

首期 SDK 在 `lib/plugins/api/` 内维护，通过分层测试守住边界；对外发布独立 Dart 包属于后续 SDK 发布工作，避免本次同时重组整个仓库。

## 4. 接口和数据约定

### 4.1 清单及调用协议

`PluginManifest` 的必填字段：`id`、`name`、`description`、`version`、`apiMin`、`apiMax`、`platforms`、`requiredCapabilities`、`optionalCapabilities`、`dependencies`、`requiredByHost`。`version` 是插件自身版本字符串；宿主协议版本使用整数，首期为 1；依赖为插件 ID 及其 API 范围，不用显示名称表达依赖。

声明不等于授权：运行宿主根据实际支持和授权集合提供能力。网络属于可选能力时，拒绝后本地饮料库和手动记录仍可使用。

以下是公共契约的具体形状；实现文件需要补齐各 DTO 的构造、只读拷贝与 JSON 校验，不允许把运行对象放入 JSON：

```dart
typedef JsonMap = Map<String, Object?>;

enum StopDecision { ready, busy, unsavedChanges }
enum PluginState { disabled, starting, enabled, stopping, failed }

abstract interface class PluginHost {
  Set<String> get grantedCapabilities;
  Future<JsonMap> request(String method, JsonMap arguments);
  Stream<JsonMap> subscribe(String topic);
}

abstract interface class PluginRuntime {
  Future<void> start(PluginHost host);
  Future<JsonMap> invoke(String method, JsonMap arguments);
  Future<void> cancel(String requestId);
  Future<StopDecision> prepareStop();
  Future<void> stop();
}

abstract interface class PluginCatalog {
  Future<List<PluginManifest>> discover();
}
```

- `PluginHost` 已绑定插件身份，调用参数不得让插件自填其他插件 ID 以取得其权限。
- 公共请求带 `requestId`、`protocolVersion: 1`；异步事件带 `requestId`、`generation`、`type`、`payload`，取消或换代后丢弃旧事件。
- 错误码固定为 `unsupportedApi`、`unsupportedPlatform`、`missingDependency`、`permissionDenied`、`pluginDisabled`、`busy`、`unsavedChanges`、`cancelled`、`timeout`、`storageFailure`、`invalidData`、`internalError`；界面显示可理解中文，不泄漏原生路径作为用户提示。
- JSON 中允许 null、布尔、有限数值、字符串、列表和字符串键对象；时间使用 Unix 毫秒，实体引用使用稳定 ID。媒体传递受限资源句柄，不能把视频或逐帧图片整体编码进控制消息。
- 内置调用不要求每次真正编码/解码 JSON；协议测试必须通过编码往返。高频视频帧继续走平台专用通道，控制、取消和结果描述遵循公共协议。

### 4.2 扩展点与宿主能力

| 名称 | 输入／输出与约束 |
|---|---|
| `navigation.primary` | 稳定 destination ID、route、label、iconKey、order；Widget 构建器属于 Flutter adapter |
| `training.set.actions` | 输入 setId，输出已启用插件贡献的操作描述；当前提供“动作分析” |
| `settings.sections` | 设置项描述和页面 ID；复用宿主主题 |
| `storage.private.read/write` | key、JSON value；宿主自动绑定 pluginId；写入接受一批操作并原子提交 |
| `training.set.read` | setId → 有限的训练组快照；已删除时返回不存在，不泄漏 SQL |
| `calories.library/records` | 宿主兼容服务封装现有 BeverageRepo，保留日期、能量精度和历史快照语义 |
| `motion.projects` | 宿主兼容服务封装项目仓库；只返回对应插件的项目与资源句柄 |
| `media.pick`、`camera.capture` | 用户操作触发；返回媒体句柄和平台能力，停用后撤销实例访问 |
| `network.foodSearch` | 固定饮料搜索服务接口，错误不阻塞本地功能 |

`calories.*` 与 `motion.*` 是本期迁移现有存储的明确兼容服务。它们的实现由宿主组合入口安装，但通过同一权限分派器调用；不允许以“官方插件”为由返回 `SqlExecutor`。新社区插件使用命名空间存储和公共训练查询能力，不依赖这些旧表适配器。

### 4.3 生命周期和持久状态

持久化“用户希望启用”与内存中的实际运行状态分开记录。启动失败显示失败原因和重试入口，不让整个应用启动失败；不自动反复重试。

```text
disabled -> starting -> enabled -> stopping -> disabled
starting/停止资源失败 -> failed（训练基础能力继续可用）
prepareStop = busy/unsavedChanges -> 保持 enabled，提示先完成或保存任务
```

首期选择明确的停用规则：存在分析、录制、保存或未保存编辑时拒绝本次停用，提示返回任务处理后重试；不暗中丢弃内容，也不在后台挂一个持久待停用请求。退出页面原有“保存/放弃/取消”流程继续有效。

启用提交顺序：检查兼容/依赖 → 创建受限宿主 → 启动 → 保存启用偏好 → 发布 UI 注册；保存偏好失败必须撤销刚启动的实例。停用先阻止新请求，检查安全点，等待资源关闭和注册撤销，再保存停用状态并调整当前路由。发生错误时显示实际状态，不把尚未关闭的相机标记为已停用。

所有启停操作在管理器内串行执行，避免双击和启停交错。注册/订阅以实例 token 持有，清理幂等，不能清理掉后来重启的新实例。普通控制调用和 start/stop 采用 10 秒超时；长媒体任务使用进度与显式取消，不套用此超时。超时不能宣称任务已停止，宿主必须先撤销新请求并调用平台关闭，确认未关闭时显示失败状态。

### 4.4 安装识别、存储和备份

- 在 `migrate()` 运行历史迁移前记录安装起源到 `app_meta.plugin_install_origin`。无 schema/领域表的真正新库记为 `fresh`；已有 schema 或领域表记为 `legacy`。该标记使用 insert-if-absent，崩溃重试不改写。
- 不能通过训练条数、饮料条数判断新用户；清空记录的老用户仍属于升级安装。
- schema 12 新增 `plugin_state(plugin_id PRIMARY KEY, desired_enabled INTEGER)`、`plugin_document(plugin_id, document_key, data_version, payload, PRIMARY KEY(plugin_id, document_key))`、`plugin_data_version(plugin_id PRIMARY KEY, data_version INTEGER)`。
- `plugin_data_version` 保留空记录插件的格式版本，也用于保存未知插件的封装。每个命名空间只允许一个数据版本；新版本迁移在宿主事务中完成。
- 新建默认偏好、三张表和 schema 12 版本号在同一事务内提交。启用选择属于本机安装状态，不随训练备份覆盖。
- v8 备份保留 v7 `data` 中的训练和饮料字段，增加必需的根字段 `plugins`；新导出明确使用 `version: 8`、`schemaVersion: 12`。饮料仍由存储适配器读写既有字段，避免一次重构同时更换全部历史数据位置。
- `plugins` 用于新增命名空间数据，格式如下。`gym.training`、`gym.calories`、`gym.motion` 在 v8 中属于保留 ID，不允许同时出现在该扩展区，防止与旧字段形成两份事实来源。

```json
{
  "community.example": {
    "dataVersion": 1,
    "records": [
      {"key": "preferences", "value": {"displayUnit": "kg"}}
    ]
  }
}
```

- v1–v7 没有 `plugins`：保留本机扩展数据；v8 缺少该字段：拒绝。v8 的某个 ID 缺失：保留本机该命名空间；存在且 records 为空：明确清空该命名空间，并保留版本。
- 未安装插件的封装按 ID、版本和内容完整保留并可再次导出，不执行其中内容。未来已安装插件的数据版本不兼容时，拒绝激活，保留原始数据；需要变换数据时走有版本的事务迁移。
- 首期动作分析视频和结果继续不进入 JSON 备份；停用保留本机媒体，恢复训练备份仍解除分析项目与旧训练组的关联。预览明确说明这项限制，不把“支持插件备份”写成“包含视频备份”。
- 扩展 records 数计入总记录数，整个备份编码后的字节数计入 20 MiB；扩展 JSON 最大嵌套深度 32，拒绝重复 key、重复 ID、非有限数值及非法版本。未知插件也受相同结构和容量限制。
- 备份预览基线包含扩展数据；预览后任何扩展写入都应使恢复预览失效。核心、饮料、已知/未知扩展数据在同一 SQLite 事务中恢复，不允许部分成功。
- 恢复前暂停新插件写入，确认活动会话已安全结束；恢复后通知数据变化。停用插件的存储适配器仍参与备份，执行 UI/相机运行时不因此启动。

## 5. 实施任务

按 Task 1 → 2 → 3 → 4 → 5 → 6 → 7 → 8 执行。每个任务先补能复现风险的测试，再实现对应行为，再运行指定检查；测试通过并审阅 diff 后才形成独立提交。本文件中的命令均为未来实施命令，本轮不执行。

### Task 1：公共契约、内置目录与边界守卫

**Files:** 新增 `lib/plugins/api/` 下三份文件、`lib/plugins/runtime/plugin_catalog.dart`、`lib/plugins/bundled/bundled_catalog.dart`、`test/plugins/plugin_protocol_test.dart`、`test/plugins/plugin_manifest_test.dart`；修改 `test/layering_test.dart`。

**Consumes:** 第 4 节协议；现有纯 Dart domain 类型。

**Produces:** `PluginManifest`、`PluginHost`、`PluginRuntime`、`PluginCatalog` 以及 DTO 的 `toJson()/fromJson()`；宿主协议版本常量 `pluginApiVersion = 1`。

- [ ] 添加清单校验测试：重复 ID、宿主 API 超出范围、依赖不存在/成环、平台不支持均产生明确错误；可选能力缺失不拒绝整个插件。
- [ ] 添加消息往返测试：null、整数时间戳、带 Unicode 的名称、空结果可还原；Widget/任意对象、NaN、错误协议版本被拒绝。
- [ ] 按第 4.1 节实现纯 Dart 契约，目录只提供描述和内置构造映射，不在 discover 时启动实例或访问相机。
- [ ] 扩展分层守卫：`plugins/api` 禁止 Flutter、Provider、数据库、平台文件 import；插件 UI 禁止直接 import `data/db` 和内部 Controller，允许显式 UI adapter 与能力客户端。
- [ ] 运行 `flutter test test/plugins/plugin_protocol_test.dart test/plugins/plugin_manifest_test.dart test/layering_test.dart`。预期全部通过，清单错误不会变成整应用启动异常。
- [ ] 审阅并提交：`feat: define bundled plugin contracts and catalog`。

**具体协议样例：**

```json
{"requestId":"request-1","protocolVersion":1,"method":"training.set.read","arguments":{"setId":"set-1"}}
```

测试应断言 `setId` 和 requestId 在往返后相等，而非仅断言序列化字符串非空。

### Task 2：默认选择、升级识别和私有存储

**Files:** 新增 `lib/data/db/plugin_migration.dart`、`lib/data/repositories/plugin_state_repo.dart`、`plugin_document_repo.dart`、`test/data/plugin_migration_test.dart`、`test/data/plugin_document_repo_test.dart`；修改 `lib/data/db/migrations.dart`。

**Consumes:** 固定插件 ID、命名空间数据规则。

**Produces:** `Future<Map<String, bool>> loadPluginPreferences(SqlExecutor exec)`、`Future<void> savePluginPreference(SqlExecutor exec, String pluginId, bool enabled)`；`PluginDocumentRepo` 提供命名空间内的事务读写，宿主持有执行器。

- [ ] 添加真实 FFI SQLite 测试：新库仅 training=true；旧 schema 11 空库升级三项=true；已有偏好重启不覆盖；重复迁移幂等；写版本号失败全部回滚；初始化起源后中断重试仍维持 fresh。
- [ ] 在历史迁移开始前持久化起源，追加 schema 12 专用事务分支；不把带默认偏好逻辑的迁移仅塞入通用 SQL 列表。
- [ ] 建立三张表与唯一约束，基础训练的关闭写入由仓库拒绝；可选插件启停偏好失败必须可报告，不静默当成功。
- [ ] 私有存储测试使用两个插件的相同 document key，断言互不覆盖；跨 ID 访问在绑定宿主层拒绝；多项写入中途异常全部回滚。
- [ ] 运行 `flutter test test/data/plugin_migration_test.dart test/data/plugin_document_repo_test.dart test/data/migrations_test.dart`。
- [ ] 审阅并提交：`feat: persist plugin defaults and namespaced data`。

**核心迁移断言示例：**

```dart
test('全新安装默认基础训练', () async {
  final exec = await FfiExecutor.openInMemory();
  addTearDown(exec.close);
  await migrate(exec);
  expect(await loadPluginPreferences(exec), {
    'gym.training': true,
    'gym.calories': false,
    'gym.motion': false,
  });
});
```

上述测试文件使用 `flutter_test`、`ffi_executor.dart`、`migrations.dart` 和 `plugin_state_repo.dart` 的实际 import。旧库 fixture 应按已发布 schema 11 构造，不能通过“删掉所有业务记录”模拟新安装。

### Task 3：生命周期、受限宿主和可等待的资源回收

**Files:** 新增 `lib/plugins/runtime/plugin_manager.dart`、`in_process_runner.dart`、`plugin_scope.dart`、`lib/plugins/host/plugin_host.dart`、`scoped_plugin_store.dart`、`test/support/plugin_fakes.dart`、`test/plugins/plugin_manager_test.dart`、`test/plugins/plugin_host_test.dart`。

**Consumes:** Task 1 契约、Task 2 偏好仓库。

**Produces:** `PluginManager` 提供 `Future<void> initialize()`、`Future<void> setEnabled(String pluginId, bool enabled)`、`bool isEnabled(String pluginId)`、`Future<void> shutdown()`；错误通过第 4 节错误码返回，状态变化供 UI 监听。

- [ ] 替身记录 start/stop 次数、活动订阅、待处理请求、能力调用；允许指定 start、stop、偏好落库失败，以及永不返回的控制请求。
- [ ] 实现依赖检查和管理器串行队列，按第 4.3 节处理 busy、unsavedChanges、超时和偏好失败；拒绝停用 requiredByHost 插件。
- [ ] 宿主能力分派检查当前实例 token、授权、目标方法和参数；撤销 token 后的旧事件和写请求被拒绝。
- [ ] 测试启用两次只产生一个活动实例；启用失败无残留注册；停用重开无重复订阅；一个插件失败不影响训练；没有能力授权时不进入存储/相机替身。
- [ ] 测试有未保存内容时 setEnabled(false) 返回 unsavedChanges，偏好和数据均不变化；关闭失败不能报告 disabled；持久化失败按实际运行状态给出可恢复错误。
- [ ] 运行 `flutter test test/plugins/plugin_manager_test.dart test/plugins/plugin_host_test.dart`。
- [ ] 审阅并提交：`feat: manage plugin lifecycles and scoped capabilities`。

这里的故障隔离只覆盖受控异步异常和资源清理；同进程无限循环、原生崩溃不在其保证范围内。

### Task 4：插件管理、动态导航和深链接

**Files:** 新增 `lib/plugins/flutter/plugin_ui_adapter.dart`、`lib/plugins/bundled/training_plugin.dart`、`lib/features/settings/plugin_management_page.dart`、`test/widget/plugin_management_test.dart`、`test/app/plugin_router_test.dart`；修改 `lib/app/providers.dart`、`lib/app/router.dart`、`lib/app/app_shell.dart`、`lib/features/settings/settings_page.dart`、`test/app/router_test.dart`。

**Consumes:** PluginManager、内置目录、已持久化偏好。

**Produces:** `/settings/plugins` 页面；稳定的导航 contribution；停用插件的解释页与启用入口。

- [ ] 新增 UI 场景：新安装只有三项底栏；旧用户五项；启停即时刷新；当前插件停用后返回训练主页；历史详情和训练记录仍使用原来的全屏路由。
- [ ] 路由表由本期已知内置 adapters 注册一次，状态变化只刷新 redirect 和可见导航；保持 GoRouter 实例稳定，不在 build 时重新创建。
- [ ] `/calories`、`/analysis/*`、旧 `/review/:setId` 深链接都经过同一守卫。停用时进入说明页，不执行插件页面构造；用户启用后可继续原目标，目标参数先按已注册路由验证。
- [ ] 说明页文案：“此功能尚未启用。启用后可继续，已有数据会保留。”当前平台不支持时显示原因，不提供无效启用按钮。
- [ ] 插件列表显示启用状态、简介、所需能力；处理中禁用重复点击；启动/关闭失败显示重试或返回任务处理的提示。
- [ ] 测试状态改变不重置活动训练、计时或计划选择；重启后保留用户选择；恢复备份不改变启用选择。
- [ ] 运行 `flutter test test/app/router_test.dart test/app/plugin_router_test.dart test/widget/plugin_management_test.dart test/widget/training_home_test.dart`。
- [ ] 审阅并提交：`feat: add plugin management and adaptive navigation`。

**导航算法：** 固定贡献的 order 依次为 training=100、calories=200、motion=300、history=400、progress=500；先过滤实际 enabled 项，再按 order 排序，以 route 所属 destination ID 查找 selectedIndex。未知位置不直接假定旧数字下标。

### Task 5：饮料热量插件与按需平台能力

**Files:** 新增 `lib/plugins/bundled/calories_plugin.dart`、`lib/plugins/host/legacy_feature_services.dart`、`web/plugin_runtime_loader.js`、`test/plugins/calories_plugin_test.dart`；修改 `lib/features/calories/`、`lib/state/beverage_search_controller.dart`、`lib/data/repositories/beverage_repo.dart`、`lib/data/files/beverage_ocr_web.dart`、`lib/data/files/beverage_http_web.dart`、`web/index.html`、`web/beverage/runtime.js`、`scripts/browser_calories_smoke.mjs`。

**Consumes:** host request/subscribe、UI adapter、PluginManager。

**Produces:** 可启停的 gym.calories；现有饮料数据通过宿主兼容服务访问，页面不持有 SqlExecutor；平台能力首次实际使用才初始化。

- [ ] 给现有饮料领域行为建立服务契约测试：份量、kJ/kcal 精度、收藏归档、历史快照、日期边界及写入失败回滚均保持。
- [ ] 将页面中的直接仓库/平台构造替换成受限客户端；宿主适配器复用原仓库。将容量检查作为宿主写事务责任，接口不要求插件 import backup_repo。
- [ ] OCR/搜索会话在页面离开和插件停用后取消；停止后返回的旧结果不能写库或触发页面更新。带未保存表单时按生命周期规则拒绝停用。
- [ ] Web loader 用一个按资源 ID 缓存的 Promise 合并并发加载；失败时移除失败项，后续可重试。停用无需承诺卸载脚本内存，但必须停止 worker、相机和订阅；不能自动加载 OCR 模型。
- [ ] 浏览器脚本先通过设置启用热量，再执行既有场景；另加默认停用时不初始化 OCR/网络能力的证据。
- [ ] 运行 `flutter test test/plugins/calories_plugin_test.dart test/widget/calories_page_test.dart test/widget/beverage_form_test.dart test/data/beverage_repo_test.dart test/state/beverage_search_controller_test.dart`。
- [ ] 审阅并提交：`refactor: register calories as a bundled plugin`。

**验收动作：** 启用 → 新增饮料与饮用记录 → 停用 → 重启 → 重新启用；记录 ID、历史快照和数值逐字段不变。模拟网络失败时，个人库和手动记录仍可用。

### Task 6：停用可备份、未知插件数据与 v8 恢复

**Files:** 新增 `lib/domain/plugin_backup.dart`、`lib/data/repositories/plugin_backup_adapter.dart`、`test/data/plugin_backup_test.dart`、`test/domain/plugin_backup_validation_test.dart`；修改 `lib/domain/backup.dart`、`backup_codec.dart`、`backup_upgrade.dart`、`lib/data/repositories/backup_repo.dart`、`lib/state/backup_controller.dart`、`lib/features/settings/backup_preview_dialog.dart`、`scripts/browser_backup_smoke.mjs`。

**Consumes:** Task 2 存储、第 4.4 节备份规则；PluginManager 的任务协调入口。

**Produces:** v8 导出与 v1–v8 导入；不启动 UI/媒体运行时的存储适配器；未知数据的持久保存与再次导出。

- [ ] 将 validate/encode/upgrade 的版本处理更新为显式 v8 规则，保留旧版本分支；schemaVersion 仍标识导出数据格式需要的结构，不以运行时插件状态推导。
- [ ] 备份快照、容量判断、预览基线和恢复事务同时包含扩展数据；插件启用偏好不进入可替换的 settings，保留旧主题恢复行为。
- [ ] 未知命名空间按封装完整落库；显式空 records 清空，缺失 ID 保留；拒绝保留 ID 冲突和不合法的 JSON 结构。
- [ ] 备份 preview 增加“已知插件数据／未安装插件数据／不包含视频”说明；预览后插件数据改变应要求重新预览。
- [ ] 覆盖 v1–v6 保留本机饮料、v7/v8 饮料替换、关闭热量仍能导出恢复、未知插件往返、空记录版本保留、超限、故障回滚及恢复后启用状态不变。
- [ ] 运行 `flutter test test/data/plugin_backup_test.dart test/domain/plugin_backup_validation_test.dart test/data/backup_repo_test.dart test/data/backup_repo_boundaries_test.dart test/domain/backup_boundaries_test.dart test/state/backup_controller_test.dart`。
- [ ] 审阅并提交：`feat: preserve plugin data in versioned backups`。

**未知插件往返的具体判据：** 导入包含 `community.example` 的上述 JSON → 退出重开 → 导出 → 比较插件 ID、dataVersion、records key/value 深度相等；不得只比较记录数量。再导入同 ID 的空 records，确认只清空该命名空间，不改变训练和其他插件数据。

### Task 7：动作分析插件、训练组扩展入口与媒体清理

**Files:** 新增 `lib/plugins/bundled/motion_plugin.dart`、`test/plugins/motion_plugin_test.dart`；修改 `lib/features/analysis/analysis_home_page.dart`、`analysis_session_page.dart`、`motion_catalog_page.dart`、`lib/state/motion_analysis_controller.dart`、`lib/state/video_review_cleanup.dart`、`lib/features/workout/completed_sets_sheet.dart`、`lib/features/history/session_detail_page.dart`、`lib/data/files/motion_bridge_web.dart`、`lib/data/files/motion_bridge_native.dart`、`web/motion/runtime.js`、`lib/app/providers.dart`、`scripts/browser_motion_smoke.mjs`、`scripts/browser_motion_ui_smoke.mjs`、`android/app/src/main/kotlin/com/mobis/gym_tracker/review/ReviewPlugin.kt`、`android/app/src/main/kotlin/com/mobis/gym_tracker/review/MotionCamera.kt`。

**Consumes:** PluginManager、training.set.actions、受限媒体/项目能力、Web loader。

**Produces:** gym.motion 完整生命周期；分析退出检查按实例注册；等待平台关闭的 `Future<void> closeSession()` 流程。

- [ ] 将全局 analysisExitGuard 改为页面实例持有的退出注册，返回可幂等撤销句柄；多个页面切换后不能留下旧 guard。
- [ ] 项目存储、训练组查询与 MotionBridge 通过宿主能力注入；原生纹理和帧传输留在 Flutter/platform adapter，不进入通用 JSON。
- [ ] 显式实现可等待的 closeSession：停止/取消当前任务，撤销旧 generation，等待订阅取消和平台 close，再释放 UI 播放器/纹理。Widget dispose 只做幂等兜底，不作为确认关闭完成的唯一证据。
- [ ] Android 增加插件级 activate/deactivate：onAttachedToEngine 仅注册通道并保留创建资源所需的引用；首次媒体请求才创建 worker、纹理和 Surface。deactivate 拒绝新任务、取消旧 generation、等待相机关闭和在途任务退出，再释放资源并返回完成，不能在主线程阻塞等待。重新激活能创建新的资源，capabilities 查询不初始化媒体资源。
- [ ] Web 与 Android 使用一致的“会话关闭”和“插件停用”语义；原有 close 的立即返回不能被当作 worker 已结束的证明。真机取证应同时确认相机释放、旧事件不再抵达与重新启用成功。
- [ ] 相机预览、录制、分析、保存、未保存编辑状态拒绝直接停用；处理完活动页面后可停用。重新启用不会重复持有相机或恢复旧任务回调。
- [ ] VideoReviewCleanup 仅在分析运行实例中订阅，取消后不再发 collect；首次重新启用仍可清理已有孤立资源，但不能删除停用期间保留的有效项目。
- [ ] 训练组复盘入口从扩展点读取；停用时入口消失，旧深链接走守卫；训练删除和备份恢复仍保留分析项目并解除关联。
- [ ] 运行 `flutter test test/plugins/motion_plugin_test.dart test/state/motion_analysis_controller_test.dart test/data/motion_project_repo_test.dart test/data/video_review_repo_test.dart test/widget/motion_catalog_page_test.dart test/widget/video_review_page_test.dart`。
- [ ] 审阅并提交：`refactor: register motion analysis with managed lifecycle`。

**关键失败场景：** 分析开始后取消，立即停用并重新启用，再投递上个 generation 的完成事件；数据库、当前页面和媒体句柄都不能被旧事件改变。平台 close 失败时必须显示失败，不宣称资源已释放。

### Task 8：示例接入、跨平台回归与交付文档

**Files:** 新增 `test/plugins/example_plugin.dart`、`test/plugins/plugin_composition_test.dart`、`scripts/browser_plugins_smoke.mjs`、`docs/plugins/development.md`、`docs/superpowers/plans/2026-10-21-plugin-acceptance.md`；修改 `README.md`、`CHANGELOG.md` 及受默认启用状态影响的既有浏览器脚本。

**Consumes:** Tasks 1–7 完整交付。

**Produces:** 一个不加入生产目录的示例；可重复的浏览器插件验收；SDK 文档与实际验证记录。

- [ ] 示例插件只通过 public host 写入自己的 preferences 文档，贡献一个设置入口，订阅一个数据变化事件；停止时撤销全部注册。测试目录加入它后，宿主无需按其 ID 增加 if/switch 分支。
- [ ] 验证 API 版本不兼容、依赖缺失、重复 ID 均单独报告，基础训练仍启动；使用不同插件 ID 的示例验证命名空间与能力隔离。
- [ ] 编写浏览器脚本：新库三入口、schema 11 空库升级五入口、启停后重启、深链接、活动训练保持、热量停用后备份、分析资源释放。
- [ ] 每项检查保存操作步骤、截图/语义树、数据快照及实际结果。测试不直接改用户主数据库；Android 安装仍遵循项目“主包覆盖更新”的既有约定，整库恢复验收先使用可恢复的明确测试数据。
- [ ] 执行下方最终命令序列；仅在出现新失败或再次改动时重跑受影响检查。
- [ ] 真机检查启停时相机释放、权限拒绝、切后台、重启和媒体保留；没有设备时将具体条目标记未验收，不能以构建替代。
- [ ] 文档写明内置插件仍占安装包空间、无独立下载安装能力、同进程的安全边界、视频备份限制与未来接入点。
- [ ] 审阅并提交：`docs: document plugin SDK and verified rollout`。

## 6. 检查命令与判据

从项目根目录，在 PowerShell 每个新会话先加载环境。以下为实施完成后的命令，按顺序执行，每条失败时先处理失败再继续：

```powershell
. .\scripts\env.ps1
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test --reporter expanded
flutter build web --no-pub
node scripts/browser_plugins_smoke.mjs
node scripts/browser_smoke.mjs
node scripts/browser_training_redesign_smoke.mjs
node scripts/browser_backup_smoke.mjs
node scripts/browser_calories_smoke.mjs
node scripts/browser_motion_ui_smoke.mjs
flutter build apk --release --no-pub
```

预期：格式无变化、静态检查零问题、全部测试通过、各浏览器脚本退出码为 0、两平台 release 构建成功。当前测试数可能随其他工作变化，不把某个固定数量当通过条件。涉及真实视频的 `browser_motion_smoke.mjs` 继续使用其现有测试素材配置；在实施记录中注明素材和实际结果。

| 验收维度 | 必须观察到的结果 |
|---|---|
| 新用户默认 | 三项导航，热量/分析运行时未启动，没有无操作触发的相机/网络请求 |
| 老用户升级 | 即使零条训练也保留原五项功能；迁移重复执行不覆盖之后选择 |
| 导航和训练 | 启停其他插件不重建训练控制器，不丢计时、未完成组或导航返回关系 |
| 生命周期 | 失败/重复启停没有重复订阅，任务未安全停止时不显示已停用 |
| 数据 | 停用重开前后稳定 ID、饮料快照、分析项目不变 |
| 备份 | v1–v8 规则明确、未知扩展可往返、未启用插件数据仍可备份、失败整批回滚 |
| 可扩展性 | 示例只接入目录和公共接口，无需修改宿主流程或获得 SQL 访问 |
| 平台 | Android 真机和 Web 分别有证据，未验证项明确列出 |

## 7. 后续独立安装接入点

| 后续能力 | 本期保留的接入点 | 后续仍需单独完成的工作 |
|---|---|---|
| 外部插件发现与安装 | PluginCatalog、稳定 manifest、兼容校验 | 下载目录、来源/签名、包完整性、缓存、安装事务 |
| 独立执行 | PluginRuntime、requestId、取消、错误和事件协议 | 选择并验证隔离运行时、资源限额、进程失效恢复 |
| 权限执行 | 绑定身份的 PluginHost、能力分派器 | 在跨进程边界执行授权，禁止绕过文件/网络能力 |
| 独立升级与回退 | 插件版本、API 范围、dataVersion | 包与数据升级原子协调、备份点、数据降级/回退策略 |
| 外部界面 | 描述型扩展点和独立 Flutter adapter | 声明式界面或受限 Web UI 的渲染、交互和无障碍验证 |
| 计划内容包 | 稳定实体 ID、既有计划导入事务、版本校验惯例 | 内容格式、引用校验、预览导入和社区分发 |

进入下一阶段的门槛：两个官方可选插件和示例都满足公共接口约束；启停、旧数据升级、备份回滚和跨平台资源释放已经有自动检查及必要真机证据。届时按具体运行技术另写实现计划，不把接口预留等同于已具备动态安装能力。

## 8. 计划自检与停止点

- [x] 已覆盖用户确认的“随 App 发布、自由启停、未来独立安装预留接口”。
- [x] 已覆盖新用户基础训练和老用户升级保留功能。
- [x] 已区分插件发现、执行、业务协议、Flutter UI 与存储适配。
- [x] 已定义停用/活动任务、未知数据备份、旧备份兼容和默认偏好持久化。
- [x] 已列出对应文件、依赖关系、接口、检查命令和验收判据。
- [x] 已明确视频备份、同进程隔离、原生代码迁移和安装包体积的实际边界。
- [ ] Tasks 1–8 实施：尚未开始，等待用户未来另行提出实施要求。

**本轮停止点：保存并检查这份计划后结束；不修改业务代码，不执行计划，不创建或派发实施任务。**
