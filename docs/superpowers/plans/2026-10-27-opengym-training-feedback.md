# openGym 训练续练与总结对比 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 实现主页面续练入口及训练总结中的上次同动作记录对比。

**Architecture:** 活动训练继续由 ActiveSessionController 与 SQLite 管理，导航仅观察状态；训练对比使用保留父组与动作身份的只读模型、批量历史查询和纯聚合函数。总结与历史详情共用读取和呈现组件，以 DataRevision 与加载代次防止旧请求覆盖新数据。

**Tech Stack:** Flutter 3.47.6 / Dart 3.13.5、Provider、go_router、SQLite、flutter_test、Node 真实浏览器验收。

## Global Constraints

- 沿用 Flutter、SQLite、现有状态控制器和视觉组件，以本机数据为依据。
- 单组大数字输入、正计时休息、参考重量点击采用、手动阶段和插件导航继续作为约束。
- 本轮不重新调整动作分析入口，也不引入自动改重。
- 比较用 exerciseId；前次必须已结束且 startedAt 严格早于本场；同时间前次以 session ID 降序确定。
- 已完成父组一组计一次；各实际分段容量各计一次；热身、未分类与缺失余力明确保留。
- 原始重量保留原始单位；容量使用标准 kg；容量变化只代表训练量变化。
- 只读模型与查询不增加数据库字段、迁移或备份版本。
- 不搬运 openGym 源码、动作数据或授权媒体。
- 用户已于 2026-10-27 批准设计及实施，直接按以下任务执行和复核。

## 执行方式与边界

当前环境提供 collaboration 工具；执行子技能不在可用技能目录中。采用等价的独立任务分派、父任务集成、回归与独立代码检查流程，不等待额外的执行方式选择。三个实现任务在互不重叠的文件范围并行；父任务负责环境、UI 集成、浏览器验收和提交。

## Task 1: 对比事实与批量读取

**Files:**
- Modify: `lib/domain/session_summary.dart`
- Modify: `lib/data/repositories/session_summary_loader.dart`
- Create: `lib/domain/session_comparison.dart`
- Create: `lib/data/repositories/session_comparison_repo.dart`
- Create: `test/domain/session_comparison_test.dart`
- Create: `test/data/session_comparison_repo_test.dart`
- Modify: `test/data/session_summary_loader_test.dart`

**Interfaces:**
- Consumes: `SessionSummary`, `ExerciseSummary`, `SetEntry`, `SqlExecutor` 和已有 kg 换算及容量函数。
- Produces: `ExerciseSummary.exerciseId`（必需）、`SessionExerciseRecord`、`ExerciseComparison`、`buildSessionComparisons` 和 `loadSessionComparisons`。

```dart
class SessionExerciseRecord {
  final WorkoutSession session;
  final List<ExerciseSummary> occurrences;
  const SessionExerciseRecord({required this.session, required this.occurrences});
  int get logicalSetCount => occurrences.fold(0, (n, e) => n + e.sets.length);
  double get volumeLoad => recordedSetsVolume(occurrences.expand((e) => e.sets));
}

class ExerciseComparison {
  final String exerciseId, exerciseName;
  final SessionExerciseRecord current;
  final SessionExerciseRecord? previous;
  const ExerciseComparison({required this.exerciseId, required this.exerciseName,
    required this.current, this.previous});
}
```

约定 `recordedSetsVolume(Iterable<SetEntry> sets)` 在领域层统一计算已完成父组及 continuation 的容量，原总结与对比均复用。`buildSessionComparisons(SessionSummary current, Iterable<SessionSummary> history)` 返回按本场动作首次出现顺序排列的对比；`Future<List<ExerciseComparison>> loadSessionComparisons(SqlExecutor exec, SessionSummary current)` 返回同一结果，进行中场次返回空列表。

- [ ] 编写领域测试，造出两个同动作 occurrence，断言逻辑组计数和所有原始段保留；不同动作 ID 即使同名也不能配对。
- [ ] 编写真实 SQLite 测试，使用同一动作在多个日期、同日期不同 session ID、未来及进行中记录，断言只选严格早于本场的已结束场次。
- [ ] 先运行两份新测试，确认缺少接口导致失败。
- [ ] 给只读总结模型补 exerciseId；补统一容量 helper；实现纯聚合及前次选择。按现有装载口径只保留已完成父组。
- [ ] 批量查询本场相关动作的前次 session 与其已完成组，保留 occurrence 和 set_detail；不按动作重复扫描全历史。
- [ ] 用删除／编辑／补录后的第二次查询验证结果来自当前历史，而非缓存累加计数。
- [ ] 运行 `flutter test test/domain/session_comparison_test.dart test/data/session_comparison_repo_test.dart test/data/session_summary_loader_test.dart test/data/program_record_flow_test.dart`。

领域测试的最小断言必须包含：
```dart
expect(result.single.exerciseId, 'bench');
expect(result.single.current.logicalSetCount, 2);
expect(result.single.previous!.session.id, 'previous');
expect(result.single.current.volumeLoad, 960);
```
其中两组分别为 60 kg × 8；分段场景另造一条父组和两个 continuation，并单独断言该父组仍只贡献一组。

## Task 2: 活动训练恢复与主页面入口

**Files:**
- Modify: `lib/state/active_session_controller.dart`
- Modify: `lib/app/providers.dart`
- Modify: `lib/app/app_shell.dart`
- Modify: `lib/features/workout/workout_home_page.dart`
- Modify: `lib/features/workout/record_page.dart`（仅恢复入口）
- Create: `lib/ui/widgets/active_workout_bar.dart`
- Create: `test/state/active_session_resume_test.dart`
- Create: `test/widget/active_workout_bar_test.dart`
- Modify: `test/app/router_test.dart`（如需补真实路由回归）

**Interfaces:**
- Consumes: 应用级 `ActiveSessionController`、`PluginUiRegistry.destinations` 与 `/session/:id`。
- Produces: 可重复安全调用的首次恢复接口，恢复加载／错误／重试状态；保持原 `resume()` 作为显式刷新调用以兼容现有导入恢复与测试。

- [ ] 先写控制器测试：两次并发首次恢复只执行一次实际装载；已载入时保留 currentIndex；显式刷新仍能读取外部更改。
- [ ] 写 widget 测试：无训练不占位，主页面显示名字与已完成父组计数，点击导航，窄屏和大字体不溢出。
- [ ] 应用启动统一发起首次恢复；首页和记录页改用幂等恢复，避免从历史页返回后重置用户所选动作。
- [ ] 恢复与写入相互保护；失败保留旧状态并提供重试；操作 generation 过期时不得重建已删除／结束 session。
- [ ] 在 AppShell 的明确主路径白名单显示续练条；使用 Column(mainAxisSize: min) 将它放在原 NavigationBar 上方，保留 SafeArea 和现有导航顺序。
- [ ] 验证已有训练结束、删除与备份恢复后续练条正确消失或重新出现；不在记录、计划编辑和分析任务页覆盖内容。
- [ ] 运行新增控制器／widget 测试以及 `test/app/router_test.dart test/widget/training_home_test.dart test/widget/plugin_management_test.dart test/widget/analysis_session_plugin_test.dart`。

## Task 3: 共用对比展示与刷新

**Files:**
- Create: `lib/ui/widgets/session_comparison_view.dart`
- Modify: `lib/ui/widgets/session_summary_view.dart`
- Create: `lib/state/summary_feedback_loader.dart`
- Modify: `lib/features/workout/summary_page.dart`
- Modify: `lib/features/history/session_detail_page.dart`
- Create: `test/widget/session_comparison_test.dart`
- Create: `test/widget/summary_feedback_test.dart`

**Interfaces:**
- Consumes: Task 1 的 `List<ExerciseComparison>`；Task 2 不提供本任务依赖。
- Produces: 总结与历史详情共用的对比显示，以及同时保护基本总结和对比请求的加载代次。

对比组件显式接收结果与状态，不自行做 SQL：
```dart
SessionComparisonView(
  comparisons: comparisons,
  loading: comparisonLoading,
  error: comparisonError,
  onRetry: reloadData,
)
```

- [ ] 写 widget 测试：首次记录提示、两次原始 kg/lb 读数、热身／正式／未分类、RPE/RIR 缺失、分段停顿与 occurrence 边界。
- [ ] 实现同一张对比卡中的“本次／上次日期＋原始组列表＋逻辑组数及容量变化”；不使用强弱箭头、百分比或 PR 徽章。
- [ ] 总结内容仍由 SessionSummaryView 展示，新区块位于原始总结后；两类页面传入相同结果与回调。
- [ ] 共用加载 mixin 先展示基本总结，再加载对比；新请求增加代次；过期结果和销毁后的回调不写入页面。
- [ ] 对比查询失败时保留本场总结并显示独立重试；基本总结读取失败保留旧数据并提供重试。
- [ ] 总结页与历史详情使用 DataRevisionLoader 触发刷新，修改／删除、CSV、补录及备份恢复后重算。sessionId 变化时也发起新读取。
- [ ] 用可控延迟执行器验证先发后到的旧对比结果不会盖过新记录；运行新测试及历史／总结相关原有 widget 测试。

## Task 4: 环境、集成验证与交付

**Files:**
- Modify: `scripts/env.ps1`（仅移除旧根路径）
- Create: `scripts/browser_training_feedback_smoke.mjs`
- Modify: `README.md`, `CHANGELOG.md`
- Create: `docs/superpowers/plans/2026-10-27-opengym-training-feedback-execution.md`

路径修复使用脚本自身所在位置：
```powershell
$root = Join-Path (Split-Path -Parent $PSScriptRoot) '.tooling'
```
验证时直接设置任务需要的 PUB_CACHE、Flutter PATH 和 Android/JDK 路径，不覆盖调用者 HOME。

- [ ] 读取 Flutter SDK 版本，运行 `flutter pub get --offline --enforce-lockfile` 重建迁移后仍引用旧路径的生成配置，保留 pubspec.lock。
- [ ] 对本轮涉及 Dart 文件运行格式化，执行全部 `flutter analyze` 和 `flutter test --reporter expanded`，将完整输出保存到忽略的 build/acceptance 目录。
- [ ] `flutter build web --no-pub`；借助现有隔离 Chrome profile 验收框架，运行新增真实流程：备份导入两次训练、打开历史／进步续练、保持所选动作、结束后对比、编辑原始记录后刷新、窄屏深浅主题。
- [ ] 运行原训练、插件与历史相关浏览器回归；检查截图及错误记录，不将构建当作实际流程验证。
- [ ] 在可用工具链下构建 Android release；若设备不在线，明确标记真机交互未验证。
- [ ] 更新 README／CHANGELOG 与实施记录，记录实际通过的测试、构建、浏览器场景及限制，不复制旧测试数量当成本轮结果。
- [ ] 独立复核最后 diff，确认无新依赖、迁移、备份格式变化、用户数据及 openGym 分支改动。
- [ ] 只提交本轮明确文件，保留既有 .superpowers、.tmp、.vscode 非跟踪内容，不推送或发布。

## 计划自查

- 范围：覆盖已批准设计的两项功能，后续动作筛选／周概览不在本轮任务中。
- 数据：稳定 ID、严格时间顺序、重复 occurrence、父组／分段、原单位与缺失余力均有读取及验证任务。
- 并发：活动训练恢复与页面读取均规定代次保护，真实修订后重算。
- 交付：静态检查、全套测试、实际浏览器及 Android 构建分别记录证据。
