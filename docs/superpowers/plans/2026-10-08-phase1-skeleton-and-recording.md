# Phase 1：骨架与能记一次训练 —— 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用 Flutter 写出一个能真的带去健身房用一次的力量训练记录 App —— 骨架、SQLite 持久化、聚焦当前组的记录页、完成即落盘、休息正计时、训练总结。

**Architecture:** 三层：`domain/`（纯逻辑，不依赖 Flutter，可用纯 `dart test` 跑）→ `data/`（`db/` 只放 schema 与 `SqlExecutor`，SQL 只出现在 `repositories/`）→ `state/`（编排层，唯一允许判定"能不能改这场训练"的地方）→ `features/` + `ui/`（界面，永不直接碰 `db/`）。三条分层规则由 `test/layering_test.dart` 强制。

**Tech Stack:** Flutter 3.47.6 / Dart 3.13.5、sqflite（+ `sqflite_common_ffi` 测试、`sqflite_common_ffi_web` Chrome 预览）、go_router、provider + ChangeNotifier、uuid、wakelock_plus。

**规格：** [docs/superpowers/specs/2026-10-08-flutter-gym-tracker-design.md](../specs/2026-10-08-flutter-gym-tracker-design.md)

---

## Global Constraints

以下约束适用于**每一个** Task，不再逐条重复。

**分层（由 `test/layering_test.dart` 强制，违反即测试失败）**
- `lib/features/**` 与 `lib/ui/**` 永不直接 import `lib/data/db/**`，只能 import `lib/data/repositories/**`
- SQL 字符串只允许出现在 `lib/data/repositories/**`
- 纯逻辑只允许出现在 `lib/domain/**`
- `lib/domain/**` **不得 import `package:flutter/**`** —— 它必须能用纯 `dart test` 跑

**数据不变量**
- 每完成一组**立刻**落盘，四步顺序不可反：`updateSetValues → completeSet → startRest → addSet`
- 休息时长用 `rest_started_at` **时间戳相减**，**绝不用累加器**
- `rest_seconds` 存在「本组做完之后」那段休息上
- 所有按 `started_at` / `finished_at` / `completed_at` 排序的查询**一律补 `rowid` 兜底**
- 迁移**只追加，绝不修改已发布的项**
- 建库后立刻执行 `PRAGMA foreign_keys = ON`（连接级）
- 时间一律存**毫秒时间戳**（INTEGER）；布尔一律存 0/1

**口径（界面文案必须一致，见规格附录）**
- 容量负荷 = `Σ(weight × reps)`，**只累加 `isCompleted` 的组**；界面写「**总容量（重量 × 次数）**」，**不写「个人最好」**
- e1RM = `(Epley + Brzycki + Lombardi) ÷ 3`，只在 `2 ≤ reps ≤ 10` 计算；`reps == 1` 返回实测重量；`reps > 10` 返回 `null` 且**界面必须不显示**；界面标注「**估算 · 仅供参考**」
- 休息建议必须标注「**粗略参考**」；增量固定 **15 / 30 秒**；组数 **< 3 时明确沉默**
- **次数数组必须原样显示**（「5 / 5 / 5 / 3」），只给结论不给原始数字用户不会信
- 提示**必须包含正反馈分支**

**测试纪律**
- **不写会随机变红的测试** —— 时间相关断言必须显式固定时间戳，绝不依赖"两次调用恰好落在同一毫秒"
- 逻辑不留在带 Widget 的文件里 —— 遇到就把函数移进 `domain/`
- 每个 Task 结束后 `flutter test` 必须全绿才允许提交

**异常输入统一约定**
- `SqlExecutor.first` 一行都没有时返回 `null`（不是异常）；`all` 返回 `[]`（不是 `null`）
- `SqlExecutor.run` **无参数时要能跑多语句**（迁移脚本是多条 `CREATE` 拼成的）

---

## 文件结构

| 文件 | 职责 |
|---|---|
| `lib/domain/types.dart` | 实体：`Exercise` / `WorkoutSession` / `SessionExercise` / `SetEntry` / `SetLike` |
| `lib/domain/metrics.dart` | 容量负荷、e1RM |
| `lib/domain/rest.dart` | 30 分钟闸门判定 |
| `lib/domain/rest_advice.dart` | 组间休息提示 5 分支 |
| `lib/domain/format.dart` | 日期 / 时间 / 时长格式化 |
| `lib/domain/session_label.dart` | 「深蹲 等 3 个动作 · 已记 12 组」 |
| `lib/data/db/sql_executor.dart` | `SqlExecutor` 接口 |
| `lib/data/db/sqflite_executor.dart` | 生产实现（Android 用 sqflite，Chrome 用 ffi_web） |
| `lib/data/db/ffi_executor.dart` | 测试与桌面实现（内存库） |
| `lib/data/db/schema.dart` | 建表 SQL |
| `lib/data/db/migrations.dart` | 只追加的版本化迁移 |
| `lib/data/db/database.dart` | 打开库 + 跑迁移 + 开外键 |
| `lib/data/repositories/seed.dart` | 52 个预置动作 |
| `lib/data/repositories/exercise_repo.dart` | 动作库读写 |
| `lib/data/repositories/session_repo.dart` | 训练与训练内动作 |
| `lib/data/repositories/set_repo.dart` | 组记录（落盘的核心） |
| `lib/data/repositories/settings_repo.dart` | `app_setting` 键值 + 主题模式 |
| `lib/state/active_session_controller.dart` | 编排层 |
| `lib/state/theme_controller.dart` | 主题三态 |
| `lib/ui/tokens.dart` | 颜色 / 字号 / 间距**唯一来源** |
| `lib/ui/theme.dart` | `ThemeData` 装配 |
| `lib/ui/widgets/*.dart` | 基础组件 |
| `lib/app/router.dart` | go_router 路由表 |
| `lib/app/app_shell.dart` | 四标签外壳 |
| `lib/features/workout/*.dart` | 训练首页 / 记录页 / 休息 / 总结 |
| `lib/features/settings/*.dart` | 设置页（外观） |
| `test/layering_test.dart` | 分层规则守卫 |
| `test/domain/*` `test/data/*` `test/state/*` | 分层单测 |
| `test/e2e/journey_test.dart` | 端到端回归 |

---

## 里程碑 A：环境与地基

### Task 0: 环境搭建与验证（**闸门任务**）

> **这一步不过，后面全部停下并向用户汇报。** 这台机器上 Flutter / Dart / JDK / Android SDK 四样全无，且规格 §8 列了三条已知风险（子进程 stdio 被禁、家目录不可写、下载量上限）。**不要假设旧文档的结论仍然成立，逐条实测。**

**Files:**
- Create: `C:\ccproject\restart_gymtool\.tooling\`（SDK 与重定向后的家目录，已进 `.gitignore`）
- Create: 工程骨架（`flutter create` 生成）

**Interfaces:**
- Consumes: 无
- Produces: 一个能 `flutter test` 通过、能在 Chrome 上跑起来的空工程；后续所有 Task 都建立在此之上

- [ ] **Step 1: 把家目录重定向到工作区内**

旧文档 §9 记着踩过五个位置：`.expo`、`.android`、`.gradle`、`AppData\Roaming\eas-cli-nodejs`、`_npx`，且 **`USERPROFILE` 不够，`APPDATA` / `LOCALAPPDATA` 要单独设**。Flutter 对应的是 `.pub-cache`、`.dart`、`.android`、`.gradle`。

在**每个** shell 会话开头执行（PowerShell）：

```powershell
$root = "C:\ccproject\restart_gymtool\.tooling"
New-Item -ItemType Directory -Force $root, "$root\home", "$root\appdata", "$root\localappdata" | Out-Null
$env:USERPROFILE   = "$root\home"
$env:HOME          = "$root\home"
$env:APPDATA       = "$root\appdata"
$env:LOCALAPPDATA  = "$root\localappdata"
$env:PUB_CACHE     = "$root\pub-cache"
$env:GRADLE_USER_HOME = "$root\gradle"
$env:ANDROID_SDK_ROOT = "$root\android-sdk"
$env:ANDROID_HOME     = "$root\android-sdk"
```

把这串存成 `scripts\env.ps1`，后续每个 Task 开始前 dot-source 它：

```powershell
. C:\ccproject\restart_gymtool\scripts\env.ps1
```

- [ ] **Step 2: 下载并解压 Flutter 3.47.6**

```powershell
$root = "C:\ccproject\restart_gymtool\.tooling"
$url = "https://storage.googleapis.com/flutter_infra_release/releases/stable/windows/flutter_windows_3.47.6-stable.zip"
$zip = "$root\flutter.zip"
curl.exe -L --retry 5 --retry-delay 5 -C - -o $zip $url
Expand-Archive -Path $zip -DestinationPath $root -Force
```

**验证**：`& "$root\flutter\bin\flutter.bat" --version` 应输出 `Flutter 3.47.6 • channel stable • Dart 3.13.5`。

> 若下载中断：`curl -C -` 支持断点续传，重跑同一条命令即可。国内网络慢的话可换 `https://storage.flutter-io.cn/flutter_infra_release/releases/stable/windows/flutter_windows_3.47.6-stable.zip`（已实测可达）。

- [ ] **Step 3: 装 JDK 17+**

Flutter 的 Android 构建需要 JDK。用 Temurin 17（免安装解压版，不写注册表）：

```powershell
$root = "C:\ccproject\restart_gymtool\.tooling"
$jdkUrl = "https://api.adoptium.net/v3/binary/latest/17/ga/windows/x64/jdk/hotspot/normal/eclipse"
$jdkZip = "$root\jdk.zip"
curl.exe -L --retry 5 -C - -o $jdkZip $jdkUrl
Expand-Archive -Path $jdkZip -DestinationPath "$root\jdk" -Force
$env:JAVA_HOME = (Get-ChildItem "$root\jdk" -Directory | Select-Object -First 1).FullName
```

**验证**：`& "$env:JAVA_HOME\bin\java.exe" -version` 应输出 `openjdk version "17..."`。

- [ ] **Step 4: 装 Android SDK（只装 cmdline-tools + 必要组件，不装 Android Studio）**

```powershell
$root = "C:\ccproject\restart_gymtool\.tooling"
$sdk = "$root\android-sdk"
New-Item -ItemType Directory -Force "$sdk\cmdline-tools" | Out-Null
$cmdUrl = "https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip"
curl.exe -L --retry 5 -C - -o "$root\cmdline-tools.zip" $cmdUrl
Expand-Archive -Path "$root\cmdline-tools.zip" -DestinationPath "$root\ct" -Force
Move-Item "$root\ct\cmdline-tools" "$sdk\cmdline-tools\latest" -Force
```

然后接受许可并安装组件：

```powershell
$sdkmanager = "$sdk\cmdline-tools\latest\bin\sdkmanager.bat"
& $sdkmanager --sdk_root=$sdk --licenses        # 一路输入 y
& $sdkmanager --sdk_root=$sdk "platform-tools" "platforms;android-35" "build-tools;35.0.0"
```

**验证**：`& "$sdk\platform-tools\adb.exe" version` 应输出版本号。

- [ ] **Step 5: `flutter doctor` 并记录结果**

```powershell
. C:\ccproject\restart_gymtool\scripts\env.ps1
flutter config --android-sdk $env:ANDROID_SDK_ROOT
flutter doctor -v
```

**期望**：`Flutter` ✅、`Android toolchain` ✅、`Chrome` ✅。**若 Android toolchain 报错，先把错误原文记下来**——这是本次唯一可能卡住的环节。

- [ ] **Step 6: 创建工程并接入依赖**

在 `C:\ccproject\restart_gymtool` 下（**不是**新建子目录）：

```powershell
flutter create --org com.mobis --project-name gym_tracker --platforms android,web .
flutter pub add sqflite sqflite_common_ffi sqflite_common_ffi_web go_router provider uuid wakelock_plus
```

> **不要手写版本号** —— 用 `flutter pub add` 让 pub 解析当前兼容版本，写死版本号会踩到解析冲突。
>
> ⚠️ **不要加 `flutter pub add dev:sqflite_common_ffi`（本计划初版有这一行，已删除）。**
> 它**必然失败**（实测退出码 65）：
> ```
> "sqflite_common_ffi" is already in "dependencies". Use "pub remove sqflite_common_ffi"
> to remove it before adding it to "dev_dependencies"
> ```
> 而且**不应该**用 `pub remove` 去"补救"：Task 5 的 `lib/data/db/ffi_executor.dart` 位于
> `lib/` 下，**这是运行时依赖，本来就必须留在 `dependencies`**。

- [ ] **Step 7: 生成 Chrome 预览所需的 sqlite3.wasm**

```powershell
dart run sqflite_common_ffi_web:setup
```

**验证**：`web/` 下应出现 `sqlite3.wasm` 与 `sqflite_sw.js` 两个文件。

- [ ] **Step 8: 写一个双后端冒烟测试，证明 SQLite 真的能用**

`test/smoke/database_smoke_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
  });

  test('内存库能建表、能写、能读回', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('CREATE TABLE t (id TEXT PRIMARY KEY, n INTEGER NOT NULL)');
    await db.insert('t', {'id': 'a', 'n': 42});
    final rows = await db.query('t');
    expect(rows, hasLength(1));
    expect(rows.first['n'], 42);
    await db.close();
  });

  test('PRAGMA foreign_keys 能打开，级联删除生效', () async {
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('PRAGMA foreign_keys = ON');
    await db.execute('CREATE TABLE parent (id TEXT PRIMARY KEY)');
    await db.execute(
      'CREATE TABLE child (id TEXT PRIMARY KEY, p TEXT NOT NULL REFERENCES parent(id) ON DELETE CASCADE)',
    );
    await db.insert('parent', {'id': 'p1'});
    await db.insert('child', {'id': 'c1', 'p': 'p1'});
    await db.delete('parent', where: 'id = ?', whereArgs: ['p1']);
    expect(await db.query('child'), isEmpty);
    await db.close();
  });
}
```

- [ ] **Step 9: 跑测试，确认通过**

Run: `flutter test test/smoke/database_smoke_test.dart -v`
Expected: `All tests passed!`（2 个测试）

> **若报 `spawn EPERM` 或进程相关错误**：旧文档 §6.2 记着"沙箱禁止子进程管道 stdio，worker 池会 spawn EPERM"，解法是 `--concurrency=1`。试 `flutter test --concurrency=1`，并把结论写进 `docs/superpowers/plans/dev-environment-notes.md`。

- [ ] **Step 10: 在 Chrome 上跑起来，确认预览通道可用**

```powershell
flutter run -d chrome
```

**期望**：Chrome 打开，显示 Flutter 默认计数器页面。按 `q` 退出。

- [ ] **Step 11: 提交**

```bash
git add -A
git commit -m "chore: Flutter 工程骨架与三后端依赖，环境验证通过"
```

- [ ] **Step 12: 把环境结论写进笔记**

创建 `docs/superpowers/plans/dev-environment-notes.md`，记录：实际用的版本号、`flutter doctor` 的原文输出、三条已知风险是否仍然成立、以及任何偏离本计划的地方。**这份笔记是后续所有 Task 的排障依据。**

---

#### Task 0 实施结果（2026-10-08，已由主 agent 独立复验）

**闸门通过，无一步失败。** 实测版本：Flutter **3.47.6** / Dart **3.13.5** / Temurin JDK **17.0.20.1** / Android SDK **36**（build-tools 36.0.0）。

| 计划里的已知风险 | 实测结论 |
|---|---|
| 子进程 stdio 被禁 → 需 `--concurrency=1` | **不成立**，默认并发即可 |
| 沙箱外家目录不可写 | **不成立**，家目录读写正常 |
| 网络下载量上限 | **不成立**，单会话拉约 3.5 GB 无拦截 |

**但这三条不成立不代表环境没坑 —— 实测暴露了两条计划没预见的：**

1. **`curl.exe` 的 schannel 吊销检查失败**（最坑）。对 `api.adoptium.net`（JDK）与 `github.com`（sqlite3.wasm）报
   `CRYPT_E_NO_REVOCATION_CHECK (0x80092012) - 吊销功能无法检查证书是否吊销`。
   **解法：加 `--ssl-no-revoke`。**
   关键结论：**这只是 curl.exe（Windows TLS 后端）的问题，不是网络封禁** —— Dart 用自己的 TLS 栈完全不受影响，`flutter pub add` 与 `sqflite_common_ffi_web:setup` 都一次成功。只有自己写 curl 脚本时才需要处理。
2. **VS Code 的 Dart 扩展绕过了 `PUB_CACHE` 重定向**，把 209 个包写进了**真实家目录**的 `AppData\Local\Pub\Cache`。目前无害（两个缓存都完整），但谁要严格保证"一切都在工程内"，得关掉该扩展或在 VS Code 设置里也注入 `PUB_CACHE`。

**两条重跑即可的偶发**（不要误判为环境损坏）：

- `dart pub global activate webdev` 首次卡 17 分钟后超时 —— pub 的 version solving 要拉约 200 个包元数据，**以分钟计**，任一连接超时即整次失败。原样重跑即成功；**超过 10 分钟不要判失败，先看 `PUB_CACHE` 有没有在长**。
- `flutter run -d chrome` 首次永久卡在 `Waiting for connection from debug service` —— 判定为首次 web 编译耗时导致的竞态，**重跑即好**。

**另有两处对计划本身的偏离**（细节见 `dev-environment-notes.md`）：

- 用 `tar.exe` 代替 `Expand-Archive`（Flutter 解压后约 3 万文件，PS 5.1 的 `Expand-Archive` 慢到不可用）
- Android platform 装 **36** 而不只是计划写的 35（Flutter 3.47.6 要求 36）

---

### Task 1: `domain/types.dart` + `domain/metrics.dart` + `domain/rest.dart`

**Files:**
- Create: `lib/domain/types.dart`
- Create: `lib/domain/metrics.dart`
- Create: `lib/domain/rest.dart`
- Test: `test/domain/metrics_test.dart`
- Test: `test/domain/rest_test.dart`

**Interfaces:**
- Consumes: 无（第一层）
- Produces:
  - `class SetLike { double weight; int reps; bool isCompleted; }`
  - `class SetEntry { String id; String sessionExerciseId; int position; double weight; int reps; bool isCompleted; int? restSeconds; int? restStartedAt; int? completedAt; }`
  - `class Exercise { String id; String name; String? muscleGroup; String? equipment; bool isCustom; bool isArchived; int createdAt; }`
  - `class WorkoutSession { String id; String? name; int startedAt; int? finishedAt; String? note; String? templateId; }`
  - `class SessionExercise { String id; String sessionId; String exerciseId; int position; String? note; }`
  - `double totalVolumeLoad(List<SetLike> sets)`
  - `double? estimateOneRepMax(double weight, int reps)`
  - `const int staleRestThresholdMs`
  - `bool isStaleRest(int? restStartedAt, int now)`
  - `SetEntry? findStaleRest(List<SetEntry> sets, int now)`

- [ ] **Step 1: 写失败的测试 —— 容量负荷与 e1RM**

`test/domain/metrics_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/domain/metrics.dart';
import 'package:gym_tracker/domain/types.dart';

SetLike s(double w, int r, {bool done = true}) =>
    SetLike(weight: w, reps: r, isCompleted: done);

void main() {
  group('totalVolumeLoad', () {
    test('累加 重量 × 次数', () {
      expect(totalVolumeLoad([s(20, 8), s(20, 8)]), 320);
    });

    test('未完成的组不计入', () {
      expect(totalVolumeLoad([s(20, 8), s(100, 10, done: false)]), 160);
    });

    test('空数组返回 0', () {
      expect(totalVolumeLoad([]), 0);
    });
  });

  group('estimateOneRepMax', () {
    test('reps 为 1 时直接返回实测重量', () {
      expect(estimateOneRepMax(100, 1), 100);
    });

    test('reps 为 0 或负数时返回 null', () {
      expect(estimateOneRepMax(100, 0), isNull);
      expect(estimateOneRepMax(100, -1), isNull);
    });

    test('reps 大于 10 时返回 null（外推失真，界面必须不显示）', () {
      expect(estimateOneRepMax(60, 11), isNull);
      expect(estimateOneRepMax(60, 20), isNull);
    });

    test('50kg × 8 次 → 62.32（三公式平均，锁住口径）', () {
      // Epley 63.33 / Brzycki 62.07 / Lombardi 61.56 → 平均 62.32
      expect(estimateOneRepMax(50, 8), closeTo(62.32, 0.01));
    });

    test('52.5kg × 8 次 → 65.43（锁住第二条真实数据）', () {
      expect(estimateOneRepMax(52.5, 8), closeTo(65.43, 0.01));
    });

    test('60×10 的 e1RM 高于 70×3 —— 「最佳 e1RM」不一定来自最重的那组', () {
      expect(estimateOneRepMax(60, 10)!,
          greaterThan(estimateOneRepMax(70, 3)!));
    });
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/domain/metrics_test.dart`
Expected: FAIL —— `Target of URI doesn't exist` / `totalVolumeLoad isn't defined`

- [ ] **Step 3: 写 `lib/domain/types.dart`**

```dart
/// 动作库里的一个动作。
///
/// 预置动作与用户自建动作共用这一张表，只有 [isCustom] 区分 —— 备份导出时
/// 两者都要带上，换设备后自建动作才不会丢。
class Exercise {
  final String id;
  final String name;

  /// 肌群（胸/背/腿/肩/手臂/核心）；不在这个枚举里的排到最后
  final String? muscleGroup;
  final String? equipment;

  /// true = 用户自建；false = 预置
  final bool isCustom;

  /// 归档的动作不在动作列表里出现，但历史记录仍引用得到它
  final bool isArchived;
  final int createdAt;

  const Exercise({
    required this.id,
    required this.name,
    this.muscleGroup,
    this.equipment,
    required this.isCustom,
    required this.isArchived,
    required this.createdAt,
  });
}

/// 一次训练。[finishedAt] 为 null 即「正在进行中」。
class WorkoutSession {
  final String id;
  final String? name;
  final int startedAt;

  /// 结束时间；null 表示这场还没结束
  final int? finishedAt;
  final String? note;

  /// 这一场是按哪套计划练的；null = 没按计划。
  ///
  /// 「今天该练哪一套」就是从这个字段推出来的：取最近一场已结束、且它非空的
  /// 训练，在计划列表里往后数一套。**刻意不另存一个「下一个该练第几套」的字段**
  /// —— 那就要在跳过、删计划、导入记录、恢复备份四条路径上同步维护它，
  /// 一旦不符，表现是「轮转莫名跳了一套」。
  final String? templateId;

  const WorkoutSession({
    required this.id,
    this.name,
    required this.startedAt,
    this.finishedAt,
    this.note,
    this.templateId,
  });

  WorkoutSession copyWith({int? finishedAt}) => WorkoutSession(
        id: id,
        name: name,
        startedAt: startedAt,
        finishedAt: finishedAt ?? this.finishedAt,
        note: note,
        templateId: templateId,
      );
}

/// 一次训练里的一个动作（练了什么 + 排第几）。
/// **组挂在它下面**，不是挂在动作上。
class SessionExercise {
  final String id;

  /// 属于哪一场训练。注意组记录引用的是本表的 id，不是 [exerciseId]
  final String sessionId;

  /// 指向动作库里的动作
  final String exerciseId;

  /// 在这一场里的顺序，从 0 开始；界面按它排列
  final int position;
  final String? note;

  const SessionExercise({
    required this.id,
    required this.sessionId,
    required this.exerciseId,
    required this.position,
    this.note,
  });
}

/// 一组记录。**记录的原子单位**：完成即落盘的那一条就是它。
///
/// 记录界面会为「下一组」预先建一条 `isCompleted: false` 的占位 —— 界面靠
/// 找这条占位来确定当前该记哪一组，所以它必须存在。
class SetEntry {
  final String id;

  /// 指向 [SessionExercise.id]（**不是** `exerciseId`）——
  /// 两者都是字符串 id，写错了编译器不报错，但会一组都读不出来
  final String sessionExerciseId;

  /// 在这个动作里的第几组，从 0 开始
  final int position;

  /// 重量（kg）
  final double weight;
  final int reps;
  final bool isCompleted;

  /// 本组做完后休息了多久（秒）。null 表示还没结束那次休息，或这是最后一组
  final int? restSeconds;

  /// 休息开始的时间戳。非 null 表示正在休息中
  final int? restStartedAt;
  final int? completedAt;

  const SetEntry({
    required this.id,
    required this.sessionExerciseId,
    required this.position,
    required this.weight,
    required this.reps,
    required this.isCompleted,
    this.restSeconds,
    this.restStartedAt,
    this.completedAt,
  });
}

/// 算容量负荷 / 1RM 所需的**最小**组形状。
///
/// 单独定义是为了让 [metrics] 不依赖完整的 [SetEntry] —— 折算曲线时手里
/// 只有「重量 + 次数」几个数，不必为了算容量伪造一个完整记录。
class SetLike {
  /// 重量（kg）
  final double weight;
  final int reps;

  /// 未完成的组不计入容量负荷
  final bool isCompleted;

  const SetLike({
    required this.weight,
    required this.reps,
    required this.isCompleted,
  });
}
```

- [ ] **Step 4: 写 `lib/domain/metrics.dart`**

```dart
import 'dart:math' as math;

import 'types.dart';

/// 容量负荷（volume load）= Σ(重量 × 次数)，**只累加已完成的组**。
///
/// 注意：文献中 "volume" 一词口径不统一（有的指总次数，有的指组数×次数）。
/// 本 App 一律采用含重量的 volume load 口径，命名上也必须叫 volumeLoad
/// 而不是 volume。
double totalVolumeLoad(List<SetLike> sets) {
  var sum = 0.0;
  for (final s in sets) {
    if (s.isCompleted) sum += s.weight * s.reps;
  }
  return sum;
}

/// 估算 1RM（e1RM）。
///
/// 采用三种经典公式的算术平均，以降低单一公式的偏差 —— 同一组数据这三个
/// 公式会给出不同结果，没有任何一个被公认最准。
///
/// 适用范围：仅当 `2 <= reps <= 10` 时有效。次数 > 10 时外推严重失真，
/// 返回 null，**调用方必须不显示该值**。`reps == 1` 时直接返回实测重量。
///
/// **公式一旦确定不得更改** —— 换了公式，进步页的历史曲线会出现无解释的
/// 断层。因此公式只有这一份实现，别处一律调用它，不重写。
///
/// 返回 null 时**不能当 0 处理** —— 0 会被读成「练得很差」，
/// 而事实是「这一组不适合换算」。
double? estimateOneRepMax(double weight, int reps) {
  if (reps < 1) return null;
  if (reps == 1) return weight;
  if (reps > 10) return null;

  final epley = weight * (1 + reps / 30);
  final brzycki = (weight * 36) / (37 - reps);
  final lombardi = weight * math.pow(reps, 0.1);

  return (epley + brzycki + lombardi) / 3;
}
```

- [ ] **Step 5: 跑测试确认通过**

Run: `flutter test test/domain/metrics_test.dart -v`
Expected: `All tests passed!`（**9** 个测试 —— 计划初版写 8，实际 Step 1 的代码块里有 9 个 `test()`：3 条 totalVolumeLoad + 6 条 estimateOneRepMax）

- [ ] **Step 6: 写失败的测试 —— 30 分钟闸门**

`test/domain/rest_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/domain/rest.dart';
import 'package:gym_tracker/domain/types.dart';

const t0 = 1700000000000;

SetEntry set({
  required String id,
  bool done = true,
  int? restStartedAt,
}) =>
    SetEntry(
      id: id,
      sessionExerciseId: 'se1',
      position: 0,
      weight: 20,
      reps: 8,
      isCompleted: done,
      restStartedAt: restStartedAt,
    );

void main() {
  group('isStaleRest', () {
    test('没在休息时永远不 stale', () {
      expect(isStaleRest(null, t0 + 99999999), isFalse);
    });

    test('刚好 30 分钟不算过头（阈值是「超过」而非「达到」）', () {
      expect(isStaleRest(t0, t0 + staleRestThresholdMs), isFalse);
    });

    test('超过 30 分钟算过头', () {
      expect(isStaleRest(t0, t0 + staleRestThresholdMs + 1), isTrue);
    });

    test('29 分钟的正常长休息不能被误伤', () {
      expect(isStaleRest(t0, t0 + 29 * 60 * 1000), isFalse);
    });
  });

  group('findStaleRest', () {
    test('没有正在休息的组时返回 null', () {
      expect(findStaleRest([set(id: 'a')], t0), isNull);
    });

    test('找到那段跑过头的休息', () {
      final sets = [
        set(id: 'a', restStartedAt: t0),
        set(id: 'b', restStartedAt: t0 + 31 * 60 * 1000),
      ];
      // t0 那一组已经超过 30 分钟；t0+31min 那一组才刚开始
      expect(findStaleRest(sets, t0 + 31 * 60 * 1000)?.id, 'a');
    });

    test('未完成的组即使带着时间戳也不认（它不该在休息）', () {
      final sets = [set(id: 'a', done: false, restStartedAt: t0)];
      expect(findStaleRest(sets, t0 + 40 * 60 * 1000), isNull);
    });
  });
}
```

- [ ] **Step 7: 跑测试确认失败**

Run: `flutter test test/domain/rest_test.dart`
Expected: FAIL —— `rest.dart` 不存在

- [ ] **Step 8: 写 `lib/domain/rest.dart`**

```dart
import 'types.dart';

/// 超过这个时长的休息，认定为「忘了按开始下一组」，而不是真实休息。
///
/// 30 分钟是刻意宽松的阈值：力量训练的组间休息极少超过 10 分钟，留三倍余量
/// 是为了绝不误伤一次真实的长时间休息（比如中途接了个电话）。它要挡掉的是
/// 另一种情况 —— 做完一组直接关掉 App 走了，第二天打开看到
/// 「组间休息 14:23:00」。
const int staleRestThresholdMs = 30 * 60 * 1000;

/// 这段休息是否已经跑过头。[restStartedAt] 为 null 表示当前没在休息。
bool isStaleRest(int? restStartedAt, int now) {
  if (restStartedAt == null) return false;
  return now - restStartedAt > staleRestThresholdMs;
}

/// 从一组记录里找出那段已经跑过头的休息。
///
/// 返回 null 表示：没有正在进行的休息，或正在进行的这段还算新鲜 ——
/// 两种情况调用方都应该什么都不做。
SetEntry? findStaleRest(List<SetEntry> sets, int now) {
  for (final s in sets) {
    if (s.isCompleted && isStaleRest(s.restStartedAt, now)) return s;
  }
  return null;
}
```

- [ ] **Step 9: 跑测试确认通过**

Run: `flutter test test/domain/`
Expected: `All tests passed!`（metrics 9 + rest 7 = **16** 个测试）

- [ ] **Step 10: 提交**

```bash
git add lib/domain test/domain
git commit -m "feat(domain): 实体类型、容量负荷与 e1RM 口径、30 分钟休息闸门"
```

---

### Task 2: `domain/rest_advice.dart` —— 组间休息提示 5 分支

**Files:**
- Create: `lib/domain/rest_advice.dart`
- Test: `test/domain/rest_advice_test.dart`

**Interfaces:**
- Consumes: 无
- Produces:
  - `enum RestFeedbackKind { positive, addWeight, extend15, extend30, extend30CheckWeight }`
  - `class RestFeedback { RestFeedbackKind kind; List<int> reps; int drop; double? avgRest; String message; }`
  - `RestFeedback? buildRestFeedback(List<int> reps, List<int?> rests)`

- [ ] **Step 1: 写失败的测试**

`test/domain/rest_advice_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/domain/rest_advice.dart';

void main() {
  test('组数少于 3 时明确沉默，不给任何提示', () {
    expect(buildRestFeedback([8, 8], [90, null]), isNull);
    expect(buildRestFeedback([], []), isNull);
    expect(buildRestFeedback([8], [null]), isNull);
  });

  test('全程稳定且休息不长 → 正反馈', () {
    final f = buildRestFeedback([5, 5, 5, 5], [90, 90, 90, null])!;
    expect(f.kind, RestFeedbackKind.positive);
    expect(f.drop, 0);
    expect(f.message, contains('5 / 5 / 5 / 5'));
    expect(f.message, contains('节奏合适'));
  });

  test('全程稳定但平均休息 > 180 秒 → 加重提示（不是缩短休息）', () {
    final f = buildRestFeedback([5, 5, 5], [200, 200, null])!;
    expect(f.kind, RestFeedbackKind.addWeight);
    expect(f.message, contains('还有余力，可以考虑加重量'));
    expect(f.message, contains('3 分 20 秒'));
  });

  test('平均休息刚好 180 秒不算长（边界是不含）', () {
    final f = buildRestFeedback([6, 6, 6], [180, 180, null])!;
    expect(f.kind, RestFeedbackKind.positive);
  });

  test('末组掉 1 次 → 多歇 15 秒', () {
    final f = buildRestFeedback([5, 5, 4], [90, 90, null])!;
    expect(f.kind, RestFeedbackKind.extend15);
    expect(f.message, contains('末组 5 → 4'));
    expect(f.message, contains('15 秒'));
  });

  test('末组掉 2 次 → 多歇 30 秒', () {
    final f = buildRestFeedback([5, 5, 3], [90, 90, null])!;
    expect(f.kind, RestFeedbackKind.extend30);
    expect(f.message, contains('30 秒'));
  });

  test('末组掉 3 次以上 → 多歇 30 秒 + 归因提示', () {
    final f = buildRestFeedback([5, 5, 2], [90, 90, null])!;
    expect(f.kind, RestFeedbackKind.extend30CheckWeight);
    expect(f.message, contains('可能是重量偏大'));
  });

  test('次数递增（drop < 0）按 drop <= 0 处理，也是正反馈', () {
    final f = buildRestFeedback([5, 6, 7], [90, 90, null])!;
    expect(f.kind, RestFeedbackKind.positive);
    expect(f.drop, -2);
  });

  test('一条休息数据都没有时 avgRest 为 null，不能当成 0', () {
    final f = buildRestFeedback([5, 5, 5], [null, null, null])!;
    expect(f.avgRest, isNull);
    // 若把 null 当成 0，会走进「歇得很短」从而误判 —— 这里必须是正反馈
    expect(f.kind, RestFeedbackKind.positive);
  });

  test('次数数组原样返回，供界面核对', () {
    final f = buildRestFeedback([12, 10, 9], [60, 60, null])!;
    expect(f.reps, [12, 10, 9]);
    // ⚠️ 计划初版这里断言的是 `contains('12 / 10 / 9')`，**那是错的**：
    // [12,10,9] 的 drop = 3，走 extend30CheckWeight 分支，而该分支的文案按
    // 规格 §4.3 是「末组 {first} → {last}…」，**不含整串次数数组**。
    // 「次数数组必须原样显示」这条约束是由总结页的卡片首行单独渲染满足的
    // （见 Task 18 的 summary_page.dart），不是由 message 满足的。
    expect(f.message, contains('末组 12 → 9'));
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/domain/rest_advice_test.dart`
Expected: FAIL —— `rest_advice.dart` 不存在

- [ ] **Step 3: 写 `lib/domain/rest_advice.dart`**

```dart
/// 建议的类型标签。界面若要按类型上色 / 配图标，认这个字段，
/// **不要去解析 [RestFeedback.message]** —— 文案改了类型还在，
/// 解析文案的代码会静默失效。
enum RestFeedbackKind {
  /// 次数没掉、休息也不长：保持现状
  positive,

  /// 次数没掉但休息偏长：还有余力
  addWeight,

  /// 末组只掉 1 次：多歇 15 秒
  extend15,

  /// 末组掉 2 次：多歇 30 秒
  extend30,

  /// 末组掉 3 次以上：多歇 30 秒，若还掉就说明重量偏大
  extend30CheckWeight,
}

/// 训练后给的一条组间休息建议，附带界面展示所需的全部原始数据。
class RestFeedback {
  final RestFeedbackKind kind;

  /// 原始次数数组。**界面必须原样展示**，让用户能自己核对 ——
  /// 只给结论不给原始数字，用户不会相信
  final List<int> reps;

  /// 首组次数 − 末组次数
  final int drop;

  /// 平均组后休息秒数；没有休息数据时为 null
  final double? avgRest;

  /// 已经拼好的人话，界面直接显示
  final String message;

  const RestFeedback({
    required this.kind,
    required this.reps,
    required this.drop,
    required this.avgRest,
    required this.message,
  });
}

/// 平均休息超过这个秒数，且次数没掉，就认为「还有余力」。
const int _longRestThresholdSeconds = 180;

/// 少于这个组数就不作判断。
const int _minSets = 3;

/// 各组的组后休息秒数，最后一组通常是 null（它是最后一组，没有「组后休息」）。
///
/// 一条数据都没有时返回 **null 而不是 0** —— 0 会被后面判成「歇得很短」，
/// 从而给出错误的「加重量」建议。
double? _averageRest(List<int?> rests) {
  var sum = 0;
  var n = 0;
  for (final r in rests) {
    if (r != null) {
      sum += r;
      n++;
    }
  }
  return n == 0 ? null : sum / n;
}

/// 生成训练后的组间休息提示。
///
/// 这是**粗略参考**，不是科学结论：只比较本次训练内首组与末组的次数差异，
/// 不跨训练推断、不建统计模型。该领域文献本身对最优休息时长没有共识，
/// 且同一个人不同训练日的反应差异明显。
///
/// **必须包含正反馈分支** —— 只挑毛病、从不肯定，用两周就会被无视。
///
/// 组数少于 3 时返回 null：数据不足时明确沉默，不硬给建议。
RestFeedback? buildRestFeedback(List<int> reps, List<int?> rests) {
  if (reps.length < _minSets) return null;

  final first = reps.first;
  final last = reps.last;
  final drop = first - last;
  final avgRest = _averageRest(rests);
  final list = reps.join(' / ');
  final restText = avgRest == null ? null : avgRest.round();

  if (drop <= 0) {
    if (restText != null && restText > _longRestThresholdSeconds) {
      final minutes = restText ~/ 60;
      final seconds = restText % 60;
      return RestFeedback(
        kind: RestFeedbackKind.addWeight,
        reps: reps,
        drop: drop,
        avgRest: avgRest,
        message: '$list 全程稳定，平均歇了 $minutes 分 $seconds 秒 —— 还有余力，可以考虑加重量',
      );
    }
    return RestFeedback(
      kind: RestFeedbackKind.positive,
      reps: reps,
      drop: drop,
      avgRest: avgRest,
      message: '$list 全程稳住了，节奏合适',
    );
  }

  if (drop == 1) {
    return RestFeedback(
      kind: RestFeedbackKind.extend15,
      reps: reps,
      drop: drop,
      avgRest: avgRest,
      message: '末组 $first → $last，下次这个动作可以多歇 15 秒',
    );
  }

  if (drop == 2) {
    return RestFeedback(
      kind: RestFeedbackKind.extend30,
      reps: reps,
      drop: drop,
      avgRest: avgRest,
      message: '末组 $first → $last，下次可以多歇 30 秒',
    );
  }

  return RestFeedback(
    kind: RestFeedbackKind.extend30CheckWeight,
    reps: reps,
    drop: drop,
    avgRest: avgRest,
    message: '末组 $first → $last，多歇 30 秒试试；如果还是掉，可能是重量偏大',
  );
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/domain/rest_advice_test.dart -v`
Expected: `All tests passed!`（10 个测试）

- [ ] **Step 5: 提交**

```bash
git add lib/domain/rest_advice.dart test/domain/rest_advice_test.dart
git commit -m "feat(domain): 组间休息提示 5 分支，含强制正反馈与粗略参考口径"
```

---

### Task 3: `domain/format.dart` + `domain/session_label.dart`

**Files:**
- Create: `lib/domain/format.dart`
- Create: `lib/domain/session_label.dart`
- Test: `test/domain/format_test.dart`
- Test: `test/domain/session_label_test.dart`

**Interfaces:**
- Consumes: 无
- Produces:
  - `String formatDate(int timestamp)` → `9月16日 周三`
  - `String formatTime(int timestamp)` → `09:05`
  - `String formatDateTime(int timestamp, [int? now])` → `今天 15:20` / `昨天 19:30` / `9月16日 19:30`
  - `String formatDuration(int seconds)` → `1 分 05 秒` / `12:34`
  - `String describeExercises(List<ExerciseProgress> exercises)` → `深蹲 等 3 个动作 · 已记 12 组`
  - `class ExerciseProgress { String exerciseName; List<SetProgress> sets; }`
  - `class SetProgress { bool isCompleted; }`

- [ ] **Step 1: 写失败的测试 —— 日期与时长格式化**

`test/domain/format_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/domain/format.dart';

void main() {
  // 全部用**显式固定**的时间戳构造，不依赖真实时钟 ——
  // 旧项目有一条赌时钟的测试实测 20 次闪 2 次，那种测试比没有更危险。
  final wed = DateTime(2024, 9, 16, 19, 30).millisecondsSinceEpoch;

  test('formatDate 用本地时区，月和日不补零', () {
    expect(formatDate(wed), '9月16日 周一');
  });

  test('formatTime 必须补零，否则 9 点 5 分会写成 9:5', () {
    final t = DateTime(2024, 1, 5, 9, 5).millisecondsSinceEpoch;
    expect(formatTime(t), '09:05');
  });

  test('formatDateTime —— 同一天说「今天」', () {
    final now = DateTime(2024, 9, 16, 21, 0).millisecondsSinceEpoch;
    expect(formatDateTime(wed, now), '今天 19:30');
  });

  test('formatDateTime —— 差一天说「昨天」', () {
    final now = DateTime(2024, 9, 17, 8, 0).millisecondsSinceEpoch;
    expect(formatDateTime(wed, now), '昨天 19:30');
  });

  test('formatDateTime —— 更早用日期，不带星期', () {
    final now = DateTime(2024, 9, 20, 8, 0).millisecondsSinceEpoch;
    expect(formatDateTime(wed, now), '9月16日 19:30');
  });

  test('跨天按日历天算，不按 24 小时 —— 23:50 练完、次日 00:10 打开说「昨天」', () {
    final before = DateTime(2024, 9, 16, 23, 50).millisecondsSinceEpoch;
    final after = DateTime(2024, 9, 17, 0, 10).millisecondsSinceEpoch;
    expect(formatDateTime(before, after), '昨天 23:50');
  });

  test('formatDuration —— 不足 1 分钟只说秒', () {
    expect(formatDuration(45), '45 秒');
  });

  test('formatDuration —— 分秒都要，秒补零', () {
    expect(formatDuration(65), '1 分 05 秒');
  });

  test('formatDuration —— 超过 1 小时带小时', () {
    expect(formatDuration(3725), '1 小时 2 分');
  });

  // formatClock 是休息界面那个一直在跳的钟面。计划初版漏了它的测试，
  // 但计划自己的注里写明它「是纯函数且必须可单测（00:00 与进位是边界）」。

  test('formatClock —— 零点显示 00:00，不能是 0:0', () {
    expect(formatClock(0), '00:00');
  });

  test('formatClock —— 分秒都补零', () {
    expect(formatClock(65), '01:05');
    expect(formatClock(59), '00:59');
  });

  test('formatClock —— 超过一小时不进位到小时，分继续累加（钟面不换行）', () {
    expect(formatClock(3920), '65:20');
  });

  test('formatClock —— 负数夹到 00:00（时钟回拨等异常不该显示负数）', () {
    expect(formatClock(-5), '00:00');
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/domain/format_test.dart`
Expected: FAIL —— `format.dart` 不存在

- [ ] **Step 3: 写 `lib/domain/format.dart`**

```dart
/// 下标即 `DateTime.weekday` 的返回值：1 = 周一 …… 7 = 周日。
const List<String> _weekdayLabels = ['', '周一', '周二', '周三', '周四', '周五', '周六', '周日'];

/// `9月16日 周三`。
///
/// 全程用本地时区的 getter，不用 `intl` 的 locale 格式化 —— 同一份代码在不同
/// 地区设置下会排出不同格式，是那种只在别人机器上复现的 bug。
/// 月和日**不补零**（中文习惯）。
String formatDate(int timestamp) {
  final d = DateTime.fromMillisecondsSinceEpoch(timestamp);
  return '${d.month}月${d.day}日 ${_weekdayLabels[d.weekday]}';
}

/// `09:05`（24 小时制）—— 必须补零，否则 9 点 5 分会写成 `9:5`。
String formatTime(int timestamp) {
  final d = DateTime.fromMillisecondsSinceEpoch(timestamp);
  return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

/// 训练是什么时候开始的：`今天 15:20` / `昨天 19:30` / `9月16日 19:30`。
///
/// 「今天 / 昨天」是为了让用户一眼认出主页那个「继续」按钮说的是哪一场 ——
/// 他打开 App 时心里想的正是「这是刚才那场，还是昨天那场」。
///
/// [now] 显式传入是为了可测：不传就用真实时间。
String formatDateTime(int timestamp, [int? now]) {
  final reference = now ?? DateTime.now().millisecondsSinceEpoch;
  final days = _calendarDaysBetween(reference, timestamp);
  if (days == 0) return '今天 ${formatTime(timestamp)}';
  if (days == 1) return '昨天 ${formatTime(timestamp)}';
  // 去掉 formatDate 末尾的星期 —— 这里已经有时间了，再加星期会把句子撑长
  return '${formatDate(timestamp).split(' ').first} ${formatTime(timestamp)}';
}

/// 按「日历天」算差，而不是按 24 小时。
///
/// 23:50 练完、次日 00:10 打开 App，两者只差 20 分钟但确实跨了一天，
/// 那时说「昨天」才对。做法是把两个时间戳都抹到当天零点再相减。
int _calendarDaysBetween(int now, int then) {
  final a = DateTime.fromMillisecondsSinceEpoch(now);
  final b = DateTime.fromMillisecondsSinceEpoch(then);
  final startOfA = DateTime(a.year, a.month, a.day).millisecondsSinceEpoch;
  final startOfB = DateTime(b.year, b.month, b.day).millisecondsSinceEpoch;
  return ((startOfA - startOfB) / 86400000).round();
}

/// 休息计时用的钟面：`12:34`（分:秒），超过一小时进位到 `65:20` 形式。
///
/// 与 [formatDuration] 分工不同：那个是总结页里的人话，这个是**一直在跳动的
/// 数字**，必须是等宽、等长、不换行，所以不带任何单位字。
String formatClock(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  final m = safe ~/ 60;
  final s = safe % 60;
  return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
}

/// 总结页里的人话时长：`45 秒` / `1 分 05 秒` / `1 小时 2 分`。
String formatDuration(int seconds) {
  final safe = seconds < 0 ? 0 : seconds;
  if (safe < 60) return '$safe 秒';

  final hours = safe ~/ 3600;
  final minutes = (safe % 3600) ~/ 60;
  final secs = safe % 60;

  if (hours > 0) return '$hours 小时 $minutes 分';
  return '$minutes 分 ${secs.toString().padLeft(2, '0')} 秒';
}
```

> `formatClock` 是计划里新增的 —— 旧项目的休息钟面由组件内部拼字符串。抽进
> `domain/` 是因为它是**纯函数且必须可单测**（`00:00` 与进位是边界）。

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/domain/format_test.dart -v`
Expected: `All tests passed!`（**13** 个测试 —— 计划初版写 9，补上 formatClock 的 4 条后为 13）

- [ ] **Step 5: 写失败的测试 —— 训练进度描述**

`test/domain/session_label_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/domain/session_label.dart';

ExerciseProgress ex(String name, int done, {int pending = 0}) => ExerciseProgress(
      exerciseName: name,
      sets: [
        ...List.generate(done, (_) => const SetProgress(isCompleted: true)),
        ...List.generate(pending, (_) => const SetProgress(isCompleted: false)),
      ],
    );

void main() {
  test('一个动作都没有 → 「还没有动作」', () {
    expect(describeExercises([]), '还没有动作');
  });

  test('单个动作不加「等」', () {
    expect(describeExercises([ex('深蹲', 2)]), '深蹲 · 已记 2 组');
  });

  test('多个动作说「等 N 个动作」', () {
    expect(
      describeExercises([ex('深蹲', 2), ex('卧推', 3), ex('硬拉', 0)]),
      '深蹲 等 3 个动作 · 已记 5 组',
    );
  });

  test('未完成的占位组不计入「已记」', () {
    expect(describeExercises([ex('深蹲', 2, pending: 1)]), '深蹲 · 已记 2 组');
  });

  test('一组都没完成时说「已记 0 组」', () {
    expect(describeExercises([ex('深蹲', 0, pending: 1)]), '深蹲 · 已记 0 组');
  });
}
```

- [ ] **Step 6: 跑测试确认失败**

Run: `flutter test test/domain/session_label_test.dart`
Expected: FAIL —— `session_label.dart` 不存在

- [ ] **Step 7: 写 `lib/domain/session_label.dart`**

```dart
/// `describeExercises` 需要的**最小**形状：只需要动作名和每组是否完成。
///
/// 参数写成结构化的最小形状（而不是依赖 `state/` 的 `ActiveExercise`），
/// 是为了让 domain 不反过来依赖编排层 —— `ActiveExercise` 天然满足这个形状。
class ExerciseProgress {
  final String exerciseName;
  final List<SetProgress> sets;

  const ExerciseProgress({required this.exerciseName, required this.sets});
}

class SetProgress {
  final bool isCompleted;

  const SetProgress({required this.isCompleted});
}

/// 描述一场进行中的训练练到哪了：`深蹲 等 3 个动作 · 已记 12 组`。
///
/// 主页按钮和「上一场训练还没结束」的询问弹窗共用它。抽出来不是为了省几行
/// 代码，而是为了让「这说的是哪一场」只有一个答案 —— 两处各写一遍，
/// 改一处忘一处时用户会看到两句互相矛盾的话，而这个按钮存在的全部意义
/// 就是让他确认「是不是我刚才那场」。
String describeExercises(List<ExerciseProgress> exercises) {
  if (exercises.isEmpty) return '还没有动作';

  var completed = 0;
  for (final e in exercises) {
    for (final s in e.sets) {
      if (s.isCompleted) completed++;
    }
  }

  final first = exercises.first.exerciseName;
  final what =
      exercises.length == 1 ? first : '$first 等 ${exercises.length} 个动作';
  return '$what · 已记 $completed 组';
}
```

- [ ] **Step 8: 跑测试确认通过**

Run: `flutter test test/domain/`
Expected: `All tests passed!`（16 + 10 + 13 + 5 = **44** 个测试）

- [ ] **Step 9: 提交**

```bash
git add lib/domain test/domain
git commit -m "feat(domain): 日期时长格式化与训练进度描述"
```

---

### Task 4: `test/layering_test.dart` —— 把分层规则变成会失败的测试

**Files:**
- Create: `test/layering_test.dart`

**Interfaces:**
- Consumes: `lib/` 下已存在的所有文件
- Produces: 一条守卫，后续每个 Task 都必须让它保持绿色

> 这个 Task 刻意排在数据层**之前** —— 让它从第一个仓储文件写出来就开始守。

- [ ] **Step 1: 写测试（它一开始就该通过，因为它守的是已有的 domain 层）**

`test/layering_test.dart`：

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 分层规则的**机械守卫**。
///
/// 规格 §2.2：旧项目把这三条叫「硬性规则」，但只靠约定守。而旧文档 §4.2 记着
/// 「判据两边同时写错的时候，只有端到端测试能发现」—— 约定守不住的东西，
/// 让测试守。
///
/// 这条测试**不看内容、只看 import 字符串**，所以它不会因为重构而误报。

/// 递归取出 `lib/` 下所有 `.dart` 文件，返回「相对路径 → 源码」。
Map<String, String> _allLibSources() {
  final result = <String, String>{};
  final dir = Directory('lib');
  if (!dir.existsSync()) return result;
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    // Windows 上是反斜杠，统一成正斜杠再做前缀判断
    final rel = entity.path.replaceAll(r'\', '/');
    result[rel] = entity.readAsStringSync();
  }
  return result;
}

/// 取出一个源文件里所有 `import '...'` / `export '...'` 的目标字符串。
List<String> _importsOf(String source) {
  final re = RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''', multiLine: true);
  return re.allMatches(source).map((m) => m.group(1)!).toList();
}

/// 这个文件是否属于某个目录（用于前缀匹配）。
bool _under(String path, String prefix) => path.startsWith(prefix);

void main() {
  final sources = _allLibSources();

  test('lib/ 下有源文件（防止 glob 写错导致本测试空转）', () {
    expect(sources, isNotEmpty);
  });

  test('规则 1：features/ 与 ui/ 永不直接 import data/db/', () {
    final violations = <String>[];
    sources.forEach((path, source) {
      if (!_under(path, 'lib/features/') && !_under(path, 'lib/ui/')) return;
      for (final imp in _importsOf(source)) {
        if (imp.contains('data/db/') || imp.contains('data\\db\\')) {
          violations.add('$path → $imp');
        }
      }
    });
    expect(violations, isEmpty,
        reason: '界面层只能通过 repositories 访问数据，不能碰 db/：\n${violations.join('\n')}');
  });

  test('规则 2：SQL 字符串只允许出现在 data/repositories/', () {
    // 识别「看起来是 SQL」的字符串字面量。保守：只认最典型的开头，
    // 避免把界面上的一句文案误判成 SQL。
    final sqlRe = RegExp(
      r'''(?:''' + "'''" + r'''|"|')\s*(?:SELECT|INSERT\s+INTO|UPDATE\s+\w+\s+SET|DELETE\s+FROM|CREATE\s+TABLE|ALTER\s+TABLE|PRAGMA)\b''',
      caseSensitive: false,
    );

    final violations = <String>[];
    sources.forEach((path, source) {
      // db/ 放 schema 与迁移 SQL，repositories/ 放查询 SQL —— 这两处是允许的
      if (_under(path, 'lib/data/db/') || _under(path, 'lib/data/repositories/')) {
        return;
      }
      if (sqlRe.hasMatch(source)) violations.add(path);
    });
    expect(violations, isEmpty,
        reason: 'SQL 只允许出现在 data/db/ 与 data/repositories/：\n${violations.join('\n')}');
  });

  test('规则 3：lib/domain/ 不得 import Flutter（它必须能用纯 dart test 跑）', () {
    final violations = <String>[];
    sources.forEach((path, source) {
      if (!_under(path, 'lib/domain/')) return;
      for (final imp in _importsOf(source)) {
        if (imp.startsWith('package:flutter/') ||
            imp.startsWith('package:sqflite') ||
            imp.startsWith('dart:ui')) {
          violations.add('$path → $imp');
        }
      }
    });
    expect(violations, isEmpty,
        reason: 'domain/ 是纯逻辑层，不得依赖 Flutter / 数据库：\n${violations.join('\n')}');
  });

  test('规则 4：lib/features/ 不得 import lib/state/ 之外的状态实现细节', () {
    // 界面通过 provider 拿 controller，但不该直接 import 具体实现文件之外的东西。
    // 这条规则较松，只挡「界面直接 new 一个仓储」这类越权。
    final violations = <String>[];
    sources.forEach((path, source) {
      if (!_under(path, 'lib/features/') && !_under(path, 'lib/ui/')) return;
      for (final imp in _importsOf(source)) {
        if (imp.contains('repositories/') && imp.contains('sqflite')) {
          violations.add('$path → $imp');
        }
      }
    });
    expect(violations, isEmpty);
  });
}
```

- [ ] **Step 2: 跑测试确认通过**

Run: `flutter test test/layering_test.dart -v`
Expected: `All tests passed!`（5 个测试）

- [ ] **Step 3: 故意破坏一次，确认它真的会红**

在 `lib/domain/metrics.dart` 顶部临时加一行 `import 'package:flutter/material.dart';`，跑 `flutter test test/layering_test.dart`，**必须看到规则 3 失败**。然后删掉那一行，再跑一次确认恢复绿色。

> 这一步不能省。**一条永远绿的守卫等于没有守卫** —— 旧文档那条教训（"一条会随机变红的测试比没有更危险"）的反面同样成立：一条**永远不红**的测试会给人虚假的安全感。

- [ ] **Step 4: 提交**

```bash
git add test/layering_test.dart
git commit -m "test: 把三条分层规则变成会失败的测试"
```

---

## 里程碑 B：数据层

### Task 5: `SqlExecutor` + 三后端 + schema v1 + 迁移框架

**Files:**
- Create: `lib/data/db/sql_executor.dart`
- Create: `lib/data/db/sqflite_executor.dart`
- Create: `lib/data/db/ffi_executor.dart`
- Create: `lib/data/db/schema.dart`
- Create: `lib/data/db/migrations.dart`
- Create: `lib/data/db/database.dart`
- Test: `test/data/migrations_test.dart`

**Interfaces:**
- Consumes: 无
- Produces:
  - `abstract class SqlExecutor { Future<void> run(String sql, [List<Object?>? params]); Future<List<T>> all<T>(String sql, [List<Object?>? params]); Future<T?> first<T>(String sql, [List<Object?>? params]); }`
  - `class SqfliteExecutor implements SqlExecutor` —— 生产
  - `class FfiExecutor implements SqlExecutor` —— 测试 / 桌面 / Chrome
  - `const String createTablesSql` / `createMetaSql`
  - `class Migration { int version; List<String> statements; }`
  - `const List<Migration> migrations`
  - `Future<int> getSchemaVersion(SqlExecutor exec)`
  - `Future<void> migrate(SqlExecutor exec)`
  - `const int schemaVersion`

- [ ] **Step 1: 写失败的测试 —— 迁移只跑一次，且全新库能建出表**

`test/data/migrations_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/migrations.dart';
import 'package:gym_tracker/data/db/schema.dart';

void main() {
  late FfiExecutor exec;

  setUp(() async {
    exec = await FfiExecutor.openInMemory();
  });

  tearDown(() async {
    await exec.close();
  });

  test('全新库版本号为 0', () async {
    expect(await getSchemaVersion(exec), 0);
  });

  test('migrate 后版本号升到当前版本', () async {
    await migrate(exec);
    expect(await getSchemaVersion(exec), schemaVersion);
  });

  test('migrate 是幂等的 —— 跑两次结果一样', () async {
    await migrate(exec);
    await migrate(exec);
    expect(await getSchemaVersion(exec), schemaVersion);
  });

  test('迁移后四张表 + app_meta 都在', () async {
    await migrate(exec);
    final rows = await exec.all<Map<String, Object?>>(
      "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
    );
    final names = rows.map((r) => r['name'] as String).toSet();
    expect(names, containsAll(<String>[
      'app_meta',
      'exercise',
      'session',
      'session_exercise',
      'set_entry',
    ]));
  });

  test('三行索引都建出来了（漏了会退化成全表扫描）', () async {
    await migrate(exec);
    final rows = await exec.all<Map<String, Object?>>(
      "SELECT name FROM sqlite_master WHERE type = 'index' AND name LIKE 'idx_%'",
    );
    final names = rows.map((r) => r['name'] as String).toSet();
    expect(names, containsAll(<String>[
      'idx_session_finished',
      'idx_session_exercise_session',
      'idx_set_entry_session_exercise',
    ]));
  });

  test('外键级联生效 —— 删 session 会带走它的 session_exercise', () async {
    await migrate(exec);
    await exec.run(
      "INSERT INTO exercise (id, name, is_custom, is_archived, created_at) VALUES ('e1', '深蹲', 0, 0, 1)",
    );
    await exec.run(
      "INSERT INTO session (id, started_at) VALUES ('s1', 1)",
    );
    await exec.run(
      "INSERT INTO session_exercise (id, session_id, exercise_id, position) VALUES ('se1', 's1', 'e1', 0)",
    );
    await exec.run(
      "INSERT INTO set_entry (id, session_exercise_id, position, weight, reps, is_completed) VALUES ('st1', 'se1', 0, 20, 8, 1)",
    );

    await exec.run("DELETE FROM session WHERE id = 's1'");

    expect(await exec.all("SELECT * FROM session_exercise"), isEmpty);
    expect(await exec.all("SELECT * FROM set_entry"), isEmpty);
    // 动作库不受影响 —— 动作只归档不删除
    expect(await exec.all("SELECT * FROM exercise"), hasLength(1));
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/data/migrations_test.dart`
Expected: FAIL —— `ffi_executor.dart` 不存在

- [ ] **Step 3: 写 `lib/data/db/sql_executor.dart`**

```dart
/// 最小 SQL 执行接口。
///
/// 数据库层只对外暴露这三个方法，是为了让上层（仓储、迁移）**不依赖具体的
/// SQLite 实现**：生产用 sqflite，测试用 `sqflite_common_ffi` 的内存库，
/// Chrome 预览用 `sqflite_common_ffi_web`，同一套仓储代码三边都跑。
///
/// **它比旧项目（React Native 版）薄。** 旧版里 sqflite 与 expo-sqlite 是两套
/// 互不相干的 API，这层抽象承担了「隔离具体实现」的主要价值；在 Dart 里
/// sqflite 自己就有 `DatabaseExecutor` 接口、三个后端实现的是同一个，
/// 那部分价值下降了。
///
/// 保留它是因为另外两条，**改这里的人请先读完再决定要不要删**：
///
/// 1. 它承载两条自定义语义，这两条是仓储代码的隐含前提 ——
///    - [run] **不传参数时要能跑多语句**（迁移的建表脚本是多条 CREATE 拼成的）
///    - [first] 一行都没有时返回 `null`；[all] 没有命中时返回 `[]`（不是 `null`）
/// 2. 它让仓储层完全不出现 sqflite 的类型 —— 将来加云同步时改动面不扩散
abstract class SqlExecutor {
  /// 执行一条 SQL，不取返回行。
  ///
  /// [params] 省略或传空数组都表示「没有参数」，此时**必须能跑多语句**。
  Future<void> run(String sql, [List<Object?>? params]);

  /// 查询多行。**没有命中时返回空数组，不是 null**，调用方不必判空。
  Future<List<T>> all<T>(String sql, [List<Object?>? params]);

  /// 查询单行。
  ///
  /// `T` 是**数据库原始行**（snake_case 列名），不是 `domain/types.dart` 里的
  /// 实体 —— 列名到实体的转换由各仓储的 `toXxx()` 负责。
  ///
  /// **一行都没有时返回 null**（已统一抹平 null/undefined 的差异）。
  Future<T?> first<T>(String sql, [List<Object?>? params]);
}
```

- [ ] **Step 4: 写 `lib/data/db/schema.dart`**

```dart
/// 建表 SQL。测试（内存库）与生产（sqflite）共用同一份字符串，
/// 因此这里任何语法错误都会在单元测试里立刻暴露。
///
/// 四张表与 `domain/types.dart` 的实体一一对应：
/// - `exercise` 动作库，预置动作与用户自建动作都在这里（`is_custom` 区分）
/// - `session` 一次训练，`finished_at` 为 NULL 就是「进行中」
/// - `session_exercise` 训练里的动作及顺序，`position` 决定界面上的先后
/// - `set_entry` 每一组：重量、次数、完成状态、休息时长
///
/// 三点全局约定：
/// - 三个外键都写 `ON DELETE CASCADE`，但**级联要生效必须先开
///   `PRAGMA foreign_keys = ON`**，而那个开关是连接级的（见 `database.dart`，
///   每次打开连接后立刻打开；测试适配器同样打开）。
/// - 时间一律存**毫秒时间戳**（INTEGER），不存字符串日期。
/// - 布尔一律存 0/1：SQLite 没有布尔类型。
///
/// 末三行是索引。它们不是可选的：历史列表按 `finished_at` 筛、进步页要按
/// `session_exercise_id` 反查组，没有索引会退化成全表扫描。
const String createTablesSql = '''
CREATE TABLE IF NOT EXISTS exercise (
  id            TEXT PRIMARY KEY,
  name          TEXT NOT NULL,
  muscle_group  TEXT,
  equipment     TEXT,
  is_custom     INTEGER NOT NULL DEFAULT 0,
  is_archived   INTEGER NOT NULL DEFAULT 0,
  created_at    INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS session (
  id          TEXT PRIMARY KEY,
  name        TEXT,
  started_at  INTEGER NOT NULL,
  finished_at INTEGER,
  note        TEXT
);

CREATE TABLE IF NOT EXISTS session_exercise (
  id          TEXT PRIMARY KEY,
  session_id  TEXT NOT NULL REFERENCES session(id) ON DELETE CASCADE,
  exercise_id TEXT NOT NULL REFERENCES exercise(id),
  position    INTEGER NOT NULL,
  note        TEXT
);

CREATE TABLE IF NOT EXISTS set_entry (
  id                  TEXT PRIMARY KEY,
  session_exercise_id TEXT NOT NULL REFERENCES session_exercise(id) ON DELETE CASCADE,
  position            INTEGER NOT NULL,
  weight              REAL NOT NULL,
  reps                INTEGER NOT NULL,
  is_completed        INTEGER NOT NULL DEFAULT 0,
  rest_seconds        INTEGER,
  rest_started_at     INTEGER,
  completed_at        INTEGER
);

CREATE INDEX IF NOT EXISTS idx_session_finished ON session(finished_at);
CREATE INDEX IF NOT EXISTS idx_session_exercise_session ON session_exercise(session_id);
CREATE INDEX IF NOT EXISTS idx_set_entry_session_exercise ON set_entry(session_exercise_id);
''';

/// 迁移版本号表。键值对形式，目前只存 `schema_version` 一个键。
///
/// 单独建这一张表，是因为它必须是**全新数据库里第一张被建出来的表**：
/// `migrate()` 要先把版本号读出来，才知道该跑哪些迁移，所以它不能属于任何一个
/// 版本化迁移项（那样就成了先有鸡还是先有蛋）。
const String createMetaSql = '''
CREATE TABLE IF NOT EXISTS app_meta (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
''';

/// 用户偏好设置。键值对形式，值是文本。
///
/// **与 `app_meta` 分开是有意的**：`app_meta` 属于库结构本身（版本号），
/// 进备份、进迁移；这一张属于用户偏好，跟着用户走，语义不同。
const String createSettingsSql = '''
CREATE TABLE IF NOT EXISTS app_setting (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);
''';
```

- [ ] **Step 5: 写 `lib/data/db/migrations.dart`**

```dart
import 'schema.dart';
import 'sql_executor.dart';

/// 一个版本化迁移项。
///
/// `version` 从 1 开始连续编号，[migrate] 按它升序执行所有大于当前版本的项。
/// 一个版本里可以有多条语句，它们会**逐条执行**，但**不在同一个事务里** ——
/// 所以单条语句必须是幂等的（都写成 `CREATE ... IF NOT EXISTS`）。
class Migration {
  final int version;
  final List<String> statements;

  const Migration({required this.version, required this.statements});
}

/// **版本化迁移。新增 schema 变更时追加一项，绝不修改已发布的项。**
///
/// 为什么不能并进旧项：v1/v2 早就发布过，库里的 `schema_version` 已经是 2 的库
/// 不会再跑它们（[migrate] 只跑 `version > current` 的项），新列会永远加不上。
///
/// 每一项都应配一条回归测试：手工造一个「只跑到 vN-1」的库，
/// 验证它升到 vN 后有表 / 列可用（见 `test/data/migrations_test.dart`）。
const List<Migration> migrations = [
  Migration(version: 1, statements: [createMetaSql, createTablesSql]),
  Migration(version: 2, statements: [createSettingsSql]),
];

/// 当前库结构版本。必须与 [migrations] 的最后一项保持一致。
const int schemaVersion = 2;

/// 读出当前库结构版本。
///
/// 全新数据库里 `app_meta` 还不存在，直接查会抛 `no such table` ——
/// 迁移尚未跑过时版本号定义为 0。
Future<int> getSchemaVersion(SqlExecutor exec) async {
  final meta = await exec.first<Map<String, Object?>>(
    "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'app_meta'",
  );
  if (meta == null) return 0;

  final row = await exec.first<Map<String, Object?>>(
    "SELECT value FROM app_meta WHERE key = 'schema_version'",
  );
  return row == null ? 0 : int.parse(row['value'] as String);
}

/// 依次执行尚未应用的迁移，完成后写入新的版本号。
/// 已经是最新版本时不做任何事（幂等，每次启动都会调用）。
Future<void> migrate(SqlExecutor exec) async {
  // app_meta 必须先存在，否则读不到版本号
  await exec.run(createMetaSql);

  final current = await getSchemaVersion(exec);
  final pending = migrations.where((m) => m.version > current).toList()
    ..sort((a, b) => a.version - b.version);

  for (final migration in pending) {
    for (final statement in migration.statements) {
      await exec.run(statement);
    }
    await exec.run(
      """INSERT INTO app_meta (key, value) VALUES ('schema_version', ?)
         ON CONFLICT(key) DO UPDATE SET value = excluded.value""",
      [migration.version.toString()],
    );
  }
}
```

- [ ] **Step 6: 写 `lib/data/db/ffi_executor.dart`**

```dart
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'migrations.dart';
import 'sql_executor.dart';

/// 基于 `sqflite_common_ffi` 的执行器 —— 用于**单元测试**（内存库）与桌面运行。
///
/// 它在这里的角色，等同于旧项目（React Native 版）里 `node:sqlite` 适配器的角色：
/// 让同一套仓储代码在不启动 Android 的前提下被真实地测到。
///
/// 它也同时服务 Chrome 预览 —— `database_factory_web` 打开的那个
/// `Database` 直接交给 [FfiExecutor.fromDatabase] 即可，**不需要第二套实现**。
class FfiExecutor implements SqlExecutor {
  final Database _db;

  FfiExecutor._(this._db);

  /// 包一个已经打开的 `Database`。
  ///
  /// Chrome 预览走这条路（web 的 factory 在 `database.dart` 里设好之后打开库，
  /// 再把 `Database` 交给这里）—— **三个后端共用同一个执行器类**，
  /// 差别只在「怎么打开库」。
  factory FfiExecutor.fromDatabase(Database db) => FfiExecutor._(db);

  /// 打开一个**内存**库，并立刻开外键。
  ///
  /// `PRAGMA foreign_keys` 是**连接级**开关，不开的话建表时写的
  /// `ON DELETE CASCADE` 完全不生效 —— 而那种失效是静默的：
  /// 删除不会报错，只是子表数据留了下来。
  static Future<FfiExecutor> openInMemory() async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
    await db.execute('PRAGMA foreign_keys = ON');
    return FfiExecutor._(db);
  }

  /// 在内存库上先跑完迁移，返回可直接使用的执行器 —— 测试里的常用入口。
  static Future<FfiExecutor> openMigrated() async {
    final exec = await openInMemory();
    await migrate(exec);
    return exec;
  }

  @override
  Future<void> run(String sql, [List<Object?>? params]) async {
    // 无参数 → 可能是一串多语句（迁移的建表脚本就是），用 execute；
    // 有参数 → 走 rawInsert，因为 execute 不接受参数。
    if (params == null || params.isEmpty) {
      await _db.execute(sql);
    } else {
      await _db.rawInsert(sql, params);
    }
  }

  @override
  Future<List<T>> all<T>(String sql, [List<Object?>? params]) async {
    final rows = await _db.rawQuery(sql, params);
    return rows.cast<T>();
  }

  @override
  Future<T?> first<T>(String sql, [List<Object?>? params]) async {
    final rows = await _db.rawQuery(sql, params);
    return rows.isEmpty ? null : rows.first as T;
  }

  Future<void> close() => _db.close();
}
```

> **`openMigrated` 直接调 `migrate(exec)`**（来自 `migrations.dart`）——
> 全项目只有一个 migrate 实现，不要在这里转发一层。

- [ ] **Step 7: 写 `lib/data/db/sqflite_executor.dart`**

```dart
import 'package:sqflite/sqflite.dart' as sqflite;

import 'sql_executor.dart';

/// 生产用的执行器（Android / iOS）。
///
/// 与 [FfiExecutor] 的差别只在「怎么打开库」，三个方法的语义完全一致 ——
/// 这正是保留 [SqlExecutor] 这层接缝的意义。
class SqfliteExecutor implements SqlExecutor {
  final sqflite.Database _db;

  SqfliteExecutor._(this._db);

  static Future<SqfliteExecutor> open(String path) async {
    final db = await sqflite.openDatabase(path);
    // 连接级的开关，不开则 ON DELETE CASCADE 静默失效
    await db.execute('PRAGMA foreign_keys = ON');
    return SqfliteExecutor._(db);
  }

  static Future<SqfliteExecutor> openInMemory() async {
    final db = await sqflite.openDatabase(sqflite.inMemoryDatabasePath);
    await db.execute('PRAGMA foreign_keys = ON');
    return SqfliteExecutor._(db);
  }

  @override
  Future<void> run(String sql, [List<Object?>? params]) async {
    if (params == null || params.isEmpty) {
      await _db.execute(sql);
    } else {
      await _db.rawInsert(sql, params);
    }
  }

  @override
  Future<List<T>> all<T>(String sql, [List<Object?>? params]) async {
    final rows = await _db.rawQuery(sql, params);
    return rows.cast<T>();
  }

  @override
  Future<T?> first<T>(String sql, [List<Object?>? params]) async {
    final rows = await _db.rawQuery(sql, params);
    return rows.isEmpty ? null : rows.first as T;
  }

  Future<void> close() => _db.close();
}
```

- [ ] **Step 8: 跑测试确认通过**

Run: `flutter test test/data/migrations_test.dart -v`
Expected: `All tests passed!`（6 个测试）

> **若 `run` 的多语句分支报错**：`sqflite` 的 `execute` 在部分平台上一次只跑一条。
> 若如此，改成按 `;` 拆分后逐条执行（**但拆分要避开字符串字面量里的分号**，
> 本项目的建表 SQL 不含这种，所以简单 `split(';')` 加去空行即可）。
> 把这个结论写进 `dev-environment-notes.md`。

- [ ] **Step 9: 提交**

```bash
git add lib/data/db test/data
git commit -m "feat(db): SqlExecutor 三后端、schema v1/v2 与只追加的版本化迁移"
```

---

### Task 6: `exercise_repo.dart` + 52 个预置动作播种

**Files:**
- Create: `lib/data/repositories/seed.dart`
- Create: `lib/data/repositories/exercise_repo.dart`
- Test: `test/data/exercise_repo_test.dart`

**Interfaces:**
- Consumes: `SqlExecutor`、`Exercise`
- Produces:
  - `class SeedExercise { String name; String muscleGroup; String equipment; }`
  - `const List<SeedExercise> seedExercises`（**恰好 52 条**）
  - `class ExerciseRow` + `Exercise toExercise(ExerciseRow row)`
  - `const String exerciseColumns`
  - `Future<List<Exercise>> listExercises(SqlExecutor exec)`
  - `Future<Exercise?> getExercise(SqlExecutor exec, String id)`
  - `Future<Exercise> createCustomExercise(SqlExecutor exec, {required String name, String? muscleGroup, String? equipment})`
  - `Future<void> seedExercisesIfEmpty(SqlExecutor exec)`

- [ ] **Step 1: 写失败的测试**

`test/data/exercise_repo_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/migrations.dart';
import 'package:gym_tracker/data/repositories/exercise_repo.dart';
import 'package:gym_tracker/data/repositories/seed.dart';

void main() {
  late FfiExecutor exec;

  setUp(() async {
    exec = await FfiExecutor.openInMemory();
    await migrate(exec);
  });

  tearDown(() async => exec.close());

  test('预置动作恰好 52 个', () {
    expect(seedExercises, hasLength(52));
  });

  test('播种写入 52 个动作，is_custom 一律为 0', () async {
    await seedExercisesIfEmpty(exec);
    final all = await listExercises(exec);
    expect(all, hasLength(52));
    expect(all.every((e) => !e.isCustom), isTrue);
  });

  test('播种只在空表时发生 —— 已有动作时不再写', () async {
    await seedExercisesIfEmpty(exec);
    await seedExercisesIfEmpty(exec);
    expect(await listExercises(exec), hasLength(52));
  });

  test('用户先自建了动作，就不该再塞预置动作进去', () async {
    await createCustomExercise(exec, name: '我的动作');
    await seedExercisesIfEmpty(exec);
    final all = await listExercises(exec);
    expect(all, hasLength(1));
    expect(all.single.name, '我的动作');
  });

  test('排序：先按肌群名次（胸背腿肩手臂核心），同肌群按拼音', () async {
    await seedExercisesIfEmpty(exec);
    final all = await listExercises(exec);
    // 排第一的必须是胸组的动作
    expect(all.first.muscleGroup, '胸');
    // 同一肌群内按拼音：胸组里 "俯卧撑" (fu) 应早于 "绳索夹胸" (sheng)
    final chest = all.where((e) => e.muscleGroup == '胸').toList();
    final fu = chest.indexWhere((e) => e.name == '俯卧撑');
    final sheng = chest.indexWhere((e) => e.name == '绳索夹胸');
    expect(fu, lessThan(sheng));
  });

  test('归档的动作不出现在列表里，但仍能按 id 取到', () async {
    await seedExercisesIfEmpty(exec);
    final target = (await listExercises(exec)).first;
    await exec.run('UPDATE exercise SET is_archived = 1 WHERE id = ?', [target.id]);

    final visible = await listExercises(exec);
    expect(visible.any((e) => e.id == target.id), isFalse);
    // 历史记录引用着它，取不到就会显示成「未知动作」
    expect((await getExercise(exec, target.id))?.name, target.name);
  });

  test('自建动作 isCustom 为 true，且带 null 肌群时排到最后', () async {
    await seedExercisesIfEmpty(exec);
    await createCustomExercise(exec, name: '自定义动作');
    final all = await listExercises(exec);
    expect(all.last.name, '自定义动作');
    expect(all.last.isCustom, isTrue);
  });

  test('中文按拼音序而不是 UTF-8 码点序', () async {
    await createCustomExercise(exec, name: '深蹲架', muscleGroup: '腿');
    await createCustomExercise(exec, name: '保加利亚', muscleGroup: '腿');
    await createCustomExercise(exec, name: '硬拉', muscleGroup: '腿');
    final legs = (await listExercises(exec)).where((e) => e.muscleGroup == '腿').toList();
    // 按码点序会排成「保加利亚、硬拉、深蹲架」——
    // 拼音序才是中文用户预期的「保加利亚(bao)、深蹲架(shen)、硬拉(ying)」
    final names = legs.map((e) => e.name).toList();
    expect(names.indexOf('保加利亚'), lessThan(names.indexOf('深蹲架')));
    expect(names.indexOf('深蹲架'), lessThan(names.indexOf('硬拉')));
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/data/exercise_repo_test.dart`
Expected: FAIL —— `exercise_repo.dart` 不存在

- [ ] **Step 3: 写 `lib/data/repositories/seed.dart`**

`id` 不写死 —— 播种时用 `newId()` 现生成，避免多设备撞 id。

```dart
import 'package:uuid/uuid.dart';

const _uuid = Uuid();

/// 新的唯一 id。全项目只有这一处生成 id，方便将来换实现。
String newId() => _uuid.v4();

/// 预置动作的模板。
class SeedExercise {
  final String name;
  final String muscleGroup;
  final String equipment;

  const SeedExercise(this.name, this.muscleGroup, this.equipment);
}

/// 预置动作表，按肌群分组书写，顺序与界面上的展示顺序一致。
///
/// 只在**全新数据库**（`exercise` 表一行都没有）时写入一次。
/// 改动它不会影响已有用户的库 —— 他们已经播过种了。
const List<SeedExercise> seedExercises = [
  // 腿（12）
  SeedExercise('深蹲', '腿', '杠铃'),
  SeedExercise('前蹲', '腿', '杠铃'),
  SeedExercise('硬拉', '腿', '杠铃'),
  SeedExercise('罗马尼亚硬拉', '腿', '杠铃'),
  SeedExercise('腿举', '腿', '器械'),
  SeedExercise('腿屈伸', '腿', '器械'),
  SeedExercise('腿弯举', '腿', '器械'),
  SeedExercise('保加利亚分腿蹲', '腿', '哑铃'),
  SeedExercise('箭步蹲', '腿', '哑铃'),
  SeedExercise('站姿提踵', '腿', '器械'),
  SeedExercise('坐姿提踵', '腿', '器械'),
  SeedExercise('臀推', '腿', '杠铃'),

  // 胸（9）
  SeedExercise('卧推', '胸', '杠铃'),
  SeedExercise('上斜卧推', '胸', '杠铃'),
  SeedExercise('下斜卧推', '胸', '杠铃'),
  SeedExercise('哑铃卧推', '胸', '哑铃'),
  SeedExercise('哑铃飞鸟', '胸', '哑铃'),
  SeedExercise('绳索夹胸', '胸', '绳索'),
  SeedExercise('双杠臂屈伸', '胸', '自重'),
  SeedExercise('俯卧撑', '胸', '自重'),
  SeedExercise('器械推胸', '胸', '器械'),

  // 背（9）
  SeedExercise('引体向上', '背', '自重'),
  SeedExercise('高位下拉', '背', '器械'),
  SeedExercise('杠铃划船', '背', '杠铃'),
  SeedExercise('哑铃单臂划船', '背', '哑铃'),
  SeedExercise('坐姿绳索划船', '背', '绳索'),
  SeedExercise('T 杠划船', '背', '杠铃'),
  SeedExercise('直臂下压', '背', '绳索'),
  SeedExercise('面拉', '背', '绳索'),
  SeedExercise('山羊挺身', '背', '自重'),

  // 肩（7）
  SeedExercise('站姿推举', '肩', '杠铃'),
  SeedExercise('坐姿哑铃推举', '肩', '哑铃'),
  SeedExercise('侧平举', '肩', '哑铃'),
  SeedExercise('前平举', '肩', '哑铃'),
  SeedExercise('俯身飞鸟', '肩', '哑铃'),
  SeedExercise('反向蝴蝶机', '肩', '器械'),
  SeedExercise('耸肩', '肩', '杠铃'),

  // 手臂（9）
  SeedExercise('杠铃弯举', '手臂', '杠铃'),
  SeedExercise('哑铃弯举', '手臂', '哑铃'),
  SeedExercise('锤式弯举', '手臂', '哑铃'),
  SeedExercise('牧师凳弯举', '手臂', '器械'),
  SeedExercise('绳索下压', '手臂', '绳索'),
  SeedExercise('仰卧臂屈伸', '手臂', '杠铃'),
  SeedExercise('过顶臂屈伸', '手臂', '哑铃'),
  SeedExercise('窄距卧推', '手臂', '杠铃'),
  SeedExercise('腕弯举', '手臂', '哑铃'),

  // 核心（6）
  SeedExercise('卷腹', '核心', '自重'),
  SeedExercise('悬垂举腿', '核心', '自重'),
  SeedExercise('平板支撑', '核心', '自重'),
  SeedExercise('俄罗斯转体', '核心', '哑铃'),
  SeedExercise('绳索卷腹', '核心', '绳索'),
  SeedExercise('健腹轮', '核心', '自重'),
];
```

> **`newId()` 放在 `seed.dart` 里是权宜**。更干净的位置是 `lib/data/ids.dart`。
> 若你这么做，**记得同步改所有 import**，并让 `layering_test.dart` 保持绿色。

- [ ] **Step 4: 写 `lib/data/repositories/exercise_repo.dart`**

```dart
import '../db/sql_executor.dart';
import 'seed.dart';

/// `exercise` 表的原始行。布尔在库里是 0/1，转换见 [toExercise]。
class ExerciseRow {
  final String id;
  final String name;
  final String? muscle_group;
  final String? equipment;
  final int is_custom;
  final int is_archived;
  final int created_at;

  const ExerciseRow({
    required this.id,
    required this.name,
    this.muscle_group,
    this.equipment,
    required this.is_custom,
    required this.is_archived,
    required this.created_at,
  });

  factory ExerciseRow.fromMap(Map<String, Object?> m) => ExerciseRow(
        id: m['id'] as String,
        name: m['name'] as String,
        muscle_group: m['muscle_group'] as String?,
        equipment: m['equipment'] as String?,
        is_custom: m['is_custom'] as int,
        is_archived: m['is_archived'] as int,
        created_at: m['created_at'] as int,
      );
}

/// 行 → 实体。snake_case 转 camelCase，并把 0/1 还原成布尔。
Exercise toExercise(ExerciseRow row) => Exercise(
      id: row.id,
      name: row.name,
      muscleGroup: row.muscle_group,
      equipment: row.equipment,
      isCustom: row.is_custom == 1,
      isArchived: row.is_archived == 1,
      createdAt: row.created_at,
    );

/// SELECT 的列清单。抽出来是为了让「列」与「映射」永远对得上。
const String exerciseColumns =
    'id, name, muscle_group, equipment, is_custom, is_archived, created_at';

/// 肌群的展示顺序。不在这个表里的肌群一律排到最后。
const List<String> muscleGroupOrder = ['胸', '背', '腿', '肩', '手臂', '核心'];

/// 不在 [muscleGroupOrder] 里的（含 null）**一律排到最后**，而不是排到最前。
int muscleGroupRank(String? group) {
  final index = muscleGroupOrder.indexOf(group ?? '');
  return index == -1 ? muscleGroupOrder.length : index;
}

/// 按肌群、再按动作名排序。
///
/// **名称必须在这里用拼音序排，不能交给 SQLite。**
/// SQLite 的 `COLLATE NOCASE` 只做 ASCII 大小写折叠，对中文退化为 UTF-8
/// 码点比较，排出来是「保加利亚分腿蹲、前蹲、坐姿提踵、深蹲、硬拉…」
/// 这种对人来说毫无规律的顺序。**Dart 的 `String.compareTo` 同样是码点序，
/// 也不能用。**
int compareExercises(Exercise a, Exercise b) {
  final rankDiff = muscleGroupRank(a.muscleGroup) - muscleGroupRank(b.muscleGroup);
  if (rankDiff != 0) return rankDiff;
  final byPinyin = pinyinKey(a.name).compareTo(pinyinKey(b.name));
  if (byPinyin != 0) return byPinyin;
  // 拼音相同时退回码点序，保证排序是**确定的**（不依赖输入顺序）
  return a.name.compareTo(b.name);
}
```

- [ ] **Step 5: 加 `pinyin` 依赖并写 `pinyinKey`**

```powershell
flutter pub add pinyin
```

在 `lib/data/repositories/exercise_repo.dart` 顶部加 import，并追加：

```dart
import 'package:pinyin/pinyin.dart';

/// 中文动作名的拼音键，用于排序。
///
/// 中文用户预期的「按字母排」是拼音序；SQLite 与 Dart 的默认比较都是
/// UTF-8 码点序，对中文等于随机顺序。
///
/// `separator: ''` 去掉音节分隔（我们要的是整串比较），
/// `defPinyin: '#'` 让不认识的字符集中排到最后而不是抛错。
String pinyinKey(String name) =>
    PinyinHelper.getPinyinE(name, separator: '', defPinyin: '#');
```

> **若 `pinyin` 包不可用或 API 不符**：改用 `lpinyin` 包。
> 若两个都不可用，**停下来和用户确认**，不要自行改测试里的排序断言 ——
> 那三条断言锁的是「中文按拼音序」这条真实的用户预期。

- [ ] **Step 6: 跑排序测试确认通过**

Run: `flutter test test/data/exercise_repo_test.dart`
Expected: 排序相关测试 PASS

- [ ] **Step 7: 补齐仓储的其余函数**

在 `lib/data/repositories/exercise_repo.dart` 末尾追加：

```dart
/// 列出全部**未归档**的动作，已按肌群 + 拼音排好序。
///
/// 排序在 Dart 里做而不是 SQL 里，原因见 [compareExercises]。
Future<List<Exercise>> listExercises(SqlExecutor exec) async {
  final rows = await exec.all<Map<String, Object?>>(
    'SELECT $exerciseColumns FROM exercise WHERE is_archived = 0',
  );
  final list = rows.map((m) => toExercise(ExerciseRow.fromMap(m))).toList();
  list.sort(compareExercises);
  return list;
}

/// 按 id 取一个动作。
///
/// **id 不存在时返回 null。** 注意**已归档的动作也能取到** ——
/// 历史记录里引用着它，取不到就会显示成「未知动作」。
Future<Exercise?> getExercise(SqlExecutor exec, String id) async {
  final row = await exec.first<Map<String, Object?>>(
    'SELECT $exerciseColumns FROM exercise WHERE id = ?',
    [id],
  );
  return row == null ? null : toExercise(ExerciseRow.fromMap(row));
}

/// 新建一个用户自建动作（`isCustom` 一律为 true，预置动作只能由播种写入）。
///
/// 不做重名检查：动作库里本来就有「卧推 / 上斜卧推 / 窄距卧推」这类同名前缀，
/// 判断重名比让用户自己看更烦人。
Future<Exercise> createCustomExercise(
  SqlExecutor exec, {
  required String name,
  String? muscleGroup,
  String? equipment,
}) async {
  final exercise = Exercise(
    id: newId(),
    name: name,
    muscleGroup: muscleGroup,
    equipment: equipment,
    isCustom: true,
    isArchived: false,
    createdAt: DateTime.now().millisecondsSinceEpoch,
  );

  await exec.run(
    '''INSERT INTO exercise (id, name, muscle_group, equipment, is_custom, is_archived, created_at)
       VALUES (?, ?, ?, ?, 1, 0, ?)''',
    [exercise.id, exercise.name, exercise.muscleGroup, exercise.equipment, exercise.createdAt],
  );

  return exercise;
}

/// 只在动作表为空时写入预置动作。
///
/// 判断依据是「表里一个动作都没有」，而不是「表里没有预置动作」——
/// 用户如果自己先建了动作，就不该再塞一堆预置动作进去。
Future<void> seedExercisesIfEmpty(SqlExecutor exec) async {
  final row = await exec.first<Map<String, Object?>>(
    'SELECT COUNT(*) AS count FROM exercise',
  );
  final count = (row?['count'] as int?) ?? 0;
  if (count > 0) return;

  final now = DateTime.now().millisecondsSinceEpoch;
  for (final item in seedExercises) {
    await exec.run(
      '''INSERT INTO exercise (id, name, muscle_group, equipment, is_custom, is_archived, created_at)
         VALUES (?, ?, ?, ?, 0, 0, ?)''',
      [newId(), item.name, item.muscleGroup, item.equipment, now],
    );
  }
}
```

- [ ] **Step 8: 跑全部测试确认通过**

Run: `flutter test test/data/exercise_repo_test.dart -v`
Expected: `All tests passed!`（8 个测试）

- [ ] **Step 9: 提交**

```bash
git add lib/data/repositories test/data
git commit -m "feat(data): 动作仓储与 52 个预置动作播种，中文按拼音序排序"
```

---

### Task 7: `session_repo.dart`

**Files:**
- Create: `lib/data/repositories/session_repo.dart`
- Test: `test/data/session_repo_test.dart`

**Interfaces:**
- Consumes: `SqlExecutor`、`newId()`、`WorkoutSession`、`SessionExercise`
- Produces:
  - `WorkoutSession toSession(SessionRow row)` / `SessionExercise toSessionExercise(SessionExerciseRow row)`
  - `const String sessionColumns` / `sessionExerciseColumns`
  - `Future<WorkoutSession> createSession(SqlExecutor exec, {String? name, String? templateId})`
  - `Future<WorkoutSession?> getSession(SqlExecutor exec, String id)`
  - `Future<WorkoutSession?> getActiveSession(SqlExecutor exec)`
  - `Future<void> finishSession(SqlExecutor exec, String id, int finishedAt)`
  - `Future<List<WorkoutSession>> listSessions(SqlExecutor exec, int limit)`
  - `Future<SessionExercise> addExerciseToSession(SqlExecutor exec, String sessionId, String exerciseId)`
  - `Future<List<SessionExercise>> listSessionExercises(SqlExecutor exec, String sessionId)`
  - `Future<String?> findLastActiveSessionExerciseId(SqlExecutor exec, String sessionId)`

> 为节省篇幅，本 Task 的测试只列**必须有的边界** —— 实现时按 Interfaces 逐个函数写，
> 每个函数至少一条测试覆盖它的边界。

- [ ] **Step 1: 写失败的测试（含 rowid 兜底那条关键用例）**

`test/data/session_repo_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/migrations.dart';
import 'package:gym_tracker/data/repositories/session_repo.dart';

void main() {
  late FfiExecutor exec;

  setUp(() async {
    exec = await FfiExecutor.openInMemory();
    await migrate(exec);
    await exec.run(
      "INSERT INTO exercise (id, name, is_custom, is_archived, created_at) VALUES ('e1', '深蹲', 0, 0, 1)",
    );
  });

  tearDown(() async => exec.close());

  test('新建的训练是进行中的', () async {
    final s = await createSession(exec, name: null, templateId: null);
    expect(s.finishedAt, isNull);
    expect((await getActiveSession(exec))?.id, s.id);
  });

  test('getSession 能取到进行中的那一场（不像 listSessions 会滤掉）', () async {
    final s = await createSession(exec, name: '推日', templateId: null);
    expect((await getSession(exec, s.id))?.name, '推日');
  });

  test('listSessions 只返回已结束的', () async {
    final s = await createSession(exec, name: null, templateId: null);
    expect(await listSessions(exec, 50), isEmpty);
    await finishSession(exec, s.id, DateTime.now().millisecondsSinceEpoch);
    expect(await listSessions(exec, 50), hasLength(1));
  });

  test('结束训练后不再是进行中的', () async {
    final s = await createSession(exec, name: null, templateId: null);
    await finishSession(exec, s.id, 12345);
    expect(await getActiveSession(exec), isNull);
  });

  // ⭐ 这条是 rowid 兜底的存在理由，不能删
  test('同一毫秒开始的两场，取最新时按 rowid 兜底（否则语义反了）', () async {
    const sameMs = 1700000000000;

    // 显式把两行设成同一个 started_at —— 让「并列」成为**确定事件**，
    // 而不是赌两次调用恰好落在同一毫秒（那种测试实测 20 次闪 2 次）。
    await createSession(exec, name: '先建的', templateId: null);
    await createSession(exec, name: '后建的', templateId: null);
    await exec.run('UPDATE session SET started_at = ?', [sameMs]);

    final rows = await exec.all<Map<String, Object?>>(
      'SELECT name, started_at FROM session ORDER BY started_at ASC',
    );
    // 先断言并列真的发生了，否则这条测试就在空转
    expect(rows[0]['started_at'], rows[1]['started_at']);

    final list = await listSessions(exec, 50);
    // 已结束的才进 listSessions，所以先都结束掉
    //
    // 注意：上面两次 createSession 都没结束，这里补上
    await exec.run('UPDATE session SET finished_at = ?', [sameMs + 1]);
    final finished = await listSessions(exec, 50);
    // 同毫秒时 SQLite 按扫描顺序返回（先插入的在前）——语义正好反了。
    // rowid DESC 兜底后，后建的「后建的」必须排在前。
    expect(finished.first.name, '后建的');
    expect(list, isEmpty); // 结束之前 listSessions 是空的
  });

  test('加入动作的 position 依次递增', () async {
    final s = await createSession(exec, name: null, templateId: null);
    final a = await addExerciseToSession(exec, s.id, 'e1');
    final b = await addExerciseToSession(exec, s.id, 'e1');
    expect(a.position, 0);
    expect(b.position, 1);
  });

  test('动作按 position 升序返回', () async {
    final s = await createSession(exec, name: null, templateId: null);
    final a = await addExerciseToSession(exec, s.id, 'e1');
    final b = await addExerciseToSession(exec, s.id, 'e1');
    final list = await listSessionExercises(exec, s.id);
    expect(list.map((e) => e.id).toList(), [a.id, b.id]);
  });

  test('没有动作时返回空数组（不是 null）', () async {
    final s = await createSession(exec, name: null, templateId: null);
    expect(await listSessionExercises(exec, s.id), isEmpty);
  });

  test('一组都没完成过时，findLastActive 返回 null', () async {
    final s = await createSession(exec, name: null, templateId: null);
    await addExerciseToSession(exec, s.id, 'e1');
    expect(await findLastActiveSessionExerciseId(exec, s.id), isNull);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/data/session_repo_test.dart`
Expected: FAIL —— `session_repo.dart` 不存在

- [ ] **Step 3: 实现 `lib/data/repositories/session_repo.dart`**

完整实现（SQL 与旧项目逐字一致）：

```dart
import '../../domain/types.dart';
import '../db/sql_executor.dart';
import 'seed.dart';

class SessionRow {
  final String id;
  final String? name;
  final int started_at;
  final int? finished_at;
  final String? note;
  final String? template_id;

  const SessionRow({required this.id, this.name, required this.started_at,
    this.finished_at, this.note, this.template_id});

  factory SessionRow.fromMap(Map<String, Object?> m) => SessionRow(
        id: m['id'] as String,
        name: m['name'] as String?,
        started_at: m['started_at'] as int,
        finished_at: m['finished_at'] as int?,
        note: m['note'] as String?,
        template_id: m['template_id'] as String?,
      );
}

class SessionExerciseRow {
  final String id;
  final String session_id;
  final String exercise_id;
  final int position;
  final String? note;

  const SessionExerciseRow({required this.id, required this.session_id,
    required this.exercise_id, required this.position, this.note});

  factory SessionExerciseRow.fromMap(Map<String, Object?> m) => SessionExerciseRow(
        id: m['id'] as String,
        session_id: m['session_id'] as String,
        exercise_id: m['exercise_id'] as String,
        position: m['position'] as int,
        note: m['note'] as String?,
      );
}

WorkoutSession toSession(SessionRow row) => WorkoutSession(
      id: row.id,
      name: row.name,
      startedAt: row.started_at,
      finishedAt: row.finished_at,
      note: row.note,
      templateId: row.template_id,
    );

SessionExercise toSessionExercise(SessionExerciseRow row) => SessionExercise(
      id: row.id,
      sessionId: row.session_id,
      exerciseId: row.exercise_id,
      position: row.position,
      note: row.note,
    );

const String sessionColumns = 'id, name, started_at, finished_at, note, template_id';
const String sessionExerciseColumns = 'id, session_id, exercise_id, position, note';

/// 开一场新训练。`finishedAt` 与 `note` 一律为空 —— 新训练必然是进行中的。
///
/// 本函数**不检查是否已有进行中的训练**：「同时只可能有一场进行中」这条
/// 不变量由 `state/active_session_controller.dart` 的 `startNew` 单独把守
/// （它要先问用户「接着练还是结束它」）。绕过它直接调本函数，
/// 就会留下两场进行中的记录。
Future<WorkoutSession> createSession(
  SqlExecutor exec, {
  String? name,
  String? templateId,
}) async {
  final session = WorkoutSession(
    id: newId(),
    name: name,
    startedAt: DateTime.now().millisecondsSinceEpoch,
    finishedAt: null,
    note: null,
    templateId: templateId,
  );
  await exec.run(
    'INSERT INTO session (id, name, started_at, finished_at, note, template_id) VALUES (?, ?, ?, NULL, NULL, ?)',
    [session.id, session.name, session.startedAt, session.templateId],
  );
  return session;
}

/// 按 id 取一场训练。**进行中的那一场也能取到**（不像 [listSessions] 会滤掉）。
/// 总结页与历史详情页都走它。
Future<WorkoutSession?> getSession(SqlExecutor exec, String id) async {
  final row = await exec.first<Map<String, Object?>>(
    'SELECT $sessionColumns FROM session WHERE id = ?',
    [id],
  );
  return row == null ? null : toSession(SessionRow.fromMap(row));
}

/// 取当前进行中的训练。
///
/// 理论上同时只该有一条未结束的记录，但 App 被强杀可能留下残留，
/// 所以按开始时间倒序取最新的一条，**而不是断言唯一**。
///
/// `rowid DESC` 不能省：`started_at` 只有毫秒精度，同一毫秒建的两场会完全并列，
/// 此时 SQLite 按扫描顺序返回（先插入的在前），语义就反了。
Future<WorkoutSession?> getActiveSession(SqlExecutor exec) async {
  final row = await exec.first<Map<String, Object?>>(
    '''SELECT $sessionColumns FROM session
       WHERE finished_at IS NULL
       ORDER BY started_at DESC, rowid DESC
       LIMIT 1''',
  );
  return row == null ? null : toSession(SessionRow.fromMap(row));
}

/// 给训练写上结束时间，从此它出现在历史列表里。
///
/// 只写这一列，**不碰组记录** —— 训练结束时那些 `is_completed = 0` 的占位组
/// 就留在库里，靠这个标记被各处排除掉，不需要清理。
Future<void> finishSession(SqlExecutor exec, String id, int finishedAt) async {
  await exec.run('UPDATE session SET finished_at = ? WHERE id = ?', [finishedAt, id]);
}

/// 列出**已结束**的训练，最近的在前。
///
/// 「只列已结束」是刻意的：进行中的那一场归 [getActiveSession] 管，
/// `startNew` 复制上次动作组合时正是靠这个过滤，才不会把进行中的训练当成「上次」。
Future<List<WorkoutSession>> listSessions(SqlExecutor exec, int limit) async {
  final rows = await exec.all<Map<String, Object?>>(
    '''SELECT $sessionColumns FROM session
       WHERE finished_at IS NOT NULL
       ORDER BY started_at DESC, rowid DESC
       LIMIT ?''',
    [limit],
  );
  return rows.map((m) => toSession(SessionRow.fromMap(m))).toList();
}

/// 往训练里追加一个动作，`position` 取当前最大值 +1（第一个动作是 0）。
///
/// **不预建第一组** —— 那是 `ActiveSessionController.addExerciseWithFirstSet`
/// 的职责，因为它还要顺带沿用上次的重量 / 次数。只调本函数的话，
/// 界面上的「完成这组」会因为没有待完成的组而毫无反应。
Future<SessionExercise> addExerciseToSession(
  SqlExecutor exec,
  String sessionId,
  String exerciseId,
) async {
  final row = await exec.first<Map<String, Object?>>(
    'SELECT MAX(position) + 1 AS next FROM session_exercise WHERE session_id = ?',
    [sessionId],
  );
  final position = (row?['next'] as int?) ?? 0;

  final se = SessionExercise(
    id: newId(),
    sessionId: sessionId,
    exerciseId: exerciseId,
    position: position,
    note: null,
  );

  await exec.run(
    '''INSERT INTO session_exercise (id, session_id, exercise_id, position, note)
       VALUES (?, ?, ?, ?, NULL)''',
    [se.id, sessionId, exerciseId, position],
  );

  return se;
}

/// 取一场训练里的动作，按 `position` 升序（即界面上的先后）。
Future<List<SessionExercise>> listSessionExercises(
  SqlExecutor exec,
  String sessionId,
) async {
  final rows = await exec.all<Map<String, Object?>>(
    '''SELECT $sessionExerciseColumns FROM session_exercise
       WHERE session_id = ?
       ORDER BY position ASC''',
    [sessionId],
  );
  return rows.map((m) => toSessionExercise(SessionExerciseRow.fromMap(m))).toList();
}

/// 找出这场训练里**最近有动作的那一组**所属的 `session_exercise`。
///
/// 用途是恢复「练到第几个动作」：`completed_at` 最大的那一组就是用户最后碰过的
/// 那组，它归属的动作就是当时停下的地方。训练里没有「当前动作」这个字段，
/// 但这件事推得出来，**不值得为它加一列**。
///
/// 正在休息时结论相同 —— `startRest` 就是对刚 `completeSet` 的同一组调用的。
///
/// `st.rowid DESC` 不能省，理由同 [getActiveSession]。
Future<String?> findLastActiveSessionExerciseId(
  SqlExecutor exec,
  String sessionId,
) async {
  final row = await exec.first<Map<String, Object?>>(
    '''SELECT se.id AS id
         FROM set_entry st
         JOIN session_exercise se ON se.id = st.session_exercise_id
        WHERE se.session_id = ?
          AND st.completed_at IS NOT NULL
        ORDER BY st.completed_at DESC, st.rowid DESC
        LIMIT 1''',
    [sessionId],
  );
  return row?['id'] as String?;
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/data/session_repo_test.dart -v`
Expected: `All tests passed!`（10 个测试）

- [ ] **Step 5: 提交**

```bash
git add lib/data/repositories/session_repo.dart test/data/session_repo_test.dart
git commit -m "feat(data): 训练仓储，含 rowid 兜底与 resume 定位查询"
```

---

### Task 8: `set_repo.dart` —— 落盘的核心

**Files:**
- Create: `lib/data/repositories/set_repo.dart`
- Test: `test/data/set_repo_test.dart`

**Interfaces:**
- Consumes: `SqlExecutor`、`newId()`、`SetEntry`
- Produces:
  - `SetEntry toSetEntry(SetRow row)`
  - `const String setColumns` / `setColumnsPrefixed`
  - `Future<SetEntry> addSet(SqlExecutor exec, String sessionExerciseId, double weight, int reps)`
  - `Future<List<SetEntry>> listSets(SqlExecutor exec, String sessionExerciseId)`
  - `Future<void> updateSetValues(SqlExecutor exec, String setId, double weight, int reps)`
  - `Future<void> completeSet(SqlExecutor exec, String setId, int completedAt)`
  - `Future<void> startRest(SqlExecutor exec, String setId, int at)`
  - `Future<void> endRest(SqlExecutor exec, String setId, int at)`
  - `Future<void> cancelRest(SqlExecutor exec, String setId)`
  - `Future<List<SetEntry>> getLastPerformance(SqlExecutor exec, String exerciseId, String beforeSessionId)`

- [ ] **Step 1: 写失败的测试**

`test/data/set_repo_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/migrations.dart';
import 'package:gym_tracker/data/repositories/session_repo.dart';
import 'package:gym_tracker/data/repositories/set_repo.dart';

void main() {
  late FfiExecutor exec;
  late String sessionId;
  late String seId;

  setUp(() async {
    exec = await FfiExecutor.openInMemory();
    await migrate(exec);
    await exec.run(
      "INSERT INTO exercise (id, name, is_custom, is_archived, created_at) VALUES ('e1', '深蹲', 0, 0, 1)",
    );
    final s = await createSession(exec, name: null, templateId: null);
    sessionId = s.id;
    final se = await addExerciseToSession(exec, sessionId, 'e1');
    seId = se.id;
  });

  tearDown(() async => exec.close());

  test('新加的组是未完成的占位，position 从 0 起', () async {
    final a = await addSet(exec, seId, 20, 8);
    final b = await addSet(exec, seId, 20, 8);
    expect(a.isCompleted, isFalse);
    expect(a.position, 0);
    expect(b.position, 1);
    expect(a.restStartedAt, isNull);
    expect(a.completedAt, isNull);
  });

  test('listSets 含未完成的占位组，按 position 升序', () async {
    await addSet(exec, seId, 20, 8);
    final b = await addSet(exec, seId, 22.5, 8);
    await updateSetValues(exec, b.id, 25, 6);
    await completeSet(exec, b.id, 1000);
    final sets = await listSets(exec, seId);
    expect(sets, hasLength(2));
    expect(sets[0].isCompleted, isFalse);
    expect(sets[1].isCompleted, isTrue);
    expect(sets[1].weight, 25);
    expect(sets[1].reps, 6);
  });

  test('completeSet 记录 completed_at 并落盘', () async {
    final a = await addSet(exec, seId, 20, 8);
    await completeSet(exec, a.id, 1700000000000);
    final sets = await listSets(exec, seId);
    expect(sets.single.isCompleted, isTrue);
    expect(sets.single.completedAt, 1700000000000);
  });

  test('endRest 用时间戳相减算秒数，不写 rest_seconds 到别处', () async {
    final a = await addSet(exec, seId, 20, 8);
    await completeSet(exec, a.id, 1000);
    await startRest(exec, a.id, 1000000);
    await endRest(exec, a.id, 1090000); // 90 秒后

    final set = (await listSets(exec, seId)).single;
    expect(set.restSeconds, 90);
    expect(set.restStartedAt, isNull); // 休息结束，标记清掉
  });

  test('endRest 在该组本来就没在休息时静默返回，不写脏数据', () async {
    final a = await addSet(exec, seId, 20, 8);
    await completeSet(exec, a.id, 1000);
    await endRest(exec, a.id, 9999999); // 从没 startRest 过
    expect((await listSets(exec, seId)).single.restSeconds, isNull);
  });

  test('endRest 对不存在的 id 也不抛错', () async {
    await expectLater(endRest(exec, 'nope', 12345), completes);
  });

  test('cancelRest 清掉 rest_started_at，且**不写 rest_seconds**', () async {
    final a = await addSet(exec, seId, 20, 8);
    await completeSet(exec, a.id, 1000);
    await startRest(exec, a.id, 1000000);
    await cancelRest(exec, a.id);

    final set = (await listSets(exec, seId)).single;
    expect(set.restStartedAt, isNull);
    // ⭐ 关键：这段时长不是真实休息，不留下 ——
    // 否则一条 8 小时的记录会把休息建议的平均值彻底带偏
    expect(set.restSeconds, isNull);
  });

  test('getLastPerformance 从**更早的已结束**训练里取完成组', () async {
    // 上一场（已结束）
    await addSet(exec, seId, 40, 5);
    final prev = (await listSets(exec, seId)).single;
    await completeSet(exec, prev.id, 1000);
    await finishSession(exec, sessionId, 2000);

    // 这一场
    final s2 = await createSession(exec, name: null, templateId: null);
    final se2 = await addExerciseToSession(exec, s2.id, 'e1');

    final last = await getLastPerformance(exec, 'e1', s2.id);
    expect(last, hasLength(1));
    expect(last.single.weight, 40);
    expect(last.single.reps, 5);
  });

  test('getLastPerformance 排除本场自己', () async {
    final a = await addSet(exec, seId, 40, 5);
    await completeSet(exec, a.id, 1000);
    // 本场还没结束，所以它本身也不在「已结束」里；再加一场空的来确认返回值
    final last = await getLastPerformance(exec, 'e1', sessionId);
    expect(last, isEmpty);
  });

  test('getLastPerformance 从没练过时返回空数组（不是 null）', () async {
    expect(await getLastPerformance(exec, 'e1', sessionId), isEmpty);
  });

  test('getLastPerformance 只取最近一次训练，不混更早的', () async {
    // 更早的一场
    await addSet(exec, seId, 30, 5);
    final old = (await listSets(exec, seId)).single;
    await completeSet(exec, old.id, 1000);
    await finishSession(exec, sessionId, 2000);

    // 更近的一场
    final s2 = await createSession(exec, name: null, templateId: null);
    final se2 = await addExerciseToSession(exec, s2.id, 'e1');
    final b = await addSet(exec, se2.id, 50, 3);
    await completeSet(exec, b.id, 3000);
    await finishSession(exec, s2.id, 4000);

    // 这一场
    final s3 = await createSession(exec, name: null, templateId: null);

    final last = await getLastPerformance(exec, 'e1', s3.id);
    expect(last, hasLength(1));
    expect(last.single.weight, 50); // 只认最近那场，不是 30
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/data/set_repo_test.dart`
Expected: FAIL —— `set_repo.dart` 不存在

- [ ] **Step 3: 实现 `lib/data/repositories/set_repo.dart`**

```dart
import '../../domain/types.dart';
import '../db/sql_executor.dart';
import 'seed.dart';

/// `set_entry` 表的原始行。
class SetRow {
  final String id;
  final String session_exercise_id;
  final int position;
  final double weight;
  final int reps;
  final int is_completed;
  final int? rest_seconds;
  final int? rest_started_at;
  final int? completed_at;

  const SetRow({required this.id, required this.session_exercise_id,
    required this.position, required this.weight, required this.reps,
    required this.is_completed, this.rest_seconds, this.rest_started_at,
    this.completed_at});

  factory SetRow.fromMap(Map<String, Object?> m) => SetRow(
        id: m['id'] as String,
        session_exercise_id: m['session_exercise_id'] as String,
        position: m['position'] as int,
        weight: (m['weight'] as num).toDouble(),
        reps: m['reps'] as int,
        is_completed: m['is_completed'] as int,
        rest_seconds: m['rest_seconds'] as int?,
        rest_started_at: m['rest_started_at'] as int?,
        completed_at: m['completed_at'] as int?,
      );
}

/// `is_completed` 的 0/1 在这里还原成布尔。
SetEntry toSetEntry(SetRow row) => SetEntry(
      id: row.id,
      sessionExerciseId: row.session_exercise_id,
      position: row.position,
      weight: row.weight,
      reps: row.reps,
      isCompleted: row.is_completed == 1,
      restSeconds: row.rest_seconds,
      restStartedAt: row.rest_started_at,
      completedAt: row.completed_at,
    );

const String setColumns =
    'id, session_exercise_id, position, weight, reps, is_completed, rest_seconds, rest_started_at, completed_at';

/// 与 [setColumns] 同一组列，但带 `st.` 前缀。
///
/// `set_entry` 与 `session_exercise` 都有 `id` 和 `position`，凡是 JOIN 了
/// `session_exercise` 的查询都必须用带前缀的版本，否则 SQLite 直接报
/// `ambiguous column name: id`（实测：prepare 阶段就抛，不是取数阶段）。
const String setColumnsPrefixed =
    'st.id, st.session_exercise_id, st.position, st.weight, st.reps, st.is_completed, st.rest_seconds, st.rest_started_at, st.completed_at';

/// 追加一组，`position` 取当前最大值 +1（第一组是 0）。
///
/// 新建出来的组**一律未完成** —— 它是界面上的「下一组」占位。
/// 「完成即落盘」的两步（[updateSetValues] → [completeSet]）发生在用户点完成时。
///
/// [sessionExerciseId] 是 **`session_exercise.id`，不是 `exercise.id`**。
Future<SetEntry> addSet(
  SqlExecutor exec,
  String sessionExerciseId,
  double weight,
  int reps,
) async {
  final row = await exec.first<Map<String, Object?>>(
    'SELECT MAX(position) + 1 AS next FROM set_entry WHERE session_exercise_id = ?',
    [sessionExerciseId],
  );
  final position = (row?['next'] as int?) ?? 0;

  final set = SetEntry(
    id: newId(),
    sessionExerciseId: sessionExerciseId,
    position: position,
    weight: weight,
    reps: reps,
    isCompleted: false,
  );

  await exec.run(
    '''INSERT INTO set_entry
         (id, session_exercise_id, position, weight, reps, is_completed, rest_seconds, rest_started_at, completed_at)
       VALUES (?, ?, ?, ?, ?, 0, NULL, NULL, NULL)''',
    [set.id, sessionExerciseId, position, weight, reps],
  );

  return set;
}

/// 取某个动作（在这一场里）的全部组，**含未完成的占位组** ——
/// 界面正需要那条占位来确定「当前该记哪一组」。
Future<List<SetEntry>> listSets(SqlExecutor exec, String sessionExerciseId) async {
  final rows = await exec.all<Map<String, Object?>>(
    '''SELECT $setColumns FROM set_entry
       WHERE session_exercise_id = ?
       ORDER BY position ASC''',
    [sessionExerciseId],
  );
  return rows.map((m) => toSetEntry(SetRow.fromMap(m))).toList();
}

/// 改写某一组的重量与次数。
///
/// 记录界面在「完成这一组」时会**先**把用户当前填的数值写进来，**再**标记完成
/// —— 顺序反过来的话，中途失败就会留下一条「已完成但数值是旧的」的记录。
Future<void> updateSetValues(
  SqlExecutor exec,
  String setId,
  double weight,
  int reps,
) async {
  await exec.run('UPDATE set_entry SET weight = ?, reps = ? WHERE id = ?',
      [weight, reps, setId]);
}

/// 标记一组已完成。**这一步必须立刻落盘** —— 训练记录的全部价值就在于不丢，
/// 不能等训练结束再统一保存。
///
/// [completedAt] 由调用方传入，与休息计时共用同一个 now，
/// 保证「完成时刻」和「休息开始时刻」不差毫秒。
Future<void> completeSet(SqlExecutor exec, String setId, int completedAt) async {
  await exec.run(
    'UPDATE set_entry SET is_completed = 1, completed_at = ? WHERE id = ?',
    [completedAt, setId],
  );
}

/// 开始休息计时：**只记时间戳**，之后用「现在 − 这个时间戳」算时长。
Future<void> startRest(SqlExecutor exec, String setId, int at) async {
  await exec.run('UPDATE set_entry SET rest_started_at = ? WHERE id = ?', [at, setId]);
}

/// 结束休息计时，写入这段休息的秒数。
///
/// **必须基于 `rest_started_at` 做时间戳相减，而不是用计数器累加** ——
/// App 被系统挂起后计数器会停，时间戳不会。旧项目真机实测：息屏前 `18:20`，
/// 息屏 35 秒后 `19:01`（Δ41 秒 vs 实测等待 40 秒，吻合）。
///
/// 该组本来就没在休息时**静默返回**（不写、不抛）——
/// 界面重复点「开始下一组」不会留下脏数据。
Future<void> endRest(SqlExecutor exec, String setId, int at) async {
  final row = await exec.first<Map<String, Object?>>(
    'SELECT rest_started_at FROM set_entry WHERE id = ?',
    [setId],
  );
  final startedAt = row?['rest_started_at'] as int?;
  if (row == null || startedAt == null) return;

  final seconds = ((at - startedAt) / 1000).round();
  await exec.run(
    'UPDATE set_entry SET rest_seconds = ?, rest_started_at = NULL WHERE id = ?',
    [seconds < 0 ? 0 : seconds, setId],
  );
}

/// 放弃一段休息：清掉 `rest_started_at`，**且不写入 `rest_seconds`**。
///
/// 用于「这段休息跑了太久，显然是忘了按开始下一组」的情况。它和 [endRest]
/// 的区别是刻意的：**那种时长不是真实休息，不该作为数据留下来** ——
/// 休息建议规则要算平均休息时长，一条 8 小时的记录足以把平均值彻底带偏。
Future<void> cancelRest(SqlExecutor exec, String setId) async {
  await exec.run('UPDATE set_entry SET rest_started_at = NULL WHERE id = ?', [setId]);
}

/// 取某个动作在**更早的某一次训练**里的完成组，用于显示「上次练了多少」。
///
/// 只取最近一次有该动作的训练：更早的数据对「这次该加多少」没有参考价值，
/// 混在一起反而会干扰。
///
/// **`s.rowid DESC` 这个并列项不能省。** `started_at` 只有毫秒精度，两场训练
/// 完全可能落在同一毫秒里；此时只写 `ORDER BY s.started_at DESC`，SQLite 会按
/// 扫描顺序返回，也就是**先插入的那一场** —— 正是「更早」的那一场，
/// 语义整个反了。
///
/// 从没练过时返回**空数组**，调用方据此回退到默认重量。
Future<List<SetEntry>> getLastPerformance(
  SqlExecutor exec,
  String exerciseId,
  String beforeSessionId,
) async {
  final previous = await exec.first<Map<String, Object?>>(
    '''SELECT s.id AS id
         FROM session s
         JOIN session_exercise se ON se.session_id = s.id
        WHERE se.exercise_id = ?
          AND s.id <> ?
          AND s.finished_at IS NOT NULL
        ORDER BY s.started_at DESC, s.rowid DESC
        LIMIT 1''',
    [exerciseId, beforeSessionId],
  );

  final previousId = previous?['id'] as String?;
  if (previousId == null) return [];

  final rows = await exec.all<Map<String, Object?>>(
    '''SELECT $setColumnsPrefixed
         FROM set_entry st
         JOIN session_exercise se ON se.id = st.session_exercise_id
        WHERE se.exercise_id = ?
          AND se.session_id = ?
          AND st.is_completed = 1
        ORDER BY st.position ASC''',
    [exerciseId, previousId],
  );

  return rows.map((m) => toSetEntry(SetRow.fromMap(m))).toList();
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/data/set_repo_test.dart -v`
Expected: `All tests passed!`（11 个测试）

- [ ] **Step 5: 提交**

```bash
git add lib/data/repositories/set_repo.dart test/data/set_repo_test.dart
git commit -m "feat(data): 组记录仓储 —— 完成即落盘四步、时间戳休息、cancelRest"
```

---

### Task 9: `settings_repo.dart` + 主题模式

**Files:**
- Create: `lib/data/repositories/settings_repo.dart`
- Test: `test/data/settings_repo_test.dart`

**Interfaces:**
- Consumes: `SqlExecutor`
- Produces:
  - `enum AppThemeMode { system, light, dark }`
  - `const String themeModeKey`
  - `Future<String?> getSetting(SqlExecutor exec, String key)`
  - `Future<void> setSetting(SqlExecutor exec, String key, String value)`
  - `Future<AppThemeMode> getThemeMode(SqlExecutor exec)`
  - `Future<void> setThemeMode(SqlExecutor exec, AppThemeMode mode)`

- [ ] **Step 1: 写失败的测试**

`test/data/settings_repo_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/migrations.dart';
import 'package:gym_tracker/data/repositories/settings_repo.dart';

void main() {
  late FfiExecutor exec;

  setUp(() async {
    exec = await FfiExecutor.openInMemory();
    await migrate(exec);
  });

  tearDown(() async => exec.close());

  test('没设置过时返回 null（不是空串 —— 两者必须能区分）', () async {
    expect(await getSetting(exec, 'nope'), isNull);
  });

  test('写入后能读回', () async {
    await setSetting(exec, 'k', 'v');
    expect(await getSetting(exec, 'k'), 'v');
  });

  test('空串是一个合法的、被显式写入过的值', () async {
    await setSetting(exec, 'k', '');
    expect(await getSetting(exec, 'k'), '');
  });

  test('重复写同一个键是覆盖，不是插入第二行', () async {
    await setSetting(exec, 'k', 'a');
    await setSetting(exec, 'k', 'b');
    expect(await getSetting(exec, 'k'), 'b');
    final rows = await exec.all("SELECT * FROM app_setting WHERE key = 'k'");
    expect(rows, hasLength(1));
  });

  test('没设置过主题 → 默认跟随系统', () async {
    expect(await getThemeMode(exec), AppThemeMode.system);
  });

  test('主题存进去能读回来', () async {
    await setThemeMode(exec, AppThemeMode.dark);
    expect(await getThemeMode(exec), AppThemeMode.dark);
    await setThemeMode(exec, AppThemeMode.light);
    expect(await getThemeMode(exec), AppThemeMode.light);
  });

  test('库里存了非法值 → 退回 system，而不是抛错', () async {
    // 主题读不出来不该让整个 App 起不来
    await setSetting(exec, themeModeKey, 'neon-pink');
    expect(await getThemeMode(exec), AppThemeMode.system);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/data/settings_repo_test.dart`
Expected: FAIL —— `settings_repo.dart` 不存在

- [ ] **Step 3: 实现 `lib/data/repositories/settings_repo.dart`**

```dart
import '../db/sql_executor.dart';

/// 主题模式在 `app_setting` 里的键名。英文键名，与 `schema_version` 保持一致。
const String themeModeKey = 'theme_mode';

/// 主题模式。
///
/// **三态而不是布尔。** 布尔（深色 / 浅色）表达不了「跟随系统」—— 那才是
/// 默认行为，也是大多数用户想要的。用户一进设置页看到的是「跟随系统」被选中，
/// 而不是被迫在两种颜色里挑一个。
enum AppThemeMode { system, light, dark }

/// 读一个设置项。
///
/// **键不存在时返回 null**（不是空串 —— 空串是一个合法的、被显式写入过的值，
/// 两者必须能区分）。
Future<String?> getSetting(SqlExecutor exec, String key) async {
  final row = await exec.first<Map<String, Object?>>(
    'SELECT value FROM app_setting WHERE key = ?',
    [key],
  );
  return row?['value'] as String?;
}

/// 写一个设置项。键已存在则覆盖。
///
/// 用 `ON CONFLICT ... DO UPDATE` 而不是「先删再插」：后者在两个 await 之间
/// 被打断会留下「键没了」的中间状态，而这个键丢了界面会退回默认主题，
/// 用户看到的是自己刚设的偏好莫名消失。
Future<void> setSetting(SqlExecutor exec, String key, String value) async {
  await exec.run(
    '''INSERT INTO app_setting (key, value) VALUES (?, ?)
       ON CONFLICT(key) DO UPDATE SET value = excluded.value''',
    [key, value],
  );
}

/// 读主题模式。
///
/// **没设置过、或库里存的是个非法值时一律返回 [AppThemeMode.system]。**
/// 非法值不当错误抛出：主题读不出来不该让整个 App 起不来，
/// 退回默认跟随系统是唯一合理的降级。
Future<AppThemeMode> getThemeMode(SqlExecutor exec) async {
  final stored = await getSetting(exec, themeModeKey);
  for (final mode in AppThemeMode.values) {
    if (mode.name == stored) return mode;
  }
  return AppThemeMode.system;
}

Future<void> setThemeMode(SqlExecutor exec, AppThemeMode mode) =>
    setSetting(exec, themeModeKey, mode.name);
```

> 旧项目还导出 `THEME_MODES`（合法取值列表，同时是设置页按钮顺序）。
> Dart 的 `AppThemeMode.values` 天然就是这个列表，**不要重复定义**。

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/data/settings_repo_test.dart -v`
Expected: `All tests passed!`（7 个测试）

- [ ] **Step 5: 跑全部测试，确认分层守卫仍然绿色**

Run: `flutter test`
Expected: `All tests passed!`

此时全量总数预期约 **93 条**：

| 来源 | 条数 | 状态 |
|---|---|---|
| `test/smoke/database_smoke_test.dart` | 2 | ✅ 实测 |
| Task 1（metrics 9 + rest 7） | 16 | ✅ 实测 |
| Task 2（rest_advice） | 10 | ✅ 实测 |
| Task 3（format 13 + session_label 5） | 18 | ✅ 实测 |
| Task 4（layering） | 5 | 待做 |
| Task 5（migrations） | 6 | 待做 |
| Task 6（exercise_repo） | 8 | 待做 |
| Task 7（session_repo） | 10 | 待做 |
| Task 8（set_repo） | 11 | 待做 |
| Task 9（settings_repo） | 7 | 待做 |
| **合计** | **约 93** | |

> **条数只是参考，不是判据。** 计划初版给的几个数字（8 / 15 / 39 / 86）有误，
> 已按实际修正 —— 但真正的判据永远是「全绿」，不是「等于某个数」。
> 若条数对不上，先看**是不是有测试被跳过或没被执行**，而不是去凑数字。

- [ ] **Step 6: 提交**

```bash
git add lib/data/repositories/settings_repo.dart test/data/settings_repo_test.dart
git commit -m "feat(data): 设置仓储与主题三态，非法值退回 system"
```

---

## 里程碑 C：编排层

### Task 10: `ActiveSessionController` —— resume / startNew / addExercise

**Files:**
- Create: `lib/state/active_session_controller.dart`
- Test: `test/state/active_session_controller_test.dart`

**Interfaces:**
- Consumes: 全部四个仓储
- Produces:
  - `enum StartResult { started, conflict }`
  - `class ActiveExercise { SessionExercise sessionExercise; String exerciseName; List<SetEntry> sets; }`
  - `class ActiveSessionController extends ChangeNotifier`，字段与方法见规格 §5.2：
    - `bool loading` / `WorkoutSession? session` / `List<ActiveExercise> exercises` / `int currentIndex`
    - `Future<bool> resume()`
    - `Future<StartResult> startNew({String? name})`
    - `Future<void> addExercise(String exerciseId)`
    - `void setCurrentIndex(int index)`
    - `Future<void> completeCurrentSet(double weight, int reps)`
    - `Future<void> beginNextSet()`
    - `Future<String?> endWorkout()`
    - `void reset()`

> **与旧实现的一处简化**：旧版的每个方法都收一个 `exec` 参数，原因是「store 在
> React 之外，拿不到 Context」。Flutter 没这个限制 ——
> **在构造函数注入 `SqlExecutor`**，调用签名更干净。

- [ ] **Step 1: 写失败的测试 —— resume 与冲突**

`test/state/active_session_controller_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/migrations.dart';
import 'package:gym_tracker/data/repositories/exercise_repo.dart';
import 'package:gym_tracker/data/repositories/session_repo.dart';
import 'package:gym_tracker/data/repositories/set_repo.dart';
import 'package:gym_tracker/state/active_session_controller.dart';

void main() {
  late FfiExecutor exec;
  late String squatId;
  late String benchId;

  setUp(() async {
    exec = await FfiExecutor.openInMemory();
    await migrate(exec);
    squatId = (await createCustomExercise(exec, name: '深蹲', muscleGroup: '腿')).id;
    benchId = (await createCustomExercise(exec, name: '卧推', muscleGroup: '胸')).id;
  });

  tearDown(() async => exec.close());

  ActiveSessionController make() => ActiveSessionController(exec);

  test('没有进行中的训练时 resume 返回 false，store 保持原样', () async {
    final c = make();
    expect(await c.resume(), isFalse);
    expect(c.session, isNull);
    expect(c.exercises, isEmpty);
  });

  test('startNew 建出一场进行中的训练', () async {
    final c = make();
    expect(await c.startNew(), StartResult.started);
    expect(c.session, isNotNull);
    expect(c.session!.finishedAt, isNull);
  });

  test('第一次用 App（无历史）时开一场空训练，不崩', () async {
    final c = make();
    await c.startNew();
    expect(c.exercises, isEmpty);
    expect(c.currentIndex, 0);
  });

  test('⭐ 已有进行中的训练时 startNew 返回 conflict，且不新建第二条', () async {
    final c = make();
    await c.startNew();
    final firstId = c.session!.id;

    final c2 = make();
    expect(await c2.startNew(), StartResult.conflict);
    // 库里仍然只有一条未结束的
    final rows = await exec.all("SELECT * FROM session WHERE finished_at IS NULL");
    expect(rows, hasLength(1));
    expect((await getActiveSession(exec))!.id, firstId);
  });

  test('⭐ conflict 时那一场必须已被装进 store（否则「接着练」进到空屏）', () async {
    final c = make();
    await c.startNew();
    await c.addExercise(squatId);

    final c2 = make();
    await c2.startNew();
    expect(c2.session, isNotNull);
    expect(c2.exercises, hasLength(1));
    expect(c2.exercises.single.exerciseName, '深蹲');
  });

  test('startNew 复制上一次已结束训练的动作组合与顺序', () async {
    final c = make();
    await c.startNew();
    await c.addExercise(squatId);
    await c.addExercise(benchId);
    await c.endWorkout();

    final c2 = make();
    await c2.startNew();
    expect(c2.exercises.map((e) => e.exerciseName).toList(), ['深蹲', '卧推']);
  });

  test('startNew 复制的是**最近一场已结束**训练的动作组合', () async {
    // 第一场：深蹲，已结束
    final c = make();
    await c.startNew();
    await c.addExercise(squatId);
    await c.endWorkout();

    // 第二场：从第一场复制来深蹲，再加卧推，然后结束它
    final c2 = make();
    await c2.startNew();
    expect(c2.exercises.map((e) => e.exerciseName).toList(), ['深蹲']);
    await c2.addExercise(benchId);
    await c2.endWorkout();

    // 第三场应复制第二场（最近一场已结束），而不是第一场
    final c3 = make();
    await c3.startNew();
    expect(c3.exercises.map((e) => e.exerciseName).toList(), ['深蹲', '卧推']);
  });

  test('进行中的那一场不会被当成「上一次」', () async {
    // 只造一场**没结束**的训练，里面已经有动作
    final c = make();
    await c.startNew();
    await c.addExercise(squatId);

    // listSessions 只返回已结束的 —— 它是「上一次」的唯一来源，
    // 所以此刻「上一次」必须是空的
    expect(await listSessions(exec, 1), isEmpty);
  });

  test('⭐ addExercise 必须预建第一组（否则「完成这组」是静默假死按钮）', () async {
    final c = make();
    await c.startNew();
    await c.addExercise(squatId);

    final sets = c.exercises.single.sets;
    expect(sets, hasLength(1));
    expect(sets.single.isCompleted, isFalse);
  });

  test('新动作的第一组预填上次成绩；从没练过时用默认值 20kg × 8', () async {
    final c = make();
    await c.startNew();
    await c.addExercise(squatId);
    final sets = c.exercises.single.sets;
    expect(sets.single.weight, 20);
    expect(sets.single.reps, 8);
  });

  test('addExercise 后 currentIndex 跳到新加的那个动作', () async {
    final c = make();
    await c.startNew();
    await c.addExercise(squatId);
    await c.addExercise(benchId);
    expect(c.currentIndex, 1);
  });

  test('resume 恢复练到第几个动作（按 completed_at 最大的那组推导）', () async {
    final c = make();
    await c.startNew();
    await c.addExercise(squatId);
    await c.addExercise(benchId);
    // 在第二个动作上完成一组
    c.setCurrentIndex(1);
    await c.completeCurrentSet(60, 8);

    // 模拟强杀重开
    final c2 = make();
    expect(await c2.resume(), isTrue);
    expect(c2.currentIndex, 1);
    expect(c2.exercises[1].sets.where((s) => s.isCompleted), hasLength(1));
  });

  test('resume 时一组都没完成过 → currentIndex 为 0', () async {
    final c = make();
    await c.startNew();
    await c.addExercise(squatId);
    await c.addExercise(benchId);

    final c2 = make();
    await c2.resume();
    expect(c2.currentIndex, 0);
  });

  test('⭐ 30 分钟闸门：resume 时清掉跑过头的休息，且不写 rest_seconds', () async {
    final c = make();
    await c.startNew();
    await c.addExercise(squatId);
    await c.completeCurrentSet(20, 8);

    // 手工把休息开始时间推到 40 分钟前
    final longAgo = DateTime.now().millisecondsSinceEpoch - 40 * 60 * 1000;
    await exec.run('UPDATE set_entry SET rest_started_at = ?', [longAgo]);

    final c2 = make();
    await c2.resume();
    final set = c2.exercises.single.sets.firstWhere((s) => s.isCompleted);
    expect(set.restStartedAt, isNull);
    // 关键：这段荒唐时长不能被记成真实休息
    expect(set.restSeconds, isNull);
  });

  test('训练已结束时 addExercise 静默返回（防御性闸门）', () async {
    final c = make();
    await c.startNew();
    await c.endWorkout();
    // 正常路径下 endWorkout 已清空 store，这里手工把已结束的塞回去
    // 来验证闸门 —— 旧项目那个「同一场被接上第二次」的 bug 就是这么来的
    await c.addExercise(squatId);
    expect(c.exercises, isEmpty);
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/state/active_session_controller_test.dart`
Expected: FAIL —— `active_session_controller.dart` 不存在

- [ ] **Step 3: 实现 `lib/state/active_session_controller.dart`**

```dart
import 'package:flutter/foundation.dart';

import '../data/db/sql_executor.dart';
import '../data/repositories/exercise_repo.dart';
import '../data/repositories/session_repo.dart';
import '../data/repositories/set_repo.dart';
import '../domain/rest.dart';
import '../domain/types.dart';

const double defaultWeightKg = 20;
const int defaultReps = 8;

/// [ActiveSessionController.startNew] 的两种结果。
///
/// `conflict` 表示库里已经有一场进行中的训练，此时**没有**新建任何东西，
/// 那一场已经装进 controller —— 界面据此问用户「接着练还是结束它」。
enum StartResult { started, conflict }

/// 记录界面上的一个动作卡片：动作本身 + 展示用的名字 + 它的全部组。
///
/// 名字在这里就查好了（而不是让界面自己去 `getExercise`），因为本来就
/// 要为「上次练了多少」查一次库，顺手带上不额外花钱。
class ActiveExercise {
  /// 这一场里的动作记录 —— **`sets` 里的组引用的是它的 id**
  final SessionExercise sessionExercise;

  /// 动作名；动作被删 / 查不到时是「未知动作」
  final String exerciseName;

  /// 该动作的全部组，含界面上那条未完成的占位组
  final List<SetEntry> sets;

  const ActiveExercise({
    required this.sessionExercise,
    required this.exerciseName,
    required this.sets,
  });

  ActiveExercise copyWith({List<SetEntry>? sets}) => ActiveExercise(
        sessionExercise: sessionExercise,
        exerciseName: exerciseName,
        sets: sets ?? this.sets,
      );

  /// 给 `domain/session_label.dart` 用 —— 它只认动作名与每组的完成状态。
  ExerciseProgress get progress => ExerciseProgress(
        exerciseName: exerciseName,
        sets: sets.map((s) => SetProgress(isCompleted: s.isCompleted)).toList(),
      );
}

/// 当前训练的全部状态与操作。
///
/// 这一层是**唯一**允许判定「能不能改这场训练」的地方（每个写操作都先查
/// `finishedAt != null`）—— 界面只管调，不用自己判断训练是否已结束。
///
/// 状态**只存在内存里**，每个写操作都立刻落库，App 重启后靠 [resume]
/// 从库重建。刻意不做持久化：真相来源只留 SQLite 一份，
/// 两处都能改状态必然对不上。
class ActiveSessionController extends ChangeNotifier {
  final SqlExecutor _exec;

  ActiveSessionController(this._exec);

  /// 正在从库里载入（[resume] 期间为 true），界面据此显示加载态
  bool loading = false;
  WorkoutSession? session;
  List<ActiveExercise> exercises = [];
  int currentIndex = 0;

  /// 载入未结束的训练；没有就返回 false。
  Future<bool> resume() async {
    loading = true;
    notifyListeners();
    try {
      final found = await getActiveSession(_exec);
      if (found == null) return false;
      final loaded = await _loadExercises(found.id);
      session = found;
      exercises = loaded;
      currentIndex = await _resolveCurrentIndex(found.id, loaded);
      return true;
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  /// 开一场新训练。
  ///
  /// 库里已经有一场进行中的训练时**不新建**，返回 [StartResult.conflict]
  /// 并把那一场装进 controller 交回界面。这是「同时只可能有一场进行中的训练」
  /// 这条不变量**唯一的守门人**。
  ///
  /// Phase 1 的动作来源是「复制上一次**已结束**训练的动作组合」；
  /// 分化计划的轮转留到后续 Phase，但**调用顺序现在就遵守**（见下）。
  Future<StartResult> startNew({String? name}) async {
    // 复用 resume 而不是另写一次查询：它会把那一场连动作带组一起装进
    // controller，界面选「接着练」时直接导航过去就有东西可渲染 ——
    // 只返回一个 id 的话，记录页会因为 controller 里没有 exercises
    // 而误判成「这次训练还没有动作」。
    if (await resume()) return StartResult.conflict;

    // 顺序不能反：**先探冲突（上面那行）→ 再定计划 → 才建 session**。
    // 轮转的输入是「最近一场已结束训练用的模板」，先建出来的话这一场虽然
    // finished_at 还是 NULL、不会污染那个查询，但「先建后定」很容易在后续
    // 改动里被误用 listSessions 之类的接口把这一场算进去。
    final created = await createSession(_exec, name: name, templateId: null);

    // listSessions 只返回已结束的，所以天然不会复制到一场还在进行中的训练
    final previousIds = await _previousSessionExerciseIds();
    for (final exerciseId in previousIds) {
      await _addExerciseWithFirstSet(created.id, exerciseId);
    }

    session = created;
    exercises = await _loadExercises(created.id);
    currentIndex = 0;
    notifyListeners();
    return StartResult.started;
  }

  /// 往训练里加一个动作。
  Future<void> addExercise(String exerciseId) async {
    final current = session;
    // 已结束的训练不能再往里加东西。正常路径下 endWorkout 已经清空 controller、
    // session 为 null，这里挡的是「有人把一场已结束的训练塞回 controller」——
    // 旧项目那个「同一场训练被接上第二次、第三次」的 bug 就是这么来的。
    if (current == null || current.finishedAt != null) return;

    await _addExerciseWithFirstSet(current.id, exerciseId);

    exercises = await _loadExercises(current.id);
    currentIndex = exercises.length - 1;
    notifyListeners();
  }

  /// 切换当前正在记录的动作。**不写数据库** —— 它是纯界面状态。
  void setCurrentIndex(int index) {
    currentIndex = index;
    notifyListeners();
  }

  // ── 以下为私有实现 ──────────────────────────────────────────────

  /// 把一场训练的动作与组全部读出来。
  ///
  /// 这里还兼任一道闸门：**收拾掉跑过头的休息**。做完一组后如果一直没按
  /// 「开始下一组」（直接关掉 App 走了、或者第二天才打开），`rest_started_at`
  /// 会一直留着。不处理的话有两个后果 —— 重开 App 会被堵在休息页出不来，
  /// 以及这段荒唐的时长会作为 `rest_seconds` 存进库，把休息建议的平均值
  /// 彻底带偏。
  ///
  /// 放在这里而不是各个入口分别处理，是因为 resume / startNew / addExercise /
  /// endWorkout 全都会经过它，**一处覆盖全部**。
  Future<List<ActiveExercise>> _loadExercises(String sessionId) async {
    final sessionExercises = await listSessionExercises(_exec, sessionId);
    final now = DateTime.now().millisecondsSinceEpoch;
    final result = <ActiveExercise>[];

    for (final se in sessionExercises) {
      final exercise = await getExercise(_exec, se.exerciseId);
      var sets = await listSets(_exec, se.id);

      final stale = findStaleRest(sets, now);
      if (stale != null) {
        await cancelRest(_exec, stale.id);
        sets = await listSets(_exec, se.id);
      }

      result.add(ActiveExercise(
        sessionExercise: se,
        exerciseName: exercise?.name ?? '未知动作',
        sets: sets,
      ));
    }
    return result;
  }

  /// 算出「上次停在第几个动作」，用来恢复记录界面的位置。
  ///
  /// 训练里没有「当前动作」这个字段，但推得出来：`completed_at` 最大的那一组
  /// 就是用户最后碰过的组。**纯查询，不加字段、不做迁移。**
  ///
  /// 正在休息的情况自动落在同一个答案上（`startRest` 就是对刚 `completeSet`
  /// 的同一组调用的），不需要第二条判定。
  ///
  /// 已知不精确、明确接受：切到第 4 个动作但一组都没做就被杀 →
  /// 会回到第 3 个动作。
  ///
  /// `索引夹到 0` 兜住 findIndex 返回 -1 的情况：直接拿去当 currentIndex
  /// 会让记录页取到 `exercises[-1]`，一片空白。
  Future<int> _resolveCurrentIndex(
    String sessionId,
    List<ActiveExercise> loaded,
  ) async {
    final lastActiveId = await findLastActiveSessionExerciseId(_exec, sessionId);
    if (lastActiveId == null) return 0;
    final index = loaded.indexWhere((e) => e.sessionExercise.id == lastActiveId);
    return index < 0 ? 0 : index;
  }

  /// 「上一次练了哪些动作」—— 没有计划时唯一的动作来源。
  ///
  /// [listSessions] 只返回**已结束**的训练，所以这里天然不会把一场还在
  /// 进行中的训练当成「上一次」。没有历史（第一次用）时返回空数组。
  Future<List<String>> _previousSessionExerciseIds() async {
    final previous = await listSessions(_exec, 1);
    if (previous.isEmpty) return [];
    final list = await listSessionExercises(_exec, previous.first.id);
    return list.map((e) => e.exerciseId).toList();
  }

  /// 往训练里加一个动作，并预建它的第一组。
  ///
  /// **预建第一组不是可选项。** 记录界面靠「还没完成的那一组」来确定当前该记
  /// 哪一组，没有这条待完成的记录，[completeCurrentSet] 会直接 return，
  /// **用户点「完成这组」会毫无反应 —— 一个静默的假死按钮。**
  ///
  /// 重量 / 次数沿用上一次练这个动作的第一组，没有历史时用默认值兜底。
  ///
  /// 抽成私有函数是为了让 [startNew] 和 [addExercise] 共用同一条路径。
  /// 两处各写一遍必然漂移，而漂移的后果正是上面那个「按钮没反应」。
  Future<void> _addExerciseWithFirstSet(
    String sessionId,
    String exerciseId,
  ) async {
    final se = await addExerciseToSession(_exec, sessionId, exerciseId);
    final last = await getLastPerformance(_exec, exerciseId, sessionId);
    final template = last.isEmpty ? null : last.first;
    await addSet(
      _exec,
      se.id,
      template?.weight ?? defaultWeightKg,
      template?.reps ?? defaultReps,
    );
  }
}
```

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/state/active_session_controller_test.dart -v`
Expected: 除 `completeCurrentSet` / `endWorkout` 相关外全部 PASS。后两个方法在 Task 11 实现 —— **为了让本 Task 能独立跑绿，先在类里加上它们的空实现**（`Future<void> completeCurrentSet(...) async {}` 与 `Future<String?> endWorkout() async => null;`），Task 11 再填实。

- [ ] **Step 5: 提交**

```bash
git add lib/state test/state
git commit -m "feat(state): 编排层 resume / startNew / addExercise，冲突不新建且装满 store"
```

---

### Task 11: `ActiveSessionController` —— 完成一组 / 休息 / 结束

**Files:**
- Modify: `lib/state/active_session_controller.dart`（填实 Task 10 留下的两个空实现）
- Test: `test/state/complete_set_test.dart`

**Interfaces:**
- Consumes: Task 10 的 `ActiveSessionController`
- Produces: `completeCurrentSet` / `beginNextSet` / `endWorkout` / `reset` 的完整实现

- [ ] **Step 1: 写失败的测试**

`test/state/complete_set_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/migrations.dart';
import 'package:gym_tracker/data/repositories/exercise_repo.dart';
import 'package:gym_tracker/data/repositories/session_repo.dart';
import 'package:gym_tracker/data/repositories/set_repo.dart';
import 'package:gym_tracker/state/active_session_controller.dart';

void main() {
  late FfiExecutor exec;
  late String squatId;

  setUp(() async {
    exec = await FfiExecutor.openInMemory();
    await migrate(exec);
    squatId = (await createCustomExercise(exec, name: '深蹲', muscleGroup: '腿')).id;
  });

  tearDown(() async => exec.close());

  Future<ActiveSessionController> started() async {
    final c = ActiveSessionController(exec);
    await c.startNew();
    await c.addExercise(squatId);
    return c;
  }

  test('⭐ 完成一组立刻落盘（不是等训练结束才写）', () async {
    final c = await started();
    await c.completeCurrentSet(40, 8);

    final seId = c.exercises.single.sessionExercise.id;
    final stored = await listSets(exec, seId);
    expect(stored.where((s) => s.isCompleted), hasLength(1));
    expect(stored.singleWhere((s) => s.isCompleted).weight, 40);
  });

  test('⭐ 落盘的是用户此刻填的值，不是组里的旧值', () async {
    final c = await started();
    // 占位组初始是 20×8，用户改成 42.5×6
    await c.completeCurrentSet(42.5, 6);
    final set = (await listSets(exec, c.exercises.single.sessionExercise.id))
        .singleWhere((s) => s.isCompleted);
    expect(set.weight, 42.5);
    expect(set.reps, 6);
  });

  test('完成一组后自动预建下一组（休息结束就有东西可填）', () async {
    final c = await started();
    await c.completeCurrentSet(40, 8);
    final sets = c.exercises.single.sets;
    expect(sets, hasLength(2));
    expect(sets.where((s) => !s.isCompleted), hasLength(1));
  });

  test('完成后开始休息计时：restStartedAt 与 completedAt 是同一个时刻', () async {
    final c = await started();
    await c.completeCurrentSet(40, 8);
    final set = c.exercises.single.sets.singleWhere((s) => s.isCompleted);
    expect(set.restStartedAt, isNotNull);
    expect(set.restStartedAt, set.completedAt);
  });

  test('beginNextSet 写入休息秒数并清掉 restStartedAt', () async {
    final c = await started();
    await c.completeCurrentSet(40, 8);

    // 手工把休息开始时间往前推 90 秒，避免测试里真的等
    final startedAt = DateTime.now().millisecondsSinceEpoch - 90000;
    await exec.run('UPDATE set_entry SET rest_started_at = ? WHERE is_completed = 1',
        [startedAt]);
    await c.resume(); // 重新载入，让内存里的值跟上

    await c.beginNextSet();
    final set = c.exercises.single.sets.singleWhere((s) => s.isCompleted);
    expect(set.restStartedAt, isNull);
    expect(set.restSeconds, closeTo(90, 2));
  });

  test('没有在休息时 beginNextSet 不写脏数据', () async {
    final c = await started();
    await c.beginNextSet();
    final sets = c.exercises.single.sets;
    expect(sets.where((s) => s.isCompleted), isEmpty);
  });

  test('⭐ endWorkout 写 finished_at 并立刻清空内存', () async {
    final c = await started();
    await c.completeCurrentSet(40, 8);
    final id = await c.endWorkout();

    expect(id, isNotNull);
    expect(c.session, isNull);   // 立刻清空，不等用户在总结页点完成
    expect(c.exercises, isEmpty);
    expect(await getActiveSession(exec), isNull);
  });

  test('endWorkout 时若正在休息，先把这段休息结掉', () async {
    final c = await started();
    await c.completeCurrentSet(40, 8);
    final startedAt = DateTime.now().millisecondsSinceEpoch - 60000;
    await exec.run('UPDATE set_entry SET rest_started_at = ? WHERE is_completed = 1',
        [startedAt]);
    await c.resume();

    await c.endWorkout();

    final seId = (await listSessionExercises(exec, (await listSessions(exec, 1)).single.id))
        .single.id;
    final set = (await listSets(exec, seId)).singleWhere((s) => s.isCompleted);
    // 不收尾的话这一组永远是 NULL，总结页算不出平均休息
    expect(set.restSeconds, closeTo(60, 2));
  });

  test('store 里本来就没有训练时 endWorkout 返回 null', () async {
    final c = ActiveSessionController(exec);
    expect(await c.endWorkout(), isNull);
  });

  test('reset 只清内存，不碰数据库', () async {
    final c = await started();
    c.reset();
    expect(c.session, isNull);
    // 库里那一场还在，仍然是进行中的
    expect(await getActiveSession(exec), isNotNull);
  });

  test('训练已结束时 completeCurrentSet 静默返回', () async {
    final c = await started();
    await c.endWorkout();
    await c.completeCurrentSet(40, 8); // 不该抛错
    expect(c.exercises, isEmpty);
  });

  test('重复点「完成这组」不会写第二条记录', () async {
    final c = await started();
    await c.completeCurrentSet(40, 8);
    // 此时没有 pending 组吗？有的 —— 上一组完成后预建了下一组。
    // 所以这里改为验证：当前动作已无 pending 时（手工删掉占位组）不出错
    await exec.run('DELETE FROM set_entry WHERE is_completed = 0');
    await c.resume();
    await c.completeCurrentSet(40, 8);
    final sets = await listSets(exec, c.exercises.single.sessionExercise.id);
    expect(sets.where((s) => s.isCompleted), hasLength(1));
  });
}
```

- [ ] **Step 2: 跑测试确认失败**

Run: `flutter test test/state/complete_set_test.dart`
Expected: FAIL —— 多个断言失败（空实现写不出数据）

- [ ] **Step 3: 把 Task 10 留下的空实现替换为完整实现**

在 `lib/state/active_session_controller.dart` 中替换那两个占位方法：

```dart
  /// 记完当前这一组：写数值 → 标完成 → 起休息计时 → 预建下一组，四步都落盘。
  ///
  /// 以下情况**静默返回**（都不报错）：训练已结束、currentIndex 越界、
  /// 该动作已无未完成的组（重复点击）。
  Future<void> completeCurrentSet(double weight, int reps) async {
    final current = session;
    if (current == null || current.finishedAt != null) return;
    if (currentIndex < 0 || currentIndex >= exercises.length) return;

    final active = exercises[currentIndex];
    final pending = active.sets.where((s) => !s.isCompleted).firstOrNull;
    if (pending == null) return;

    final now = DateTime.now().millisecondsSinceEpoch;

    // 顺序不能反：先把用户填的数值写进去，再标记完成。
    // 反过来一旦中途失败，就会留下「已完成但数值是旧的」的记录 ——
    // 而全局约束要求每完成一组立刻落盘，用户看到的就是最终记录。
    await updateSetValues(_exec, pending.id, weight, reps);
    await completeSet(_exec, pending.id, now);
    await startRest(_exec, pending.id, now);

    // 预先建好下一组，这样休息结束后立刻有东西可填
    await addSet(_exec, active.sessionExercise.id, weight, reps);

    final updated = await listSets(_exec, active.sessionExercise.id);
    exercises = List.of(exercises)..[currentIndex] = active.copyWith(sets: updated);
    notifyListeners();
  }

  /// 结束休息、进入下一组：写入这段休息的秒数并清掉 `restStartedAt`。
  ///
  /// 当前没有在休息时只是刷新一下列表，不写库。
  Future<void> beginNextSet() async {
    final current = session;
    if (current == null || current.finishedAt != null) return;
    if (currentIndex < 0 || currentIndex >= exercises.length) return;

    final active = exercises[currentIndex];
    final resting = active.sets
        .where((s) => s.isCompleted && s.restStartedAt != null)
        .firstOrNull;
    if (resting != null) {
      await endRest(_exec, resting.id, DateTime.now().millisecondsSinceEpoch);
    }

    final updated = await listSets(_exec, active.sessionExercise.id);
    exercises = List.of(exercises)..[currentIndex] = active.copyWith(sets: updated);
    notifyListeners();
  }

  /// 结束并**立刻清空** controller。
  ///
  /// 收尾：如果正处在休息中，先把这段休息结掉，否则这一组的 `rest_seconds`
  /// 永远是 NULL，总结页算不出平均休息。
  ///
  /// 结束之后立刻清内存，而不是等用户在总结页点「完成」——
  /// 「已经结束但还是当前训练」这个中间态正是旧项目「主页一直显示继续上次训练」
  /// 的直接原因：用户从总结页按系统返回键离开时永远走不到清空那一步，
  /// 而主页只看 controller 里有没有 session。
  ///
  /// **总结页不受影响**：它按路由参数 id 从库里读，不依赖 controller。
  ///
  /// 返回被结束的那场的 id；controller 里本来就没有训练时返回 null。
  Future<String?> endWorkout() async {
    final current = session;
    if (current == null) return null;

    if (currentIndex >= 0 && currentIndex < exercises.length) {
      final active = exercises[currentIndex];
      final resting = active.sets
          .where((s) => s.isCompleted && s.restStartedAt != null)
          .firstOrNull;
      if (resting != null) {
        await endRest(_exec, resting.id, DateTime.now().millisecondsSinceEpoch);
      }
    }

    final finishedId = current.id;
    await finishSession(
        _exec, finishedId, DateTime.now().millisecondsSinceEpoch);

    reset();
    return finishedId;
  }

  /// 清空内存里的训练状态。**不碰数据库、不结束训练** ——
  /// 调用方要负责先 [finishSession]（[endWorkout] 已经这么做了）。
  void reset() {
    session = null;
    exercises = [];
    currentIndex = 0;
    notifyListeners();
  }
```

同时在文件顶部补上需要的 import：

```dart
import 'package:collection/collection.dart';   // firstOrNull
```

> 若不想引 `collection` 包，把 `firstOrNull` 换成手写的 `_firstOrNull` 辅助函数。
> Dart 3 的 `Iterable` 没有内置 `firstOrNull`。

- [ ] **Step 4: 跑测试确认通过**

Run: `flutter test test/state/ -v`
Expected: `All tests passed!`（Task 10 的 14 条 + 本 Task 的 12 条）

- [ ] **Step 5: 提交**

```bash
git add lib/state test/state
git commit -m "feat(state): 完成即落盘四步、正计时休息、结束立刻清内存"
```

---

### Task 12: 端到端回归测试

**Files:**
- Create: `test/e2e/journey_test.dart`

**Interfaces:**
- Consumes: 全部仓储与 controller
- Produces: 一条串起 5 条主旅程的回归测试

> **为什么必须有这一层**（旧文档 §6.1）：「开训练 → 加动作 → 练完 → 结束 →
> 数据落地」这一条链跨了 4 个仓储 + 编排层，而没有任何一个分层测试覆盖它。
> 旧项目这条链**第一次跑就抓出一个分层测试没抓到的问题**。

- [ ] **Step 1: 写测试**

`test/e2e/journey_test.dart`：

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/migrations.dart';
import 'package:gym_tracker/data/repositories/exercise_repo.dart';
import 'package:gym_tracker/data/repositories/session_repo.dart';
import 'package:gym_tracker/data/repositories/set_repo.dart';
import 'package:gym_tracker/domain/metrics.dart';
import 'package:gym_tracker/domain/rest_advice.dart';
import 'package:gym_tracker/state/active_session_controller.dart';

/// 端到端回归：一条链串起 5 条主旅程。
///
/// 它跨了 exerciseRepo / sessionRepo / setRepo / ActiveSessionController 四处，
/// **没有任何分层测试覆盖这条链**。旧项目这条链第一次跑就抓出了一个分层测试
/// 没抓到的问题（判据写岔，而分层测试里那条用例同时写错了同一个判据）。
void main() {
  late FfiExecutor exec;

  setUp(() async {
    exec = await FfiExecutor.openInMemory();
    await migrate(exec);
    await seedExercisesIfEmpty(exec);
  });

  tearDown(() async => exec.close());

  test('主旅程：播种 → 开训练 → 加动作 → 完成多组 → 结束 → 数据落地正确', () async {
    // ── 旅程 1：全新库播种 ──
    final all = await listExercises(exec);
    expect(all, hasLength(52));

    final squat = all.firstWhere((e) => e.name == '深蹲');
    final bench = all.firstWhere((e) => e.name == '卧推');

    // ── 旅程 2：开一场训练并加两个动作 ──
    final c = ActiveSessionController(exec);
    expect(await c.startNew(), StartResult.started);
    await c.addExercise(squat.id);
    await c.addExercise(bench.id);
    expect(c.exercises, hasLength(2));
    expect(c.currentIndex, 1);

    // ── 旅程 3：在深蹲上完成 3 组，中间有休息 ──
    c.setCurrentIndex(0);
    final seId = c.exercises[0].sessionExercise.id;

    for (var i = 0; i < 3; i++) {
      await c.completeCurrentSet(40, 8);
      // 模拟 90 秒休息：把开始时间往前推，再结束它
      if (i < 2) {
        final back = DateTime.now().millisecondsSinceEpoch - 90000;
        await exec.run(
          'UPDATE set_entry SET rest_started_at = ? WHERE session_exercise_id = ? AND is_completed = 1',
          [back, seId],
        );
        await c.resume();
        await c.beginNextSet();
      }
    }

    final squatSets =
        (await listSets(exec, seId)).where((s) => s.isCompleted).toList();
    expect(squatSets, hasLength(3));
    expect(squatSets.every((s) => s.weight == 40 && s.reps == 8), isTrue);
    // 前两组有休息数据，最后一组没有（它后面没有休息）
    expect(squatSets[0].restSeconds, closeTo(90, 2));
    expect(squatSets[1].restSeconds, closeTo(90, 2));
    expect(squatSets[2].restSeconds, isNull);

    // ── 旅程 4：结束训练，controller 立刻清空 ──
    final finishedId = await c.endWorkout();
    expect(finishedId, isNotNull);
    expect(c.session, isNull);
    expect(await getActiveSession(exec), isNull);

    // ── 旅程 5：数据落地逐字段核对 ──
    final stored = (await listSessions(exec, 50)).single;
    expect(stored.id, finishedId);
    expect(stored.finishedAt, isNotNull);

    final storedSets = await listSets(exec, seId);
    expect(storedSets.where((s) => s.isCompleted), hasLength(3));
    // 未完成的占位组留着，不清理 —— 各处靠 is_completed 排除它
    expect(storedSets.where((s) => !s.isCompleted), hasLength(1));

    final volume = totalVolumeLoad(squatSets);
    expect(volume, 40 * 8 * 3); // 960

    final feedback = buildRestFeedback(
      squatSets.map((s) => s.reps).toList(),
      squatSets.map((s) => s.restSeconds).toList(),
    )!;
    expect(feedback.kind, RestFeedbackKind.positive);
    expect(feedback.message, contains('8 / 8 / 8'));
  });

  test('主旅程：强杀后 resume 能恢复，且「上次成绩」被下一场沿用', () async {
    final all = await listExercises(exec);
    final squat = all.firstWhere((e) => e.name == '深蹲');

    // 第一场：练 3 组 40kg
    final c1 = ActiveSessionController(exec);
    await c1.startNew();
    await c1.addExercise(squat.id);
    for (var i = 0; i < 3; i++) {
      await c1.completeCurrentSet(40, 5);
    }
    await c1.endWorkout();

    // 第二场：新 controller（模拟重开 App）
    final c2 = ActiveSessionController(exec);
    expect(await c2.startNew(), StartResult.started);
    // 动作组合应被复制过来
    expect(c2.exercises.single.exerciseName, '深蹲');
    // 第一组应预填上次的 40kg × 5
    expect(c2.exercises.single.sets.single.weight, 40);
    expect(c2.exercises.single.sets.single.reps, 5);
  });

  test('主旅程：训练中强杀 → 重开 resume 捡回那一场，且组数正确', () async {
    final all = await listExercises(exec);
    final squat = all.firstWhere((e) => e.name == '深蹲');

    final c1 = ActiveSessionController(exec);
    await c1.startNew();
    await c1.addExercise(squat.id);
    await c1.completeCurrentSet(40, 5);
    await c1.completeCurrentSet(40, 5);
    // 不调 endWorkout —— 模拟进程被强杀

    final c2 = ActiveSessionController(exec);
    expect(await c2.resume(), isTrue);
    final done = c2.exercises.single.sets.where((s) => s.isCompleted);
    expect(done, hasLength(2));
    // 还有一组待完成，界面才能继续记
    expect(c2.exercises.single.sets.where((s) => !s.isCompleted), hasLength(1));
  });

  test('主旅程：冲突 —— 有进行中的训练时不新建，且那一场可直接接着练', () async {
    final all = await listExercises(exec);
    final squat = all.firstWhere((e) => e.name == '深蹲');

    final c1 = ActiveSessionController(exec);
    await c1.startNew();
    await c1.addExercise(squat.id);

    final c2 = ActiveSessionController(exec);
    expect(await c2.startNew(), StartResult.conflict);
    // ⭐ 那一场必须已装进 controller，否则「接着练」进到一屏空白
    expect(c2.exercises, hasLength(1));

    final rows = await exec.all("SELECT id FROM session WHERE finished_at IS NULL");
    expect(rows, hasLength(1));
  });

  test('主旅程：30 分钟闸门 —— 隔夜打开不会被堵在休息页，也不污染休息数据', () async {
    final all = await listExercises(exec);
    final squat = all.firstWhere((e) => e.name == '深蹲');

    final c1 = ActiveSessionController(exec);
    await c1.startNew();
    await c1.addExercise(squat.id);
    await c1.completeCurrentSet(40, 5);

    // 把休息开始时间推到 8 小时前 —— 显然是忘了按「开始下一组」
    await exec.run('UPDATE set_entry SET rest_started_at = ?',
        [DateTime.now().millisecondsSinceEpoch - 8 * 3600 * 1000]);

    final c2 = ActiveSessionController(exec);
    await c2.resume();
    final done = c2.exercises.single.sets.singleWhere((s) => s.isCompleted);
    expect(done.restStartedAt, isNull);
    // 关键：8 小时不能被记成真实休息，否则平均值彻底带偏
    expect(done.restSeconds, isNull);
  });
}
```

- [ ] **Step 2: 跑测试**

Run: `flutter test test/e2e/journey_test.dart -v`
Expected: `All tests passed!`（5 个测试）

> **若这里红了，先别改测试。** 端到端测试的价值恰恰在于它是唯一能发现
> 「分层各自都绿、但层与层之间假设不一致」的那一层。旧项目那次红，
> 根因是界面判「一行 set 都没有」而 `keep` 保留已完成组导致条件恒不成立 ——
> **当时分层测试里那条用例也写错了同一个判据**。先定位到底哪一层的假设错了。

> ⚠️ **一处实施时要专门确认的疑点（写本计划时发现的）。**
>
> `domain/rest_advice.dart` 的文档说「最后那一组通常是 null（它是最后一组，
> 没有『组后休息』）」。但实现上：`completeCurrentSet` 会给**刚完成的每一组**
> 调 `startRest`，而 `endWorkout` 又会把「正在进行的那段休息」结掉 ——
> 于是**最后完成的那一组**的 `rest_seconds` 会是一个接近 0 的值，而不是 null。
>
> 后果：总结页读库时算出的 `averageRest` 会被这个 0 拉低（例如真实的
> `[90, 90, null]` 平均 90 秒，会变成 `[90, 90, 0]` 平均 60 秒）。
>
> 上面那条 e2e 测试**在 `endWorkout` 之前**读组，所以它绕开了这个问题 ——
> 这是有意的，好让这条测试先锁住「完成即落盘」这条主链。
>
> **实施时必须做的事**：在真机验收（Task 22 Step 6）时，用一个真实训练核对
> 总结页显示的提示是否被这个 0 影响到了判断档位（尤其当平均休息刚好在
> 180 秒上下时，它可能把 `addWeight` 误判成 `positive`）。
> **若确认有影响，停下来向用户汇报，不要自行决定怎么改** ——
> 这属于规格「绝不伪造数据」那一条红线的范围，处置方式该由用户定。

- [ ] **Step 3: 记录「怎么单独跑」和「怎么排除」**

e2e 放在 `test/e2e/` 这个独立目录里，所以不需要任何 tag 配置 —— 按路径即可区分：

```powershell
# 日常快速反馈：跳过 e2e
flutter test test/domain test/data test/state test/layering_test.dart

# 提交前：完整跑一遍（**这一步不能省**）
flutter test
```

把这两条命令写进 `docs/superpowers/plans/dev-environment-notes.md`。

> **不要引入 `@Tags` 注解或 `dart_test.yaml`** —— 按目录排除已经够用，
> 多一层测试框架配置只会多一处将来会失效的地方。

- [ ] **Step 4: 提交**

```bash
git add test/e2e
git commit -m "test(e2e): 5 条主旅程端到端回归"
```

---

## 里程碑 D：界面层

> **界面层的测试策略**：按规格 §7.2，本项目的 Widget **不写单元测试**（旧项目对应的是「纯逻辑留在带 JSX 的文件里等于永远测不到」）——
> 判据是：**凡是能抽进 `domain/` 的逻辑都已经抽走了**，剩下的都是纯渲染。
> 界面层靠 `flutter analyze` + Chrome 预览 + 真机验收把关。
> **因此每个 Task 都必须至少有一次「在 Chrome 里看到它对」的记录。**

### Task 13: `ui/tokens.dart` + `ui/theme.dart`

**Files:**
- Create: `lib/ui/tokens.dart`
- Create: `lib/ui/theme.dart`

**Interfaces:**
- Consumes: 无
- Produces:
  - `class AppColors` + `AppColors.dark` / `AppColors.light`
  - `abstract final class AppFontSize`（`display` 84 / `clock` 76 / `stat` 30 / `h1` 30 / `h2` 22 / `title` 17 / `body` 15 / `caption` 13 / `label` 11）
  - `abstract final class AppSpacing`
  - `ThemeData buildTheme(AppColors colors, Brightness brightness)`

- [ ] **Step 1: 写 `lib/ui/tokens.dart`**

```dart
import 'package:flutter/material.dart';

/// 纯视觉层的**唯一来源**。
///
/// 规格 §6.4：**界面不写裸数值** —— 颜色、字号、间距一律从这里取。
/// 这条纪律的收益很具体：休息计时的钟面与记录页的大数字是两个不同尺寸，
/// 共用一个 display 会让其中一处偏大或偏小（旧项目落地时才发现，
/// 于是多出了一档 clock 76）。
class AppColors {
  /// 近黑，**不用纯黑** —— 纯黑在 OLED 上和边框糊在一起，看不出边界
  final Color background;
  final Color surface;
  final Color surfacePressed;

  /// 信号橙。同时是杠铃片、警示带、力量器械的颜色。
  ///
  /// 刻意避开 `#2b7fff` 蓝（AI 生成界面的最典型特征）与荧光绿
  /// （与健身房「安全色」语义冲突）。
  final Color accent;
  final Color success;
  final Color danger;
  final Color textPrimary;
  final Color textSecondary;
  final Color textTertiary;
  final Color border;

  const AppColors({
    required this.background,
    required this.surface,
    required this.surfacePressed,
    required this.accent,
    required this.success,
    required this.danger,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.border,
  });

  /// 力量感 · 暗色仪表盘。默认配色。
  static const AppColors dark = AppColors(
    background: Color(0xFF0B0C0E),
    surface: Color(0xFF141619),
    surfacePressed: Color(0xFF1C1F24),
    accent: Color(0xFFFF6A1A),
    success: Color(0xFF32D74B),
    danger: Color(0xFFFF453A),
    textPrimary: Color(0xFFF2F4F7),
    textSecondary: Color(0xFF9BA1AC),
    textTertiary: Color(0xFF656B76),
    border: Color(0xFF2A2E35),
  );

  /// 浅色是**同色相映射**，不是简单反色：暖白底 + 略深一档的橙。
  static const AppColors light = AppColors(
    background: Color(0xFFFAFAF8),
    surface: Color(0xFFFFFFFF),
    surfacePressed: Color(0xFFF0EFEC),
    accent: Color(0xFFE4580A),
    success: Color(0xFF1F9D3A),
    danger: Color(0xFFD32F2F),
    textPrimary: Color(0xFF16181C),
    textSecondary: Color(0xFF5A606B),
    textTertiary: Color(0xFF8B9099),
    border: Color(0xFFDDDCD8),
  );
}

/// 字号尺度。**下面是实际值，不是设计稿的值。**
///
/// 设计阶段写的是 display 88，落地时收敛到 84，并多出一档 clock 76。
class AppFontSize {
  AppFontSize._();

  /// 记录页那个超大数字
  static const double display = 84;

  /// 休息计时的钟面
  static const double clock = 76;

  /// 统计块里的主数字
  static const double stat = 30;
  static const double h1 = 30;
  static const double h2 = 22;

  /// 列表行主文本、按钮
  static const double title = 17;
  static const double body = 15;

  /// 次要说明、元信息
  static const double caption = 13;

  /// 分组小标题、单位标注（通常配 letterSpacing）
  static const double label = 11;
}

class AppSpacing {
  AppSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;

  /// 屏幕左右安全边距
  static const double screenH = 20;

  /// 圆角
  static const double radius = 14;
  static const double radiusSm = 8;
}

/// 数字专用文字样式：**等宽数字**。
///
/// `FontFeature.tabularFigures()` 让数字宽度恒定 —— 拖动那个 84px 的大数字时
/// `9 → 10` 不会让整块抖一下。
///
/// 字体用**系统字体**，不引第三方字体文件：中文字体动辄 5–10MB 会拖慢启动；
/// 引拉丁数字字体则会制造中西混排差异。**品牌感靠排版、间距、颜色做，
/// 不靠字体文件。**
const List<FontFeature> tabularNums = [FontFeature.tabularFigures()];
```

- [ ] **Step 2: 写 `lib/ui/theme.dart`**

```dart
import 'package:flutter/material.dart';

import 'tokens.dart';

/// 把 [AppColors] 装配成 ThemeData。
///
/// 这里**只做映射，不做设计决策** —— 所有取值都来自 tokens。
ThemeData buildTheme(AppColors colors) {
  final isDark = colors.background.computeLuminance() < 0.5;

  return ThemeData(
    useMaterial3: true,
    brightness: isDark ? Brightness.dark : Brightness.light,
    scaffoldBackgroundColor: colors.background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: colors.accent,
      brightness: isDark ? Brightness.dark : Brightness.light,
    ).copyWith(
      surface: colors.surface,
      primary: colors.accent,
      error: colors.danger,
    ),
    dividerColor: colors.border,
    textTheme: TextTheme(
      displayLarge: TextStyle(
        fontSize: AppFontSize.display,
        fontWeight: FontWeight.w700,
        color: colors.textPrimary,
        fontFeatures: tabularNums,
      ),
      headlineLarge: TextStyle(
        fontSize: AppFontSize.h1,
        fontWeight: FontWeight.w700,
        color: colors.textPrimary,
      ),
      titleLarge: TextStyle(
        fontSize: AppFontSize.h2,
        fontWeight: FontWeight.w600,
        color: colors.textPrimary,
      ),
      titleMedium: TextStyle(
        fontSize: AppFontSize.title,
        fontWeight: FontWeight.w600,
        color: colors.textPrimary,
      ),
      bodyMedium: TextStyle(fontSize: AppFontSize.body, color: colors.textPrimary),
      bodySmall: TextStyle(fontSize: AppFontSize.caption, color: colors.textSecondary),
      labelSmall: TextStyle(
        fontSize: AppFontSize.label,
        letterSpacing: 0.8,
        color: colors.textTertiary,
      ),
    ),
    extensions: <ThemeExtension<dynamic>>[AppColorsExtension(colors)],
  );
}

/// 让任意 widget 通过 `Theme.of(context).extension<AppColorsExtension>()`
/// 拿到当前配色 —— 不必在每个 widget 里判断亮暗。
class AppColorsExtension extends ThemeExtension<AppColorsExtension> {
  final AppColors colors;

  const AppColorsExtension(this.colors);

  @override
  AppColorsExtension copyWith({AppColors? colors}) =>
      AppColorsExtension(colors ?? this.colors);

  @override
  AppColorsExtension lerp(ThemeExtension<AppColorsExtension>? other, double t) {
    if (other is! AppColorsExtension) return this;
    return t < 0.5 ? this : other;
  }
}

/// 取当前配色的便捷入口。
AppColors appColors(BuildContext context) =>
    Theme.of(context).extension<AppColorsExtension>()?.colors ?? AppColors.dark;
```

- [ ] **Step 3: 在 Chrome 里目视确认**

在 `lib/main.dart` 里临时把 `MaterialApp` 的 theme 换成 `buildTheme(AppColors.dark)`，跑 `flutter run -d chrome`，确认背景是近黑而不是纯黑、强调色是橙而不是蓝。

- [ ] **Step 4: 提交**

```bash
git add lib/ui
git commit -m "feat(ui): tokens 与主题装配 —— 铸铁 + 信号橙，数字等宽"
```

---

### Task 14: `ui/widgets/` 基础组件

**Files:**
- Create: `lib/ui/widgets/primary_button.dart`
- Create: `lib/ui/widgets/app_card.dart`
- Create: `lib/ui/widgets/stat_block.dart`
- Create: `lib/ui/widgets/segmented_control.dart`
- Create: `lib/ui/widgets/empty_state.dart`

**Interfaces:**
- Consumes: `tokens.dart`、`theme.dart`
- Produces:
  - `class PrimaryButton extends StatelessWidget`（`label`、`onPressed`、`variant`）
  - `class AppCard extends StatelessWidget`（`child`、`onTap`）
  - `class StatBlock extends StatelessWidget`（`label`、`value`、`unit`）
  - `class SegmentedControl<T> extends StatelessWidget`（`options`、`value`、`onChanged`）
  - `class EmptyState extends StatelessWidget`（`message`、`action`）

- [ ] **Step 1: 写这五个组件**

`lib/ui/widgets/primary_button.dart`：

```dart
import 'package:flutter/material.dart';

import '../theme.dart';
import '../tokens.dart';

enum ButtonVariant { primary, secondary, danger }

/// 主操作按钮。整宽是**有意的** —— 记录页那几次点击要能用拇指一次命中。
class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final ButtonVariant variant;
  final IconData? icon;

  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = ButtonVariant.primary,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    final bg = switch (variant) {
      ButtonVariant.primary => c.accent,
      ButtonVariant.secondary => c.surfacePressed,
      ButtonVariant.danger => c.danger,
    };
    final fg = variant == ButtonVariant.secondary ? c.textPrimary : Colors.white;
    final disabled = onPressed == null;

    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: bg,
          foregroundColor: fg,
          disabledBackgroundColor: c.surfacePressed,
          disabledForegroundColor: c.textTertiary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppSpacing.radius),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20),
              const SizedBox(width: AppSpacing.sm),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: AppFontSize.title,
                fontWeight: FontWeight.w600,
                color: disabled ? c.textTertiary : fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
```

`lib/ui/widgets/app_card.dart`：

```dart
import 'package:flutter/material.dart';

import '../theme.dart';
import '../tokens.dart';

/// 二级容器。`surface` 色 + 细描边，不用阴影 ——
/// 暗色主题里阴影几乎不可见，描边才是能看清边界的手段。
class AppCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
  });

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    final content = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(AppSpacing.radius),
        border: Border.all(color: c.border),
      ),
      child: child,
    );

    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSpacing.radius),
      child: content,
    );
  }
}
```

`lib/ui/widgets/stat_block.dart`：

```dart
import 'package:flutter/material.dart';

import '../theme.dart';
import '../tokens.dart';

/// 总结页顶部那三个数字之一：时长 / 总组数 / 总容量。
///
/// **单位单独一档且更小**，因为它和数字不是同一层级的信息。
class StatBlock extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;

  const StatBlock({
    super.key,
    required this.label,
    required this.value,
    this.unit,
  });

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: AppFontSize.label,
            letterSpacing: 0.8,
            color: c.textTertiary,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: AppFontSize.stat,
                fontWeight: FontWeight.w700,
                color: c.textPrimary,
                fontFeatures: tabularNums,
              ),
            ),
            if (unit != null) ...[
              const SizedBox(width: 3),
              Text(
                unit!,
                style: TextStyle(
                  fontSize: AppFontSize.caption,
                  color: c.textSecondary,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
```

`lib/ui/widgets/segmented_control.dart`：

```dart
import 'package:flutter/material.dart';

import '../theme.dart';
import '../tokens.dart';

/// 三选一分段控件。**主题三态用的就是它** ——
/// 布尔（深/浅）表达不了「跟随系统」，那才是默认值。
class SegmentedControl<T> extends StatelessWidget {
  final List<T> options;
  final T value;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  const SegmentedControl({
    super.key,
    required this.options,
    required this.value,
    required this.labelOf,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: c.surfacePressed,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm + 2),
      ),
      child: Row(
        children: options.map((option) {
          final selected = option == value;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(option),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? c.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                ),
                child: Text(
                  labelOf(option),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: AppFontSize.body,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    color: selected ? Colors.white : c.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}
```

`lib/ui/widgets/empty_state.dart`：

```dart
import 'package:flutter/material.dart';

import '../theme.dart';
import '../tokens.dart';

/// 空态。
///
/// [action] 不是可选的装饰 —— 旧项目在 M2 踩过一个坑：训练页的空态
/// 只显示一句「这次训练还没有动作」，**没有任何添加入口**，
/// 用户进到那里就是一条死路。空态必须给出下一步。
class EmptyState extends StatelessWidget {
  final String message;
  final Widget? action;

  const EmptyState({super.key, required this.message, this.action});

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: AppFontSize.body, color: c.textSecondary),
            ),
            if (action != null) ...[
              const SizedBox(height: AppSpacing.xl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: 跑静态分析**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 3: 提交**

```bash
git add lib/ui/widgets
git commit -m "feat(ui): 五个基础组件 —— 按钮/卡片/统计块/分段控件/空态"
```

---

### Task 15: 路由 + 四标签外壳

**Files:**
- Create: `lib/app/router.dart`
- Create: `lib/app/app_shell.dart`
- Create: `lib/app/providers.dart`
- Modify: `lib/main.dart`
- Create: `lib/features/history/history_page.dart`（占位）
- Create: `lib/features/progress/progress_page.dart`（占位）

**Interfaces:**
- Consumes: `ActiveSessionController`、`theme.dart`
- Produces:
  - `class AppProviders extends StatelessWidget`（打开库、跑迁移、播种、下发 controller）
  - `GoRouter buildRouter()`
  - 路由常量：`/`（训练）、`/history`、`/progress`、`/settings`、`/session/:id`（记录页）、`/summary/:id`

- [ ] **Step 1: 写 `lib/app/providers.dart`**

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/db/database.dart';
import '../data/db/sql_executor.dart';
import '../data/repositories/exercise_repo.dart';
import '../data/repositories/settings_repo.dart';
import '../state/active_session_controller.dart';
import '../state/theme_controller.dart';
import '../ui/theme.dart';
import '../ui/tokens.dart';
import 'router.dart';

/// App 的依赖装配与启动流程。
///
/// **顺序不可反**：打开库 → 跑迁移 → 播种 → 读主题偏好 → 才放行子树。
/// 最后一条见规格 §6.5：偏好读出来之前不放行子树，否则每次启动都会闪一帧。
class AppBootstrap extends StatefulWidget {
  const AppBootstrap({super.key});

  @override
  State<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends State<AppBootstrap> {
  SqlExecutor? _exec;
  ActiveSessionController? _session;
  ThemeController? _theme;
  Object? _error;

  /// **router 只建一次。** 写在 `build()` 里的话每次重建都会新建一个
  /// `GoRouter`，导航栈会被整个丢掉。
  late final _router = buildRouter();

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    try {
      final exec = await openAppDatabase();
      await seedExercisesIfEmpty(exec);

      final theme = ThemeController(exec);
      await theme.load(); // 不放行子树直到它完成 —— 否则每次启动闪一帧

      if (!mounted) return;
      setState(() {
        _exec = exec;
        _session = ActiveSessionController(exec);
        _theme = theme;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final exec = _exec;
    final session = _session;
    final theme = _theme;

    if (_error != null) {
      // 数据库打不开时也要给一个能读懂的界面，而不是白屏
      return MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Text('数据库打开失败：$_error', textAlign: TextAlign.center),
            ),
          ),
        ),
      );
    }

    if (exec == null || session == null || theme == null) {
      return const MaterialApp(
        home: Scaffold(body: Center(child: CircularProgressIndicator())),
      );
    }

    return MultiProvider(
      providers: [
        Provider<SqlExecutor>.value(value: exec),
        ChangeNotifierProvider<ActiveSessionController>.value(value: session),
        ChangeNotifierProvider<ThemeController>.value(value: theme),
      ],
      // 在 Provider 之下读主题，所以这一层必须是独立 widget
      child: _ThemedApp(router: _router),
    );
  }
}

/// 把 [ThemeController] 的三态偏好接到 `MaterialApp.themeMode` 上。
class _ThemedApp extends StatelessWidget {
  final GoRouter router;

  const _ThemedApp({required this.router});

  @override
  Widget build(BuildContext context) {
    final mode = context.watch<ThemeController>().mode;
    return MaterialApp.router(
      title: '健身记录',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(AppColors.light),
      darkTheme: buildTheme(AppColors.dark),
      themeMode: switch (mode) {
        AppThemeMode.system => ThemeMode.system,
        AppThemeMode.light => ThemeMode.light,
        AppThemeMode.dark => ThemeMode.dark,
      },
      routerConfig: router,
    );
  }
}
```

`lib/main.dart`：

```dart
import 'package:flutter/material.dart';

import 'app/providers.dart';

void main() => runApp(const AppBootstrap());
```

> `_ThemedApp` 需要 `import 'package:go_router/go_router.dart';`。

- [ ] **Step 2: 写 `lib/data/db/database.dart`**

```dart
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart' as sqflite;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

import 'ffi_executor.dart';
import 'migrations.dart';
import 'sql_executor.dart';
import 'sqflite_executor.dart';

/// 打开 App 数据库并跑完迁移。
///
/// **三后端**（规格 §3.1）：
/// - Android 真机 → `sqflite`
/// - Chrome 预览 → `sqflite_common_ffi_web`（真 SQLite wasm，落 IndexedDB）
/// - 单元测试 → 走 `FfiExecutor.openMigrated()`，**不经过这里**
///
/// 三个后端最终都汇到同一个执行器类，**差别只在「怎么打开库」**。
///
/// 打开后**必须立刻开 `PRAGMA foreign_keys = ON`** —— 它是连接级开关，
/// 不开的话建表时写的 `ON DELETE CASCADE` 静默失效。
Future<SqlExecutor> openAppDatabase() async {
  if (kIsWeb) {
    // Chrome 预览：真 SQLite，但数据落在浏览器 IndexedDB，与手机完全隔离。
    // ⚠️ 官方标为 experimental 且 slow，有已知 bug，且 IndexedDB 绑端口 ——
    // **预览只用于看视觉与基本流程，不是验收**（规格 §3.1）。
    final db = await databaseFactoryFfiWeb.openDatabase(
      'gym_tracker.db',
      options: OpenDatabaseOptions(version: 1),
    );
    await db.execute('PRAGMA foreign_keys = ON');
    final exec = FfiExecutor.fromDatabase(db);
    await migrate(exec);
    return exec;
  }

  final dir = await sqflite.getDatabasesPath();
  final exec = await SqfliteExecutor.open(p.join(dir, 'gym_tracker.db'));
  await migrate(exec);
  return exec;
}
```

> **`OpenDatabaseOptions(version: 1)` 是必须的** —— 不传 version 时
> `openDatabase` 会走「无版本」路径，`PRAGMA foreign_keys` 之后仍可执行，
> 但如果该后端对 version 有断言就会在启动时抛错。
> 我们**自己管版本**（`app_meta.schema_version`），所以这里的 version 只用 1
> 占位，**不依赖它的 onUpgrade 回调**。
>
> **若 `databaseFactoryFfiWeb.openDatabase` 的签名与此不符**：以该包
> 实际 API 为准调整，并把差异记进 `dev-environment-notes.md`。

- [ ] **Step 3: 写 `lib/app/router.dart` + `lib/app/app_shell.dart`**

```dart
// router.dart
import 'package:go_router/go_router.dart';

import '../features/history/history_page.dart';
import '../features/progress/progress_page.dart';
import '../features/settings/settings_page.dart';
import '../features/workout/summary_page.dart';
import '../features/workout/workout_home_page.dart';
import '../features/workout/record_page.dart';
import 'app_shell.dart';

GoRouter buildRouter() => GoRouter(
      initialLocation: '/',
      routes: [
        ShellRoute(
          builder: (context, state, child) => AppShell(child: child),
          routes: [
            GoRoute(path: '/', builder: (_, __) => const WorkoutHomePage()),
            GoRoute(path: '/history', builder: (_, __) => const HistoryPage()),
            GoRoute(path: '/progress', builder: (_, __) => const ProgressPage()),
            GoRoute(path: '/settings', builder: (_, __) => const SettingsPage()),
          ],
        ),
        // 记录页与总结页**不在标签外壳里** —— 它们要占满全屏
        GoRoute(path: '/session/:id', builder: (_, s) => RecordPage(sessionId: s.pathParameters['id']!)),
        GoRoute(path: '/summary/:id', builder: (_, s) => SummaryPage(sessionId: s.pathParameters['id']!)),
      ],
    );
```

```dart
// app_shell.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../ui/theme.dart';
import '../ui/tokens.dart';

/// 四标签外壳。**`SafeArea` 不可省** ——
/// 旧项目在隐藏导航栏后出现过「顶部动作条压住状态栏」。
class AppShell extends StatelessWidget {
  final Widget child;

  const AppShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    final location = GoRouterState.of(context).uri.path;
    final index = switch (location) {
      '/history' => 1,
      '/progress' => 2,
      '/settings' => 3,
      _ => 0,
    };

    return Scaffold(
      body: SafeArea(child: child),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        backgroundColor: c.surface,
        indicatorColor: c.accent.withValues(alpha: 0.18),
        onDestinationSelected: (i) => switch (i) {
          0 => context.go('/'),
          1 => context.go('/history'),
          2 => context.go('/progress'),
          _ => context.go('/settings'),
        },
        destinations: const [
          NavigationDestination(icon: Icon(Icons.fitness_center), label: '训练'),
          NavigationDestination(icon: Icon(Icons.history), label: '历史'),
          NavigationDestination(icon: Icon(Icons.show_chart), label: '进步'),
          NavigationDestination(icon: Icon(Icons.settings), label: '设置'),
        ],
      ),
    );
  }
}
```

- [ ] **Step 4: 写两个占位页**

```dart
// lib/features/history/history_page.dart
import 'package:flutter/material.dart';
import '../../ui/widgets/empty_state.dart';

class HistoryPage extends StatelessWidget {
  const HistoryPage({super.key});
  @override
  Widget build(BuildContext context) =>
      const EmptyState(message: '历史记录将在下一期交付');
}
```
（`progress_page.dart` 同形，文案「进步曲线将在下一期交付」。）

- [ ] **Step 5: 在 Chrome 里目视确认四标签能切**

Run: `flutter run -d chrome`
Expected: 底栏四个标签可切换，切到历史/进步显示占位空态。**SafeArea 生效，没有内容被状态栏压住。**

- [ ] **Step 6: 提交**

```bash
git add lib/app lib/data/db/database.dart lib/features lib/main.dart
git commit -m "feat(app): 依赖装配、go_router 路由与四标签外壳"
```

---

### Task 16: 训练首页

**Files:**
- Create: `lib/features/workout/workout_home_page.dart`
- Create: `lib/features/workout/conflict_dialog.dart`

**Interfaces:**
- Consumes: `ActiveSessionController`、`describeExercises`、`formatDateTime`
- Produces: `WorkoutHomePage`；`Future<ConflictChoice?> showConflictDialog(BuildContext)`

- [ ] **Step 1: 写冲突对话（三按钮）**

`lib/features/workout/conflict_dialog.dart`：

```dart
import 'package:flutter/material.dart';

import '../../ui/tokens.dart';

/// 用户对「已经有一场没结束的训练」的选择。
enum ConflictChoice { resume, endAndStartNew, cancel }

/// 询问用户怎么处理那一场没结束的训练。
///
/// ⚠️ **这里是三按钮，不是旧项目的两按钮。**
///
/// 旧项目（React Native）的设计文档 §5.2 记着：原始设计是三按钮
/// `[接着练] [结束它，开始新的] [取消]`，但实现被迫改成两按钮 + cancelable ——
/// 原因是 **Android 的 Alert 最多三个按钮，且 RN 的映射顺序是
/// `[neutral, negative, positive]`，三个按钮时必有一个落进加粗主按钮位**，
/// 「无论放哪个都是误导」。
///
/// **Flutter 自己绘制对话框，没有这个限制**，因此还原原始设计：
/// 「取消」与「结束它」是两个不同性质的选项，值得各占一个按钮。
Future<ConflictChoice?> showConflictDialog(
  BuildContext context, {
  required String description,
}) {
  return showDialog<ConflictChoice>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      title: const Text('上一场训练还没结束'),
      content: Text(description),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, ConflictChoice.cancel),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, ConflictChoice.endAndStartNew),
          child: const Text('结束它，开始新的'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, ConflictChoice.resume),
          child: const Text('接着练'),
        ),
      ],
    ),
  );
}
```

- [ ] **Step 2: 写训练首页**

`lib/features/workout/workout_home_page.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/session_repo.dart';
import '../../domain/format.dart';
import '../../domain/session_label.dart';
import '../../domain/types.dart';
import '../../state/active_session_controller.dart';
import '../../ui/theme.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/app_card.dart';
import '../../ui/widgets/primary_button.dart';
import 'conflict_dialog.dart';

/// 训练首页。它要回答两个问题：
/// 1. 有没有没练完的（「继续 今天 15:20 的训练 · 深蹲 等 3 个动作 · 已记 12 组」）
/// 2. 否则就开一场新的
class WorkoutHomePage extends StatefulWidget {
  const WorkoutHomePage({super.key});

  @override
  State<WorkoutHomePage> createState() => _WorkoutHomePageState();
}

class _WorkoutHomePageState extends State<WorkoutHomePage> {
  WorkoutSession? _active;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _probe());
  }

  /// 探一次库里有没有进行中的训练。
  ///
  /// **必须在挂载后再探** —— 旧项目修过一个竞态：主页刚挂载、
  /// resume 还没跑完时用户点了「开始新训练」。
  Future<void> _probe() async {
    final c = context.read<ActiveSessionController>();
    await c.resume();
    if (!mounted) return;
    setState(() => _active = c.session);
  }

  Future<void> _startNew() async {
    final c = context.read<ActiveSessionController>();

    // 先刷新一次 _active，避免竞态
    await c.resume();
    if (!mounted) return;
    setState(() => _active = c.session);

    if (_active != null) {
      final choice = await showConflictDialog(
        context,
        description: _describe(c, _active!),
      );
      if (!mounted) return;

      switch (choice) {
        case ConflictChoice.resume:
          context.push('/session/${_active!.id}');
          return;
        case ConflictChoice.endAndStartNew:
          await c.endWorkout();
          break;
        case ConflictChoice.cancel:
        case null:
          return;
      }
    }

    final result = await c.startNew();
    if (!mounted) return;
    if (result == StartResult.started) {
      context.push('/session/${c.session!.id}');
    }
  }

  /// 「深蹲 等 3 个动作 · 已记 12 组」。
  ///
  /// 主页按钮和冲突弹窗**共用同一个函数** —— 抽出来不是为了省几行代码，
  /// 而是为了让「这说的是哪一场」只有一个答案。两处各写一遍、改一处忘一处时，
  /// 用户会看到两句互相矛盾的话，而这个按钮存在的全部意义就是让他确认
  /// 「是不是我刚才那场」。
  String _describe(ActiveSessionController c, WorkoutSession s) =>
      describeExercises(c.exercises.map((e) => e.progress).toList());

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ActiveSessionController>();
    final sc = appColors(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: AppSpacing.xl),
          Text('训练', style: TextStyle(
            fontSize: AppFontSize.h1,
            fontWeight: FontWeight.w700,
            color: sc.textPrimary,
          )),
          const SizedBox(height: AppSpacing.xl),

          if (c.session != null)
            AppCard(
              onTap: () => context.push('/session/${c.session!.id}'),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('继续 ${formatDateTime(c.session!.startedAt)} 的训练',
                      style: TextStyle(
                        fontSize: AppFontSize.title,
                        fontWeight: FontWeight.w600,
                        color: sc.accent,
                      )),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    describeExercises(c.exercises.map((e) => e.progress).toList()),
                    style: TextStyle(
                        fontSize: AppFontSize.caption, color: sc.textSecondary),
                  ),
                ],
              ),
            ),

          if (c.session != null) const SizedBox(height: AppSpacing.lg),

          PrimaryButton(
            label: c.session != null ? '开始新训练' : '开始训练',
            icon: Icons.play_arrow_rounded,
            onPressed: _startNew,
          ),
        ],
      ),
    );
  }
}
```

- [ ] **Step 3: 在 Chrome 里走一遍**

Run: `flutter run -d chrome`
点「开始训练」→ 应跳到记录页（记录页在 Task 17 才实现，此时是占位）。
返回首页 → 应显示「继续 今天 HH:MM 的训练」。

- [ ] **Step 4: 提交**

```bash
git add lib/features/workout
git commit -m "feat(workout): 训练首页与冲突三按钮对话"
```

---

### Task 17: 记录页 —— 聚焦当前组

**Files:**
- Create: `lib/features/workout/record_page.dart`
- Create: `lib/features/workout/drag_number.dart`
- Create: `lib/features/workout/stepper.dart`
- Create: `lib/features/workout/rest_view.dart`

**Interfaces:**
- Consumes: `ActiveSessionController`、`formatClock`、`AppFontSize`
- Produces: `RecordPage({required String sessionId})`、`DragNumber`、`Stepper`

- [ ] **Step 1: 写 `DragNumber` —— 大数字拖动**

```dart
import 'package:flutter/material.dart';

import '../../ui/theme.dart';
import '../../ui/tokens.dart';

/// 可拖动调值的大数字。
///
/// 规格 §6.2：**拖动与步进器并存，不是二选一。**
/// 拖动管大跨度（20 → 60），步进器管微调 —— 旧项目真机使用后确认二者互补。
///
/// 纯拖动会被汗手坑：**手上有汗、屏幕可能湿，想调 2.5kg 却滑过头**，
/// 所以它是「快速粗调」，精调交给步进器。
class DragNumber extends StatefulWidget {
  final double value;
  final double step;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final String unit;

  /// 拖动灵敏度：每多少逻辑像素走一档。旧项目实测 12dp/档手感合适。
  final double pixelsPerStep;

  const DragNumber({
    super.key,
    required this.value,
    required this.onChanged,
    this.step = 2.5,
    this.min = 0,
    this.max = 500,
    this.unit = 'kg',
    this.pixelsPerStep = 12,
  });

  @override
  State<DragNumber> createState() => _DragNumberState();
}

class _DragNumberState extends State<DragNumber> {
  late double _accumulated;

  @override
  void initState() {
    super.initState();
    _accumulated = 0;
  }

  void _onDragStart(DragStartDetails _) => _accumulated = 0;

  void _onDragUpdate(DragUpdateDetails d) {
    // 向上拖 = 加重，所以取负
    _accumulated += -d.delta.dy;
    final steps = (_accumulated / widget.pixelsPerStep).truncate();
    if (steps == 0) return;
    _accumulated -= steps * widget.pixelsPerStep;

    final next = (widget.value + steps * widget.step)
        .clamp(widget.min, widget.max);
    if (next != widget.value) widget.onChanged(_round(next));
  }

  double _round(double v) => (v / widget.step).round() * widget.step;

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    return GestureDetector(
      onVerticalDragStart: _onDragStart,
      onVerticalDragUpdate: _onDragUpdate,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            // 整数不显示小数点，22.5 显示一位 —— tabularFigures 保证不抖
            widget.value == widget.value.roundToDouble()
                ? widget.value.toInt().toString()
                : widget.value.toStringAsFixed(1),
            style: TextStyle(
              fontSize: AppFontSize.display,
              fontWeight: FontWeight.w700,
              color: c.textPrimary,
              fontFeatures: tabularNums,
              height: 1.0,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(widget.unit, style: TextStyle(
            fontSize: AppFontSize.label,
            letterSpacing: 1.2,
            color: c.textTertiary,
          )),
        ],
      ),
    );
  }
}
```

- [ ] **Step 2: 写 `Stepper` —— 精调**

```dart
import 'package:flutter/material.dart';

import '../../ui/theme.dart';
import '../../ui/tokens.dart';

/// 一对 −/+ 做精确微调。
///
/// 视觉上是**次级**的（比大数字小得多）—— 它服务的是「22.5 想变 25」
/// 这种微调，不是主要操作路径。
class Stepper extends StatelessWidget {
  final double value;
  final double step;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  const Stepper({
    super.key,
    required this.value,
    required this.onChanged,
    this.step = 2.5,
    this.min = 0,
    this.max = 500,
  });

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _btn(context, Icons.remove, () {
          final next = (value - step).clamp(min, max);
          onChanged((next / step).round() * step);
        }),
        const SizedBox(width: AppSpacing.lg),
        _btn(context, Icons.add, () {
          final next = (value + step).clamp(min, max);
          onChanged((next / step).round() * step);
        }),
      ],
    );
  }

  Widget _btn(BuildContext context, IconData icon, VoidCallback onTap) {
    final c = appColors(context);
    return SizedBox(
      width: 48,
      height: 48,
      child: Material(
        color: c.surfacePressed,
        borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          child: Icon(icon, size: 22, color: c.textSecondary),
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: 写 `RestView` —— 正计时**

`lib/features/workout/rest_view.dart`：

```dart
import 'dart:async';

import 'package:flutter/material.dart';

import '../../domain/format.dart';
import '../../ui/theme.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/primary_button.dart';
import 'breathing_dot.dart';

/// 休息界面：**正计时，不催促**。
///
/// 这是本 App 与常见健身 App 最重要的区别（规格 §3.4）：
/// 用户休息多久就记多久，数据是**观察**出来的，不是**规定**出来的。
/// 倒计时会催人，而每一次休息都因此成为一条可分析的数据。
///
/// **计时基于 `restStartedAt` 时间戳用「现在 − 开始」算，不用累加器** ——
/// App 被系统挂起十分钟，算出来的休息时长依然准确。旧项目真机实测：
/// 息屏前 18:20，息屏 35 秒后 19:01，Δ41 秒 vs 实测等待 40 秒，吻合。
class RestView extends StatefulWidget {
  final int restStartedAt;
  final int nextSetNumber;
  final VoidCallback onBeginNextSet;

  const RestView({
    super.key,
    required this.restStartedAt,
    required this.nextSetNumber,
    required this.onBeginNextSet,
  });

  @override
  State<RestView> createState() => _RestViewState();
}

class _RestViewState extends State<RestView> {
  Timer? _timer;

  /// 每次都从时间戳现算，**不累加** —— 累加器在 App 被挂起时会冻住
  int get _elapsedSeconds =>
      ((DateTime.now().millisecondsSinceEpoch - widget.restStartedAt) / 1000)
          .floor();

  @override
  void initState() {
    super.initState();
    // 这个 Timer **只负责触发重绘**，不负责计时。
    // 所以它的 tick 间隔准不准、挂起期间有没有跳，都不影响读数。
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // 呼吸点告诉用户「它真的在走」，而不是一个静止的 00:00
        const BreathingDot(),
        const SizedBox(height: AppSpacing.lg),
        Text(
          formatClock(_elapsedSeconds),
          style: TextStyle(
            fontSize: AppFontSize.clock,
            fontWeight: FontWeight.w700,
            color: c.textPrimary,
            fontFeatures: tabularNums,
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text('组间休息', style: TextStyle(
          fontSize: AppFontSize.label,
          letterSpacing: 1.2,
          color: c.textTertiary,
        )),
        const SizedBox(height: AppSpacing.xxl),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
          child: PrimaryButton(
            label: '开始第 ${widget.nextSetNumber} 组',
            onPressed: widget.onBeginNextSet,
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 4: 写 `lib/features/workout/breathing_dot.dart`**

只做一个「它真的在走」的视觉暗示，**尊重系统「减弱动态效果」**。

```dart
import 'package:flutter/material.dart';

import '../../ui/theme.dart';

/// 休息计时旁的呼吸点。
///
/// 它存在的理由是：一个静止的 `00:00` 无法告诉用户计时到底有没有在跑。
class BreathingDot extends StatefulWidget {
  const BreathingDot({super.key});

  @override
  State<BreathingDot> createState() => _BreathingDotState();
}

class _BreathingDotState extends State<BreathingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    final dot = Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(color: c.accent, shape: BoxShape.circle),
    );

    // 系统开了「减弱动态效果」就不做呼吸，只留一个静止的点。
    // 规格 §6.4：两处动效都必须尊重这个开关。
    if (MediaQuery.disableAnimationsOf(context)) return dot;

    return FadeTransition(
      opacity: Tween<double>(begin: 0.35, end: 1.0).animate(_controller),
      child: dot,
    );
  }
}
```

- [ ] **Step 5: 在 Chrome 里目视确认**

**这一步现在只能确认编译通过** —— `DragNumber` / `Stepper` / `RestView` 要到
Task 18 组装进记录页才看得到。跑 `flutter analyze` 确认无错误即可。

- [ ] **Step 6: 提交**

```bash
git add lib/features/workout
git commit -m "feat(workout): 数值控件与休息界面 —— 拖动大跨度 + 步进器微调并存"
```

---

### Task 18: 动作条 + 动作选择弹层 + 记录页组装

**Files:**
- Create: `lib/features/workout/exercise_strip.dart`
- Create: `lib/features/workout/exercise_picker.dart`
- Create: `lib/features/workout/record_page.dart`
- Test: 无（界面层，见里程碑 D 开头的说明）

**Interfaces:**
- Consumes: `listExercises`、`ActiveSessionController`、Task 17 的 `DragNumber` / `Stepper` / `RestView`
- Produces: `ExerciseStrip`、`Future<Exercise?> showExercisePicker(BuildContext)`、`RecordPage({required String sessionId})`

> **`firstOrNull` 需要 `package:collection`**（Dart 的 `Iterable` 没有内置它）。
> 若不想引这个包，在文件内写一个私有 `T? _firstOrNull<T>(Iterable<T> it)` 辅助函数。

- [ ] **Step 1: 写动作选择弹层**

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/db/sql_executor.dart';
import '../../data/repositories/exercise_repo.dart';
import '../../domain/types.dart';
import '../../ui/theme.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/empty_state.dart';

/// 动作选择弹层：**按肌群分组、拼音序、带搜索**。
///
/// 这个弹层是旧项目 M2 那个**功能性缺口**的解药 ——
/// 当时「一次训练只能练一个动作」，用户真机用一次就发现换不了动作，
/// App 无法完成任何一次真实训练。这次它从第一版就在。
Future<Exercise?> showExercisePicker(BuildContext context) {
  return showModalBottomSheet<Exercise>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    builder: (_) => const _ExercisePickerSheet(),
  );
}

class _ExercisePickerSheet extends StatefulWidget {
  const _ExercisePickerSheet();
  @override
  State<_ExercisePickerSheet> createState() => _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends State<_ExercisePickerSheet> {
  List<Exercise>? _all;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final exec = context.read<SqlExecutor>();
    final list = await listExercises(exec);
    if (mounted) setState(() => _all = list);
  }

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    final all = _all;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      builder: (context, scrollController) {
        if (all == null) {
          return const Center(child: CircularProgressIndicator());
        }

        // 过滤 + 按肌群分组。**listExercises 已经按肌群名次 + 拼音序排好**，
        // 这里只需要按肌群切开，不要重排 —— 重排会让两处顺序不一致。
        final filtered = _query.isEmpty
            ? all
            : all.where((e) => e.name.contains(_query)).toList();

        final groups = <String, List<Exercise>>{};
        for (final e in filtered) {
          groups.putIfAbsent(e.muscleGroup ?? '其他', () => []).add(e);
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '搜索动作',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _query = v.trim()),
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? const EmptyState(message: '没有找到匹配的动作')
                  : ListView(
                      controller: scrollController,
                      children: [
                        for (final entry in groups.entries) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                                AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
                            child: Text(entry.key, style: TextStyle(
                              fontSize: AppFontSize.label,
                              letterSpacing: 0.8,
                              color: c.textTertiary,
                            )),
                          ),
                          for (final e in entry.value)
                            ListTile(
                              title: Text(e.name),
                              subtitle: e.equipment == null ? null : Text(e.equipment!),
                              onTap: () => Navigator.pop(context, e),
                            ),
                        ],
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}
```

- [ ] **Step 2: 写 `ExerciseStrip`**

```dart
import 'package:flutter/material.dart';

import '../../ui/theme.dart';
import '../../ui/tokens.dart';
import '../../state/active_session_controller.dart';

/// 顶部横向动作条 + `＋`。
///
/// **`SafeArea` 已由外壳负责**，这里不重复加 —— 但它是横向滚动的，
/// 最后一个 chip 之后要留出尾距，否则看起来像被截断。
class ExerciseStrip extends StatelessWidget {
  final List<ActiveExercise> exercises;
  final int currentIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onAdd;

  const ExerciseStrip({
    super.key,
    required this.exercises,
    required this.currentIndex,
    required this.onSelect,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
        children: [
          for (var i = 0; i < exercises.length; i++)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.sm),
              child: _chip(context, exercises[i].exerciseName, i == currentIndex,
                  () => onSelect(i)),
            ),
          // 旧项目另一处坑：训练里一个动作都没有时是条死路 ——
          // 空态只写了一句「这次训练还没有动作」，没有任何添加入口。
          // 所以这个 ＋ 永远在，无论当前有没有动作。
          GestureDetector(
            onTap: onAdd,
            child: Container(
              width: 44,
              height: 36,
              decoration: BoxDecoration(
                color: c.surfacePressed,
                borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                border: Border.all(color: c.border),
              ),
              child: Icon(Icons.add, size: 20, color: c.accent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String label, bool active, VoidCallback onTap) {
    final c = appColors(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: active ? c.accent.withValues(alpha: 0.16) : Colors.transparent,
          borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
          border: Border.all(color: active ? c.accent : c.border),
        ),
        child: Text(label, style: TextStyle(
          fontSize: AppFontSize.body,
          fontWeight: active ? FontWeight.w600 : FontWeight.w400,
          color: active ? c.accent : c.textSecondary,
        )),
      ),
    );
  }
}
```

- [ ] **Step 3: 写记录页，把上面三块组装起来**

`lib/features/workout/record_page.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../domain/types.dart';
import '../../state/active_session_controller.dart';
import '../../ui/theme.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/empty_state.dart';
import '../../ui/widgets/primary_button.dart';
import 'drag_number.dart';
import 'exercise_picker.dart';
import 'exercise_strip.dart';
import 'rest_view.dart';
import 'stepper.dart';

/// 记录页。**屏幕上只呈现当前这一组** —— 拇指永远停在同一个位置，
/// 不需要瞄准（规格 §6.1 的方案 B）。
///
/// 为什么不是全览列表：点击目标小、单手够不到顶部、改数值还要跳转。
class RecordPage extends StatefulWidget {
  final String sessionId;
  const RecordPage({super.key, required this.sessionId});

  @override
  State<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends State<RecordPage> {
  /// 用户此刻在编辑的数值。与库里那条占位组的值分开保存 ——
  /// 拖动过程中不该每一帧都写库，**只有点「完成这组」才落盘**。
  double? _weight;
  int? _reps;

  @override
  void initState() {
    super.initState();
    // 记录全程屏幕常亮 —— 组间放下手机时不该息屏
    WakelockPlus.enable();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final c = context.read<ActiveSessionController>();
      await c.resume();
      _syncFromPending(c);
    });
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    super.dispose();
  }

  /// 把编辑值同步成当前动作那条未完成占位组的值。
  ///
  /// 只在「切换动作」或「刚完成一组」时调用 —— 用户正在拖数字时不能覆盖他。
  void _syncFromPending(ActiveSessionController c) {
    if (!mounted) return;
    final pending = _pendingOf(c);
    if (pending == null) {
      setState(() { _weight = null; _reps = null; });
      return;
    }
    setState(() {
      _weight = pending.weight;
      _reps = pending.reps;
    });
  }

  /// 当前动作下那条**未完成的占位组** —— 界面靠它确定「现在该记哪一组」。
  ///
  /// 它不存在时 [ActiveSessionController.completeCurrentSet] 会静默 return，
  /// 所以这里为 null 就意味着「完成这组」不该可点。
  SetEntry? _pendingOf(ActiveSessionController c) {
    if (c.currentIndex < 0 || c.currentIndex >= c.exercises.length) return null;
    for (final s in c.exercises[c.currentIndex].sets) {
      if (!s.isCompleted) return s;
    }
    return null;
  }

  Future<void> _complete(ActiveSessionController c) async {
    final weight = _weight;
    final reps = _reps;
    if (weight == null || reps == null) return;

    // 一次轻微震动，**让用户不用盯着屏幕确认**（规格 §6.1）
    await HapticFeedback.lightImpact();

    await c.completeCurrentSet(weight, reps);
    _syncFromPending(c);
  }

  Future<void> _beginNextSet(ActiveSessionController c) async {
    await c.beginNextSet();
    _syncFromPending(c);
  }

  Future<void> _addExercise(ActiveSessionController c) async {
    final picked = await showExercisePicker(context);
    if (picked == null || !mounted) return;
    await c.addExercise(picked.id);
    _syncFromPending(c);
  }

  Future<void> _endWorkout(ActiveSessionController c) async {
    final id = await c.endWorkout();
    if (!mounted) return;
    if (id != null) context.go('/summary/$id');
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<ActiveSessionController>();
    final sc = appColors(context);

    final session = c.session;
    if (session == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('记录')),
        body: const EmptyState(message: '这场训练不在了，可能已被结束'),
      );
    }

    return Scaffold(
      appBar: AppBar(
        backgroundColor: sc.background,
        title: Text(session.name ?? '训练'),
        actions: [
          TextButton(
            onPressed: () => _endWorkout(c),
            child: const Text('结束训练'),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // ── 动作条：换动作不必退出记录界面 ──
            ExerciseStrip(
              exercises: c.exercises,
              currentIndex: c.currentIndex,
              onSelect: (i) {
                c.setCurrentIndex(i);
                _syncFromPending(c);
              },
              onAdd: () => _addExercise(c),
            ),

            Expanded(
              child: c.exercises.isEmpty
                  // 空训练**不是死路** —— 旧项目在这里踩过坑：
                  // 只写一句「这次训练还没有动作」，没有任何添加入口
                  ? EmptyState(
                      message: '这次训练还没有动作',
                      action: PrimaryButton(
                        label: '添加动作',
                        icon: Icons.add,
                        onPressed: () => _addExercise(c),
                      ),
                    )
                  : _body(c, sc),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(ActiveSessionController c, AppColors sc) {
    final active = c.exercises[c.currentIndex];
    final total = active.sets.length;
    final completed = active.sets.where((s) => s.isCompleted).length;
    final resting = active.sets
        .where((s) => s.isCompleted && s.restStartedAt != null)
        .firstOrNull;

    // ── 正在休息 ──
    if (resting != null) {
      return RestView(
        restStartedAt: resting.restStartedAt!,
        nextSetNumber: completed + 1,
        onBeginNextSet: () => _beginNextSet(c),
      );
    }

    final pending = _pendingOf(c);
    final weight = _weight ?? pending?.weight ?? 20;
    final reps = _reps ?? pending?.reps ?? 8;

    return Column(
      children: [
        const SizedBox(height: AppSpacing.lg),

        Text(active.exerciseName, style: TextStyle(
          fontSize: AppFontSize.title,
          fontWeight: FontWeight.w600,
          color: sc.textPrimary,
        )),
        const SizedBox(height: AppSpacing.xs),

        // 「第 N / M 组」——旧项目这里踩过「组数只是右上角小灰字，不显眼」，
        // 所以它现在是动作名正下方的一等信息
        Text('第 ${completed + 1} / $total 组', style: TextStyle(
          fontSize: AppFontSize.caption,
          color: sc.textSecondary,
          fontFeatures: tabularNums,
        )),

        const SizedBox(height: AppSpacing.lg),
        _lastPerformanceLine(active, sc),

        const Spacer(),

        DragNumber(
          value: weight,
          onChanged: (v) => setState(() => _weight = v),
        ),

        const SizedBox(height: AppSpacing.xl),
        Stepper(
          value: weight,
          onChanged: (v) => setState(() => _weight = v),
        ),

        const SizedBox(height: AppSpacing.lg),
        _repsRow(reps, sc),

        const Spacer(),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
          child: PrimaryButton(
            label: '✓ 完成这组',
            // 没有待完成的组时置灰 —— 那正是「点了没反应」的假死状态
            onPressed: pending == null ? null : () => _complete(c),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
      ],
    );
  }

  /// 「上次 40 kg × 8」。
  ///
  /// 常驻在动作名下方 —— 渐进超负荷最需要的就是这条信息。
  /// 它是**从上一次训练查出来的**，不是本场的。
  Widget _lastPerformanceLine(ActiveExercise active, AppColors sc) {
    final done = active.sets.where((s) => s.isCompleted).toList();
    if (done.isEmpty) return const SizedBox.shrink();
    final last = done.last;
    return Text(
      '本场上一组 ${_fmt(last.weight)} kg × ${last.reps}',
      style: TextStyle(
        fontSize: AppFontSize.caption,
        color: sc.textTertiary,
        fontFeatures: tabularNums,
      ),
    );
  }

  Widget _repsRow(int reps, AppColors sc) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text('次数', style: TextStyle(fontSize: AppFontSize.label, color: sc.textTertiary)),
        const SizedBox(width: AppSpacing.md),
        Stepper(
          value: reps.toDouble(),
          step: 1,
          max: 100,
          onChanged: (v) => setState(() => _reps = v.round()),
        ),
        const SizedBox(width: AppSpacing.md),
        SizedBox(
          width: 48,
          child: Text('$reps', textAlign: TextAlign.center, style: TextStyle(
            fontSize: AppFontSize.h2,
            fontWeight: FontWeight.w600,
            color: sc.textPrimary,
            fontFeatures: tabularNums,
          )),
        ),
      ],
    );
  }

  String _fmt(double v) =>
      v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(1);
}
```

- [ ] **Step 4: 让 `＋` 更好按，并接上「换一个动作不必退出记录页」的验证**

在 `exercise_picker.dart` 顶部确认 `SqlExecutor` provider 已被正确读取
（`context.read<SqlExecutor>()`）。若报 `ProviderNotFoundException`，
说明 `AppBootstrap` 的 `MultiProvider` 没包住路由 —— 检查 `providers.dart`。

- [ ] **Step 5: 在 Chrome 里走一遍完整流程**

1. 首页点「开始训练」→ 进入记录页，显示「这次训练还没有动作」+ 整宽「添加动作」
2. 点「添加动作」→ 弹层按肌群分组（胸在最前）
3. 搜索「深蹲」→ 列表过滤
4. 选中 → 动作条出现 chip，屏幕显示「深蹲 / 第 1 / 1 组 / 20 kg」
5. 拖动大数字到 40，点「✓ 完成这组」→ 切到休息页，正计时开始
6. 点「开始第 2 组」→ 回到记录态，组号变成「第 2 / 2 组」
7. 再点动作条的 `＋` 加一个动作 → 动作条两个 chip，可点着切换
8. 点「结束训练」→ 跳总结页

**任何一步不对就先修，再提交。**

- [ ] **Step 6: 提交**

```bash
git add lib/features/workout
git commit -m "feat(workout): 记录页组装 —— 聚焦当前组、动作条、空态不是死路"
```

---

### Task 19: 总结页

**Files:**
- Create: `lib/features/workout/summary_page.dart`

**Interfaces:**
- Consumes: `getSession`、`listSessionExercises`、`listSets`、`totalVolumeLoad`、`buildRestFeedback`
- Produces: `SummaryPage({required String sessionId})`

- [ ] **Step 1: 写总结页**

```dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../data/db/sql_executor.dart';
import '../../data/repositories/exercise_repo.dart';
import '../../data/repositories/session_repo.dart';
import '../../data/repositories/set_repo.dart';
import '../../domain/metrics.dart';
import '../../domain/rest_advice.dart';
import '../../domain/types.dart';
import '../../ui/theme.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/app_card.dart';
import '../../ui/widgets/primary_button.dart';
import '../../ui/widgets/stat_block.dart';

/// 训练总结。
///
/// **按路由参数 id 从库里读，不依赖 controller** —— 这正是 [endWorkout]
/// 敢于「结束就立刻清内存」的前提：总结页不受内存被清空的影响。
class SummaryPage extends StatefulWidget {
  final String sessionId;
  const SummaryPage({super.key, required this.sessionId});

  @override
  State<SummaryPage> createState() => _SummaryPageState();
}

class _SummaryPageState extends State<SummaryPage> {
  WorkoutSession? _session;
  List<_ExerciseSummary> _summaries = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final exec = context.read<SqlExecutor>();
    final session = await getSession(exec, widget.sessionId);
    final ses = await listSessionExercises(exec, widget.sessionId);

    final summaries = <_ExerciseSummary>[];
    for (final se in ses) {
      final sets = await listSets(exec, se.id);
      final done = sets.where((s) => s.isCompleted).toList();
      if (done.isEmpty) continue; // 空动作不上总结页
      final ex = await getExercise(exec, se.exerciseId);
      summaries.add(_ExerciseSummary(
        name: ex?.name ?? '未知动作',
        sets: done,
      ));
    }

    if (!mounted) return;
    setState(() {
      _session = session;
      _summaries = summaries;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final session = _session;
    if (session == null) {
      return const Scaffold(body: Center(child: Text('这场训练不存在')));
    }

    final finishedAt = session.finishedAt ??
        DateTime.now().millisecondsSinceEpoch;
    final durationSeconds = ((finishedAt - session.startedAt) / 1000).round();

    final allSets = _summaries.expand((s) => s.sets).toList();
    final volume = totalVolumeLoad(
      allSets.map((s) => SetLike(weight: s.weight, reps: s.reps, isCompleted: true)).toList(),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('训练总结'),
        backgroundColor: c.background,
        // 总结页**没有返回键** —— 结束是不可逆的，这里只给一个出口
        automaticallyImplyLeading: false,
      ),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screenH),
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              StatBlock(label: '时长', value: _minutes(durationSeconds), unit: '分'),
              StatBlock(label: '总组数', value: '${allSets.length}', unit: '组'),
              StatBlock(label: '总容量', value: volume.round().toString(), unit: 'kg'),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            // 规格附录的口径要求：容量必须写明它是「重量 × 次数」，
            // 且**不能写成「个人最好」** —— 容量是训练量，不是力量成绩
            '总容量（重量 × 次数）',
            style: TextStyle(fontSize: AppFontSize.label, color: c.textTertiary),
          ),
          const SizedBox(height: AppSpacing.xl),

          Text('组间休息回顾（粗略参考）', style: TextStyle(
            fontSize: AppFontSize.h2,
            fontWeight: FontWeight.w600,
            color: c.textPrimary,
          )),
          const SizedBox(height: AppSpacing.md),

          for (final s in _summaries) _exerciseCard(context, s),

          const SizedBox(height: AppSpacing.xl),
          PrimaryButton(
            label: '完成',
            onPressed: () => context.go('/'),
          ),
        ],
      ),
    );
  }

  String _minutes(int seconds) => (seconds / 60).round().toString();

  Widget _exerciseCard(BuildContext context, _ExerciseSummary s) {
    final c = appColors(context);
    final reps = s.sets.map((e) => e.reps).toList();
    final rests = s.sets.map((e) => e.restSeconds).toList();
    final feedback = buildRestFeedback(reps, rests);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.name, style: TextStyle(
              fontSize: AppFontSize.title,
              fontWeight: FontWeight.w600,
              color: c.textPrimary,
            )),
            const SizedBox(height: AppSpacing.sm),
            // ⭐ 原始次数数组**必须原样显示** —— 只给结论不给原始数字，
            // 用户无法核对，也不会相信
            Text(reps.join(' / '), style: TextStyle(
              fontSize: AppFontSize.title,
              color: c.textPrimary,
              fontFeatures: tabularNums,
            )),
            if (feedback != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(feedback.message, style: TextStyle(
                fontSize: AppFontSize.caption,
                color: _kindColor(c, feedback.kind),
              )),
            ] else ...[
              const SizedBox(height: AppSpacing.sm),
              // 组数 < 3 时明确沉默，不硬给建议
              Text('组数不足 3 组，暂不判断', style: TextStyle(
                fontSize: AppFontSize.caption, color: c.textTertiary,
              )),
            ],
          ],
        ),
      ),
    );
  }

  Color _kindColor(AppColors c, RestFeedbackKind kind) => switch (kind) {
        // 界面按 kind 上色，**不解析 message** —— 文案改了类型还在
        RestFeedbackKind.positive => c.success,
        RestFeedbackKind.addWeight => c.accent,
        _ => c.textSecondary,
      };
}

class _ExerciseSummary {
  final String name;
  final List<SetEntry> sets;
  const _ExerciseSummary({required this.name, required this.sets});
}
```

- [ ] **Step 2: 在 Chrome 里跑一遍完整流程**

开训练 → 加动作 → 完成 3 组 → 结束 → 看总结页三个数字与次数数组。
**手工核算**：3 组 × (20kg × 8) = 480，页面必须显示 480。

- [ ] **Step 3: 提交**

```bash
git add lib/features/workout/summary_page.dart
git commit -m "feat(workout): 总结页 —— 三数字 + 次数数组原样 + 粗略提示"
```

---

### Task 20: 主题三态与设置页

**Files:**
- Create: `lib/state/theme_controller.dart`
- Create: `lib/features/settings/settings_page.dart`

**Interfaces:**
- Consumes: `getThemeMode` / `setThemeMode`
- Produces: `class ThemeController extends ChangeNotifier { AppThemeMode mode; Future<void> load(); Future<void> setMode(AppThemeMode); }`

- [ ] **Step 1: 写 `lib/state/theme_controller.dart`**

```dart
import 'package:flutter/foundation.dart';

import '../data/db/sql_executor.dart';
import '../data/repositories/settings_repo.dart';

/// 主题偏好的编排层。
///
/// 四条实现约定（规格 §6.5），每条都对应一个真实问题：
/// 1. 偏好存 `app_setting`（迁移 v2 引入）
/// 2. **非法值退回 system**（`getThemeMode` 负责）——
///    主题读不出来不该让 App 起不来
/// 3. **先改内存再写库，写库失败不回滚** ——
///    用户在设置页点一下必须立刻变色，不能等一次磁盘往返
/// 4. 偏好读出来之前不放行子树（由 `AppProviders` 负责），
///    否则每次启动都会闪一帧
class ThemeController extends ChangeNotifier {
  final SqlExecutor _exec;

  ThemeController(this._exec);

  AppThemeMode mode = AppThemeMode.system;

  Future<void> load() async {
    mode = await getThemeMode(_exec);
    notifyListeners();
  }

  Future<void> setMode(AppThemeMode next) async {
    if (next == mode) return;
    // 先改内存 —— 立刻变色
    mode = next;
    notifyListeners();
    try {
      await setThemeMode(_exec, next);
    } catch (_) {
      // 写库失败**不回滚**：用户看到的颜色是对的，下次启动会退回旧值。
      // 相比「点了没反应」，这个失败模式更容易接受。
    }
  }
}
```

- [ ] **Step 2: 写设置页**

```dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/settings_repo.dart';
import '../../state/theme_controller.dart';
import '../../ui/theme.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/app_card.dart';
import '../../ui/widgets/segmented_control.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    final theme = context.watch<ThemeController>();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.screenH),
      children: [
        const SizedBox(height: AppSpacing.xl),
        Text('设置', style: TextStyle(
          fontSize: AppFontSize.h1, fontWeight: FontWeight.w700, color: c.textPrimary)),
        const SizedBox(height: AppSpacing.xl),

        Text('外观', style: TextStyle(
          fontSize: AppFontSize.label, letterSpacing: 0.8, color: c.textTertiary)),
        const SizedBox(height: AppSpacing.sm),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('主题', style: TextStyle(
                fontSize: AppFontSize.title, color: c.textPrimary)),
              const SizedBox(height: AppSpacing.md),
              // 三态，不是布尔 —— 布尔表达不了「跟随系统」，
              // 而它才是默认值、也是大多数人想要的
              SegmentedControl<AppThemeMode>(
                options: AppThemeMode.values,
                value: theme.mode,
                labelOf: (m) => switch (m) {
                  AppThemeMode.system => '跟随系统',
                  AppThemeMode.light => '浅色',
                  AppThemeMode.dark => '深色',
                },
                onChanged: (m) => context.read<ThemeController>().setMode(m),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
```

- [ ] **Step 3: 在 Chrome 里确认三态都生效**

切「浅色」应立刻变暖白底、橙变深一档；切「跟随系统」应跟随 Chrome 的偏好。

- [ ] **Step 4: 提交**

```bash
git add lib/state/theme_controller.dart lib/features/settings
git commit -m "feat(settings): 主题三态，先改内存再写库"
```

---

## 里程碑 E：验收

### Task 21: 静态检查与全量测试

- [ ] **Step 1: 静态分析**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 2: 全量测试（含 e2e）**

Run: `flutter test`
Expected: `All tests passed!`，断言数 **不少于 120 条**

- [ ] **Step 3: 构建一次真机可装的 APK**

Run: `flutter build apk --debug`
Expected: 产出 `build/app/outputs/flutter-apk/app-debug.apk`，且**记录它的字节数**

> 这一步的价值（旧文档 §7.1）：`tsc` 与 `jest` 都覆盖不到「整个 App 到底打不打得成包」。
> 在插上真机之前先确认能打包。

- [ ] **Step 4: 提交**

```bash
git add -A
git commit -m "chore: Phase 1 静态检查与全量测试通过"
```

---

### Task 22: 真机验收

> **这一节必须如实记录结果。** 旧项目最后一轮的 12 项真机验收**全部未做**
> （收尾机器 `adb devices` 为空），文档里如实写成「未做」而不是「通过」。
> **静态自查不等于验收。**

**设备**：________（填写型号 / Android 版本）
**构建**：`app-debug.apk`，______ 字节，安装时间 ________
**验证方式**：`adb shell input tap|swipe` 驱动 + `adb shell screencap` 截图取证

- [ ] **Step 1: 连接设备并常驻 adb**

```powershell
adb devices -l                                  # 必须有设备
adb shell svc power stayon usb                  # USB 连接时不息屏
```

> **`stayon usb` 不是可选的。** 手机自动锁屏后 `adb shell screencap` 会返回
> **上一帧而不是报错** —— 旧项目因此拿到过一张和半小时前**哈希完全相同**的
> 「新」截图，并一度据此得出错误结论。核对前台窗口用：
> `adb shell uiautomator dump`

- [ ] **Step 2: 安装并启动**

```powershell
adb install -r build\app\outputs\flutter-apk\app-debug.apk
adb shell am start -n com.mobis.gym_tracker/.MainActivity
```

- [ ] **Step 3: 成功标准 1 —— 一组做完到记录完成 ≤ 2 次点击**

- [ ] 点「✓ 完成这组」即完成记录（**1 次点击**）
- [ ] 点「开始第 N 组」回到记录态（**1 次点击**）
- [ ] 全程无需手动输入数字（数值预填上一组）
- [ ] 数值可用**拖动**调整，不必一下下点加减

**证据**（截图 + 描述）：________________________________

- [ ] **Step 4: 成功标准 2 —— 记录过程不打断训练节奏**

- [ ] 训练期间屏幕保持常亮
- [ ] 完成一组有轻微震动反馈
- [ ] 组间休息是**正计时**，不催促
- [ ] 换动作不必退出记录界面（顶部动作条 + `＋`）

**证据**：________________________________

- [ ] **Step 5: 成功标准 3 ⭐ —— 训练记录永不丢失**

- [ ] 完成 3 组后强杀 App（`adb shell am force-stop com.mobis.gym_tracker`），重开后「继续上次训练」出现
- [ ] 进入后已完成的组数正确
- [ ] **息屏挂起后计时仍然准确** —— 记录息屏前的读数、息屏时长、亮屏后的读数

**证据**（这是本轮最关键的验证）：

| 检查项 | 结果 |
|---|---|
| 完成 2 组后强杀 → 重开 | ______ |
| 息屏前计时 | ______ |
| 息屏 ____ 秒 + 亮屏后 | ______ |
| Δ 与实测等待时间 | ______ |

> 最后一条证明的是「计时基于 `rest_started_at` 时间戳而不是累加计数器」。
> **若用计数器，息屏挂起时它会冻住不动。**

- [ ] **Step 6: 成功标准 4 —— 结束后能看到次数对比与粗略提示**

- [ ] 顶部三个数字：时长 / 总组数 / 总容量
- [ ] 卡片第一行是**原始次数数组**
- [ ] 提示文案与次数数组一致
- [ ] 页面标注了**「粗略参考」**
- [ ] 少于 3 组显示**「组数不足 3 组，暂不判断」**

**手工核算**：____ 组 × (____ kg × ____ 次) = **____ kg**，与页面显示一致

- [ ] **Step 7: 数据落地检查**

- [ ] 点「完成」后回到训练页
- [ ] 训练页**不再显示**「继续上次训练」
- [ ] 重启 App 后无残留进行中的训练
- [ ] 从零建库：清空 App 数据（`pm clear`）后重新打开，4 张表 + 52 个动作全部建出

- [ ] **Step 8: 把结果如实写进本文档**

在上面每一处「证据」填真实结果。**未做的项明确写「未做」，不要留空、不要写「通过」。**

- [ ] **Step 9: 提交**

```bash
git add docs/superpowers/plans
git commit -m "docs: Phase 1 真机验收结果（如实记录，未做的项明确标注）"
```

---

## 完成定义（Definition of Done）

Phase 1 完成的条件，**缺一不可**：

1. `flutter analyze` 无问题
2. `flutter test` 全绿，断言数不少于 120 条
3. `test/layering_test.dart` 的 5 条规则全绿，**且有人为破坏验证过它真的会红**
4. Chrome 预览能走通「开训练 → 加动作 → 完成 3 组 → 结束 → 看总结」全流程
5. `flutter build apk --debug` 成功产出 APK
6. **Task 22 的 4 条成功标准 + 数据落地检查在真机上逐条跑过，结果如实记录**
7. `docs/superpowers/plans/dev-environment-notes.md` 记录了实际环境、三条已知风险的实际结论、以及所有偏离本计划的地方

---

## 与规格的覆盖对照

| 规格章节 | 由哪个 Task 实现 |
|---|---|
| §2.1 目录结构 | Task 1–20 |
| §2.2 三条分层规则 → 测试 | **Task 4** |
| §2.3 domain 不依赖 Flutter | Task 4（规则 3） |
| §2.4 技术选型 | Task 0 |
| §2.5 删掉 demoExecutor / preview | Task 0（不创建即达成）+ Task 15（database.dart 三后端） |
| §2.6 SqlExecutor 两条语义 | Task 5 |
| §3.2 schema v1 + 全局约定 | Task 5 |
| §3.3 迁移只追加 | Task 5 |
| §3.4 不能省的 SQL（rowid / 四步 / 时间戳 / cancelRest） | Task 5、7、8 |
| §4.1 容量负荷口径 | Task 1 |
| §4.2 e1RM 口径与 null 处理 | Task 1、19 |
| §4.3 休息提示 5 分支 + 正反馈 | **Task 2** |
| §5.3 startNew 调用顺序 | Task 10 |
| §5.4 冲突三按钮 | **Task 16** |
| §5.5 endWorkout 立刻清内存 | Task 11 |
| §5.6 resume 定位 | Task 10 |
| §5.7 加动作预建第一组 | Task 10 |
| §5.8 防御性闸门 | Task 10、11 |
| §6.1 记录页聚焦当前组 | **Task 18** |
| §6.2 拖动 + 步进器并存 | **Task 17**（控件）+ Task 18（组装） |
| §6.3 动作条 + 弹层 | Task 18 |
| §6.4 视觉规范 | Task 13、14 |
| §6.5 主题三态 | Task 20 |
| §7.1 三层验证 | Task 1–11（分层）、Task 12（e2e）、Task 22（真机） |
| §7.2 测试纪律 | 贯穿全部 Task；e2e 的排除方式见 Task 12 Step 3 |
| §7.3 验收标准 | **Task 22** |
| §7.4 真机验收方法论 | Task 22 Step 1 |
| §8 环境搭建与三条已知风险 | **Task 0** |
| §9.1 明确不做 | 不创建对应实现即达成 |
| 规格 §2.3 五个已知坑 | Task 18（换动作 / 空态不是死路）、Task 15（安全区）、Task 17+18（拖动+步进）、Task 10（30 分钟闸门）、Task 18（组数信息层级） |

### 覆盖检查的结论

逐条走查规格后，**没有发现「规格里有要求但计划里没有 Task」的缺口**。

有一处**规格与计划的措辞差异**需要说明：规格 §3.3 的迁移表把 v2（`app_setting`）
归给「主题三态」，而本计划把 v2 放在 **Task 5**（与 v1 一起建立迁移框架）而不是
Task 20（主题三态）。原因是迁移框架必须一次建对、且**只追加**，
把 v2 留到最后一个 Task 会让中间的每一次测试都跑在一个「迁移表不完整」的库上。
Task 20 只消费 v2 建出来的表，不修改迁移。
