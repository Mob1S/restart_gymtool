# 开发环境笔记（Task 0 产出）

> 这份笔记是后续所有 Task 的排障依据。记录的是**这台机器上实测到的**事实，
> 不是对旧文档结论的复述 —— 旧文档的三条风险逐条实测过，见 §4。

**实测日期**：2026-10-08
**机器**：Windows 11 家庭版 中文版 64-bit，24H2，build 10.0.26100.4946，`mob1s\mobis`
**工作目录**：`C:\ccproject\restart_gymtool`
**Task 0 结论**：**通过**。工程可 `flutter test` 全绿，可在 Chrome 上跑起来。

---

## 1. 实际版本号（全部实测，非计划值）

| 组件 | 实际版本 | 位置 |
|---|---|---|
| Flutter SDK | **3.47.6** stable，revision `5fc346839b`（2026-09-30） | `.tooling\flutter` |
| Dart | **3.13.5**（2026-09-29） | `.tooling\flutter\bin\cache\dart-sdk` |
| DevTools | **2.60.0** | — |
| Engine | revision `692136cb65` | — |
| JDK | **Temurin 17.0.20.1+1**（`openjdk version "17.0.20.1" 2026-08-18`） | `.tooling\jdk\jdk-17.0.20.1+1` |
| Android cmdline-tools | **12.0**（zip `commandlinetools-win-11076708_latest.zip`） | `.tooling\android-sdk\cmdline-tools\latest` |
| Android platform-tools | **37.0.1**（`Android Debug Bridge version 1.0.41`） | `.tooling\android-sdk\platform-tools` |
| Android platforms | **android-36**（Flutter 3.47.6 要求）与 android-35 | `.tooling\android-sdk\platforms` |
| Android build-tools | **36.0.0** 与 **35.0.0** | `.tooling\android-sdk\build-tools` |
| Chrome | **154.0.8037.93** | `C:\Program Files (x86)\Google\Chrome\Application\chrome.exe` |
| Visual Studio | Community 2022 17.11.35222.181（Windows 10 SDK 10.0.22621.0） | `C:\vs2022` |

Flutter 计划值写的是 3.47.6 / Dart 3.13.5，**实测完全一致**。

### 关键 pub 依赖版本（`flutter pub add` 解析结果）

```
sqflite 2.4.4+1            go_router 18.0.2        uuid 4.6.0
sqflite_common 2.5.13+1    provider 6.1.5+1        wakelock_plus 1.8.1
sqflite_common_ffi 2.4.3   sqlite3 3.5.2           flutter_lints 6.0.0
sqflite_common_ffi_web 1.2.0
```

生成 `web/sqlite3.wasm` 时另外被动引入了：webdev 4.0.3（全局激活）、sqlite3.wasm **748686 字节**、sqflite_sw.js **263881 字节**。

### 磁盘占用

`.tooling` 合计 **6,456 MB**（Flutter 3112 + Android SDK 637 + JDK 303 + pub-cache 232 + 三个 zip 保留 2172）。
三个 zip（`flutter.zip` 1844 MB、`jdk.zip` 182 MB、`cmdline-tools.zip` 146 MB）**保留未删**，
确认环境稳定后可安全删除以回收 2.1 GB。C: 盘剩余 155.7 GB。

---

## 2. `flutter doctor -v` 完整原文

```
[√] Flutter (Channel stable, 3.47.6, on Microsoft Windows [版本 10.0.26100.4946], locale zh-CN) [416ms]
    • Flutter version 3.47.6 on channel stable at C:\ccproject\restart_gymtool\.tooling\flutter
    • Upstream repository https://github.com/flutter/flutter.git
    • Framework revision 5fc346839b (7 days ago), 2026-09-30 15:02:49 -0700
    • Engine revision 692136cb65
    • Dart version 3.13.5
    • DevTools version 2.60.0
    • Feature flags: enable-web, enable-linux-desktop, enable-macos-desktop, enable-windows-desktop, enable-android, enable-ios, cli-animations, enable-native-assets, enable-record-use, enable-swift-package-manager, omit-legacy-version-file, enable-lldb-debugging, enable-uiscene-migration

[√] Windows Version (11 家庭版 中文版 64-bit, 24H2, 2009) [5.0s]

[√] Android toolchain - develop for Android devices (Android SDK version 36.0.0) [2.5s]
    • Android SDK at C:\ccproject\restart_gymtool\.tooling\android-sdk
    • Emulator version unknown
    • Platform android-36, build-tools 36.0.0
    • ANDROID_HOME = C:\ccproject\restart_gymtool\.tooling\android-sdk
    • ANDROID_SDK_ROOT = C:\ccproject\restart_gymtool\.tooling\android-sdk
    • Java binary at: C:\ccproject\restart_gymtool\.tooling\jdk\jdk-17.0.20.1+1\bin\java
      This JDK is specified by the JAVA_HOME environment variable.
      To manually set the JDK path, use: `flutter config --jdk-dir="path/to/jdk"`.
    • Java version OpenJDK Runtime Environment Temurin-17.0.20.1+1 (build 17.0.20.1+1)
    • All Android licenses accepted.

[√] Chrome - develop for the web [342ms]
    • Chrome at C:\Program Files (x86)\Google\Chrome\Application\chrome.exe

[√] Visual Studio - develop Windows apps (Visual Studio Community 2022 17.11.2) [341ms]
    • Visual Studio at C:\vs2022
    • Visual Studio Community 2022 version 17.11.35222.181
    • Windows 10 SDK version 10.0.22621.0

[√] Connected device (3 available) [333ms]
    • Windows (desktop) • windows • windows-x64    • Microsoft Windows [版本 10.0.26100.4946]
    • Chrome (web)      • chrome  • web-javascript • Google Chrome 154.0.8037.93
    • Edge (web)        • edge    • web-javascript • Microsoft Edge 154.0.4258.53

[√] Network resources [875ms]
    • All expected network resources are available.

• No issues found!
```

> **注意**：第一次 doctor（装 android-35 时）Android toolchain 是 `[!]`，原文是：
> `X Flutter requires Android SDK 36 and the Android BuildTools 28.0.3`。
> 装上 `platforms;android-36` + `build-tools;36.0.0` 后转绿。见 §5 偏离说明。
> 计划 Step 4 写的是 `platforms;android-35`，对 3.47.6 来说**不够**。

---

## 3. 两个冒烟测试的结果

命令：`flutter test test/smoke/database_smoke_test.dart -v`
结果：**`All tests passed!`，2 个测试，退出码 0**

```
00:00 +0: (setUpAll)
00:00 +0: 内存库能建表、能写、能读回
00:00 +1: PRAGMA foreign_keys 能打开，级联删除生效
00:00 +2: (tearDownAll)
00:00 +2: All tests passed!
```

1. **初始库能建表读写** —— PASS。`databaseFactoryFfi.openDatabase(inMemoryDatabasePath)` 可用，
   `CREATE TABLE` / `INSERT` / `query` 全通，读回的 `n == 42`。
2. **`PRAGMA foreign_keys` 级联删除生效** —— PASS。开 PRAGMA 后建 parent/child（`ON DELETE CASCADE`），
   删 parent 后 child 表为空。**这条证明了连接级 PRAGMA 在本后端上真的生效**，
   规格 §3 那条「不开 PRAGMA 则 CASCADE 静默失效」的前提是可满足的。

附带：`flutter test`（整个套件，含 `flutter create` 生成的 `test/widget_test.dart`）也是
**`All tests passed!`，3 个测试，退出码 0** —— 后续 Task 的「全绿」基线是干净的。

### `--concurrency=1` 需要吗？→ **不需要**

默认并发下直接跑过，**没有出现 `spawn EPERM`，没有出现任何子进程 / 管道 stdio 相关报错**。
`flutter test` 的 flutter_tester 子进程正常 spawn、正常回收。
后续 Task 遇到间歇性 EPERM 时再考虑 `--concurrency=1`，但目前完全不必。

---

## 4. 三条已知风险的实际结论（逐条实测）

| # | 规格 §8 记录的旧风险 | 实测结论 |
|---|---|---|
| 1 | 子进程管道 stdio 被禁 → `flutter test` 可能需要 `--concurrency=1` | **不成立**。默认并发下 `flutter test` 全绿，无 EPERM。 |
| 2 | 沙箱外的家目录不可写 → 需重定向 `USERPROFILE`/`APPDATA`/`LOCALAPPDATA` | **不成立**（实测真实家目录可写）。仍按计划保留了重定向，理由见 §5-2。 |
| 3 | 网络下载量上限 → 大件下载需分段验证 | **不成立**（在本次实测范围内）。单次会话共拉取约 **3.5 GB** 无上限拦截。 |

### 风险 1 的证据

`flutter test test/smoke/database_smoke_test.dart -v` 未加任何并发参数即通过。
测试进程输出证实子进程链正常：`frontend_server_aot.dart.snapshot` 编译 → `flutter_tester.exe`
spawn（pid 262440）→ 连接 → 跑完 → 退出 → 清理临时目录。全程无 stdio 报错。

### 风险 2 的证据

在**未重定向**的真实家目录下逐个实测：

```
HOME FILE WRITE OK: C:\Users\mobis\cc_probe_119105573.txt
HOME FILE DELETE OK
HOME MKDIR OK                              (C:\Users\mobis\cc_probe_dir_*)
APPDATA MKDIR OK / RMDIR OK                (C:\Users\mobis\AppData\Roaming)
LOCALAPPDATA MKDIR OK / RMDIR OK           (C:\Users\mobis\AppData\Local)
```

另一条独立证据：**VS Code 的 Dart/Flutter 扩展在真实家目录里成功写入了 610 MB 的 pub 缓存**
（`C:\Users\mobis\AppData\Local\Pub\Cache`，209 个包）。如果家目录不可写，这是不可能的。

### 风险 3 的证据

单次会话内实际拉取量（全部走通，无截断、无配额报错）：

| 对象 | 大小 | 来源 |
|---|---|---|
| `flutter_windows_3.47.6-stable.zip` | 1,933,193,895 B（1844 MB） | storage.googleapis.com |
| Temurin JDK 17 zip | 190,817,615 B（182 MB） | api.adoptium.net |
| `commandlinetools-win-11076708_latest.zip` | 153,583,359 B（146 MB） | dl.google.com |
| Android SDK 组件（platform-tools + 2×platform + 2×build-tools） | 约 490 MB | dl.google.com |
| pub 包（两个缓存合计去重前） | 约 840 MB | pub.dev |
| `sqlite3.wasm` | 748,686 B | github.com |
| **合计** | **约 3.5 GB** | — |

**但这次实测暴露了一条计划没写的、真实存在的网络风险**（见 §6-1 与 §6-3）：
`pub.dev` 会间歇性 **socket 超时**（`errno = 121 信号灯超时时间已到`），
以及 `curl.exe` 的 **schannel 吊销检查失败**。这两条都不是「下载量上限」，但会实际卡住流程。

---

## 5. 偏离计划的地方（逐条说明理由）

### 5-1. 用 `tar.exe` 解压而不是 `Expand-Archive`

计划 Step 2 用 `Expand-Archive`。Flutter zip 解压后是 **1844 MB / 约 3 万个文件**，
PowerShell 5.1 的 `Expand-Archive` 在这种规模下会慢到不可用（常以小时计）。
改用 Windows 自带的 `C:\WINDOWS\system32\tar.exe`（bsdtar 3.8.1），全部三个包合计几分钟解完。
**命令语义等价，产物相同**。

### 5-2. `scripts/env.ps1` 比计划 Step 1 多做了三件事

计划 Step 1 只给了 9 个环境变量的赋值。实际写入 `scripts/env.ps1` 的版本另外做了：

1. **按存在性追加 `JAVA_HOME`** —— 计划 Step 3 在命令行里临时设 `$env:JAVA_HOME`，
   但每个 Task 都靠 dot-source 本脚本起步，不写进去的话每个新 shell 都会「找不到 java」，
   Android 构建与 `sdkmanager` 直接失效。
2. **把 `flutter\bin`、`platform-tools`、`cmdline-tools\latest\bin`、`%JAVA_HOME%\bin` 前插到 `PATH`** ——
   同理，否则每个新 shell 都要手敲绝对路径。
3. **建目录时一并把 `pub-cache` / `gradle` / `android-sdk` 建出来** —— 避免 Flutter/Gradle 首次运行时
   因父目录不存在而报错。

**计划 Step 1 的 9 行赋值原样保留，一行没改。**

另外：**重定向本身在实测中被证明非必需**（§4 风险 2 不成立），但仍按计划保留，
理由是它让工程自包含、`.tooling/` 已在 `.gitignore` 里、且能防住「换一台真的禁写家目录的机器」。
**代价见 §6-4。**

### 5-3. Android platform 从 35 改成同时装 36

计划 Step 4 写 `"platforms;android-35" "build-tools;35.0.0"`。实测 `flutter doctor` 报：

```
[!] Android toolchain - develop for Android devices (Android SDK version 35.0.0)
    X Flutter requires Android SDK 36 and the Android BuildTools 28.0.3
```

Flutter 3.47.6 要求 **Android SDK 36**（计划里的 35 是按更早的 Flutter 写的）。
**保留 35，另外补装 `platforms;android-36` 与 `build-tools;36.0.0`**，doctor 转绿。
两个版本都在，不需要谁去改 `compileSdk`。

### 5-4. **跳过了 `flutter pub add dev:sqflite_common_ffi`**（计划 Step 6 第二条命令）

该命令**失败**，原文：

```
"sqflite_common_ffi" is already in "dependencies". Use "pub remove sqflite_common_ffi"
to remove it before adding it to "dev_dependencies"
Failed to update packages.
（退出码 65）
```

计划在同一步里先 `flutter pub add sqflite ... sqflite_common_ffi ...` 再 `pub add dev:sqflite_common_ffi`，
**自相矛盾**。没有执行 `pub remove`（那会把依赖从 `dependencies` 抹掉）。

**不做任何补救是正确选择**：Task 5 要写的 `lib/data/db/ffi_executor.dart` 位于 `lib/`，
它 `import 'package:sqflite_common_ffi/sqflite_common_ffi.dart'` ——
**这是运行时依赖，本来就必须留在 `dependencies`，不能进 `dev_dependencies`**。
计划 Step 6 的第二条命令应当删除。

### 5-5. 生成 wasm 的命令用了 `dart run` 而非 `flutter pub run`

计划 Step 7 写的是 `dart run sqflite_common_ffi_web:setup`（正确）。
第一次我误用了 `flutter pub run`，同样会执行并在内部调 `dart pub global activate webdev`。
**最终成功的一次用的是计划原文的 `dart run`**（加 `--verbose`）。

### 5-6. `sqflite_common_ffi_web:setup` 顺带装了全局 `webdev`

这不是偏离，是**该工具自身的固有行为**，但很重要，写下来免得后面的人以为工程被污染：

- 它在 `.dart_tool\sqflite_common_ffi_web\setup\1.2.0\` 下**复制了一份源码副本**，
  在那个副本里 `dart pub add dev:webdev` + `dart pub get` + `webdev build`。
- 因此 **工程根目录的 `pubspec.yaml` 没有被改动**（已确认：dependencies 只有计划里那 8 个 + cupertino_icons）。
- 同时它 `dart pub global activate webdev` 装到了 `PUB_CACHE\bin`。
- 重跑是幂等的（第二次会打印 `binaries up to date`）。

### 5-7. Step 11「提交」**没有执行**

任务约束明确禁止执行任何 git 命令，提交由主 agent 负责。故 `.tooling/`、工程骨架、
`scripts/env.ps1`、`test/smoke/`、`docs/.../dev-environment-notes.md` 目前**均未提交**。

---

## 6. 实际踩到的坑（计划没预见到，后续 Task 会再遇到）

### 6-1. `curl.exe` 的 schannel 吊销检查失败 —— **最坑的一条**

在这台机器上，`curl.exe` 对**部分** HTTPS 站点直接失败：

```
curl: (35) schannel: next InitializeSecurityContext failed:
CRYPT_E_NO_REVOCATION_CHECK (0x80092012) - 吊销功能无法检查证书是否吊销
```

**14 秒就失败**，看起来像网络封禁，实际不是。命中过：`api.adoptium.net`（JDK）、
`github.com`（sqlite3.wasm）。而 `storage.googleapis.com`、`dl.google.com`、`pub.dev` 正常。

**解法：给 `curl.exe` 加 `--ssl-no-revoke`。** 加上之后 JDK 与 github 全部一次成功：

```
https://github.com/simolus3/sqlite3.dart/releases/download/sqlite3-3.6.0/sqlite3.wasm
http=200 size=748686 time=1.82s
```

**关键结论（已被 Task 21 修正，见 §10）：这只是 `curl.exe`（Windows TLS 后端）
的表现**，不是网络封禁。**Dart 用自己的 TLS 栈，不受影响** ——
`sqflite_common_ffi_web:setup` 从 github.com 拉 sqlite3.wasm 是一次成功的，
`flutter pub add` 从 pub.dev 拉 49 个包也正常。

> ⚠️ **本节的原始结论「Flutter/Dart 侧不用做任何处理」是只对了一半的。**
> 当时只探了 Dart 与 curl 两条路，**漏了第三条：Java**。
> Task 21 构建 APK 时被同一条根因打死（`PKIX path building failed`），
> 详见 §10 —— 那里有完整根因与证据。**这一段保留原文，因为它记录的是
> 「当时的判断」与「后来被什么推翻」。**

### 6-2. `sdkmanager --licenses` 不能靠 PowerShell 管道喂 `y`

计划 Step 4 写「一路输入 y」。实测：

- `$yes | & $sdkmanager --licenses` —— **失败**。PowerShell 的管道到 `sdkmanager.bat`（经由 cmd.exe）
  时 stdin 送不进去，结果 `7 of 7 SDK package licenses not accepted`，后面装组件全部 `Skipping`。
- **可行解法**：把 y 写进文件，用 cmd.exe 重定向。

```powershell
Set-Content -Path "$root\yes.txt" -Value ("y`r`n" * 200) -NoNewline -Encoding ascii
cmd.exe /c "`"$sdkmanager`" --sdk_root=$sdk --licenses < `"$root\yes.txt`" 2>&1"
```

成功输出 `All SDK package licenses accepted`，`$sdk\licenses\` 下出现 7 个许可文件。

另一个必须注意的点：**`cmd.exe /c` 起的进程不会自动继承 PowerShell 的 `$env:` 变量除非先 dot-source**
—— 第一次失败的真实原因是没 dot-source `env.ps1`，`JAVA_HOME` 没设，sdkmanager 直接报
`ERROR: JAVA_HOME is not set and no 'java' command could be found in your PATH.`

### 6-3. `pub` 会间歇性 socket 超时（**后续 Task 一定会再遇到**）

`dart pub global activate webdev` 第一次跑，**卡了 17 分钟**，最后失败：

```
SLVR: Version solving took 0:04:36.905403 seconds.
ERR : Got socket error trying to find package yaml at https://pub.dev.
FINE: Wrapped exception: ClientException with SocketException:
      信号灯超时时间已到 (OS Error: 信号灯超时时间已到, errno = 121),
      address = pub.dev, port = 55126, uri=https://pub.dev/api/packages/yaml
（退出码 69）
```

`errno 121` = `ERROR_SEM_TIMEOUT`。特征是：**version solving 阶段要拉约 200 个包的元数据，
耗时以分钟计，其中任何一个连接超时都会让整次失败。**

**同一命令直接重跑就成功了**（退出码 0，装上 webdev 4.0.3）。原因是 pub 会把
版本元数据缓存到 `PUB_CACHE\hosted\pub.dev\.cache\`，第二次省掉了那 4 分半钟。

> **后续 Task 的应对**：
> 1. `pub` 命令超过 10 分钟**不要判定失败**，先检查 `PUB_CACHE` 有没有在增长；
> 2. 失败就**原样重跑**，第二次通常几十秒；
> 3. 实在反复失败，再考虑 `$env:PUB_HOSTED_URL = "https://pub.flutter-io.cn"` ——
>    实测该镜像 **11 ms** 响应（pub.dev 是 76 ms），明显更快。但**换镜像会重建一份
>    `hosted\pub.flutter-io.cn\` 缓存**，已下载的 232 MB 用不上，所以只作为最后手段。

### 6-4. 注意： `PUB_CACHE` 重定向被 VS Code 扩展绕过了（**后续 Task 必须知道**）

这是本次最值得注意的发现。

工程里 `.dart_tool\package_config.json` 解析出的**所有三方包路径都指向真实家目录**：

```
file:///C:/Users/mobis/AppData/Local/Pub/Cache/hosted/pub.dev/...     ← 209 个包，610 MB
```

**不是**我们重定向的 `.tooling\pub-cache`（那里有 155 个包，232 MB）。

原因：**VS Code 的 Dart/Flutter 扩展**（进程 `dart language-server --client-id=VS-Code`、
`tooling-daemon --machine`、`devtools --machine`）在检测到新工程后自己跑了一次 `pub get`，
它**继承了 VS Code 进程的原始环境，没有 `PUB_CACHE` 重定向**，于是把包装进了真实家目录，
并改写了 `package_config.json`。

**影响与应对：**

- **目前无害** —— 两个缓存里都有需要的包，`flutter test` 全绿，`flutter run -d chrome` 正常。
  这也再次印证 §4 风险 2 不成立（家目录确实可写，610 MB 都写进去了）。
- **但 `PUB_CACHE` 重定向在 VS Code 在场时不生效**。谁要严格保证「一切都在工程内」，
  得关掉 VS Code 的 Dart 扩展，或在 VS Code 的设置里也注入 `PUB_CACHE`。
- **`env.ps1` 必须继续每会话 dot-source**（本次全程如此）。我们自己的命令走
  `.tooling\pub-cache`，扩展走真实家目录，两边都完整，任何一边都能独立解析依赖。

### 6-5. 首次 `flutter --version` 会假装卡死

Flutter SDK 的 zip 里 `flutter_tools.snapshot` 是预编译的，但首跑仍会执行
「Building flutter tool」→ `dart pub upgrade`（下载 96+ 个包）→
**`dart --snapshot-kind=app-jit` 重编 flutter_tools**。最后一步**几分钟内不打印任何东西**，
看起来完全卡死。第一次我误判为卡死并 kill 掉了；重跑只用 45 秒就出了结果 ——
说明 kill 掉的是**正常的编译**。

> **判断方法**：`flutter.bat` 首跑慢，先看 `flutter\bin\cache\` 里
> `flutter_tools.snapshot` 的时间戳在不在变，以及有没有 `dart.exe --snapshot-kind=app-jit` 进程。
> 有就耐心等，别 kill。

### 6-6. `flutter run -d chrome` 第一次卡在「Waiting for connection from debug service」

第一次 `flutter run -d chrome`（含首次 web 编译）**永久卡在**：

```
Launching lib\main.dart on Chrome in debug mode...
Waiting for connection from debug service on Chrome...             14.7s
```

现象与排查结论：

- Chrome **确实起来了**（`--user-data-dir=...\flutter_tools_chrome_device.XXX`、`--remote-debugging-port=59718`），
  而且**应用的 dev server 是好的**：`http://localhost:59638/` 返回 200、
  `/main.dart.js` 返回 200、Chrome 到 59638 的 TCP 是 `Established`。
- 但 **Chrome 没有真正打开 59718**：`netstat` 无该端口，用户数据目录里也没有
  `DevToolsActivePort` 文件 → flutter 永远等不到 DWDS 握手。
- **隔离测试证明不是环境问题**：手工用「Flutter 完全相同的参数」、以及「加上重定向后的环境变量」
  分别起 Chrome，**端口都正常 LISTENING**（59719 / 59720 / 59721 三次全成功）。
  所以既不是 Chrome 的问题，也不是 `env.ps1` 重定向的问题。
- **直接重跑就成功了。**第二次全程正常，见 §7。

**判定：首次 web 编译耗时过长导致的竞态。后续再遇到，先重跑一次，不要立刻改配置。**

---

### 6-7. ⭐ **`sqflite` 的 `execute` 在 Android 上只跑第一条语句、其余静默丢弃**（Task 5 发现）

**这是本项目至今发现的最危险的一条平台差异 —— 它会让 App 在真机上缺表，而全部测试都是绿的。**

#### 现象

`SqlExecutor.run` 的契约要求「不传参数时能跑多语句」（迁移的建表脚本是 7 条 CREATE 拼成的）。
若直接 `db.execute(createTablesSql)`：

| 后端 | 结果 |
|---|---|
| **FFI（测试 / 桌面）** | ✅ 7 条全部执行。底层走 `sqlite3` 包的 `sqlite3_exec`，支持多语句 |
| **Android（生产）** | ❌ **只执行第一条 `CREATE TABLE exercise`，其余 3 张表 + 3 个索引无声消失** |

#### 证据（不是推测）

1. **接口契约原文**，`sqflite_common-2.5.13+1/lib/sqlite_api.dart:85-89`，`DatabaseExecutor.execute` 的文档：
   > Executes a single SQL statement... You cannot have multiple statements (separated by `;` or by line), as this is not supported. i.e. you cannot create 2 tables for example.

2. **Android 实现路径**：`SqflitePlugin.onExecuteCall` → `Database.execute` → `getWritableDatabase().execSQL(...)`（`sqflite_android-2.4.4/.../Database.java:426`）。Android 的 `execSQL` 底层是 `sqlite3_prepare_v2`，**只编译第一条，其余静默丢弃且不报错**。

3. **探针实测（FFI 侧）**：两条 CREATE 一次 `execute`，两条都建出来了 —— 印证了「FFI 支持、所以测试抓不到」。

#### 后果

**全部测试都跑在 FFI 上，因此这个差异永远测不出来。** 若不兜底，Android 上库只有一张表，直到运行时访问 `session` 才炸 `no such table` —— 而且是在真机验收、甚至真实使用时。

#### 处置

实现了共享函数 `splitSqlStatements`（在 `lib/data/db/sql_executor.dart`），
**两个后端都经它逐条执行**：

```dart
List<String> splitSqlStatements(String sql) => sql
    .split(';')
    .map((statement) => statement.trim())
    .where((statement) => statement.isNotEmpty)
    .toList();
```

两个设计取舍：

- **共享而非各写一份**：要求「两个分支在三个后端里行为必须一致」，共享一份是构造性保证；更实际的好处是**测试跑的就是 Android 用的那条代码路径**。
- **FFI 也拆**：FFI 本可把多语句直接交给底层，但那样 Android 的拆分路径就**没有任何测试覆盖**，两端行为也会各自漂移。

**已知边界**：朴素按 `;` 切分，不处理字符串字面量里的分号（`DEFAULT ';'`、触发器 `BEGIN...END;`）。
本项目 DDL 与迁移脚本不含这类写法。**将来若需要，只需改这一个函数。**

#### ⚠️ 一条必须如实说明的局限

**这个兜底的「必要性」无法由本机测试证明** —— 在 FFI 上改不改测试都绿（FFI 本来就支持多语句）。
依据是 `sqflite_android` 源码 + Android 平台文档，**没有上真机验证**。

**坐实它只能靠 Task 22 真机验收**：在真机上清空 App 数据后重开，确认 4 张表 + 52 个动作全部建出
（这条本来就在 M2 验收清单的「数据落地检查」里）。

---

## 7. `flutter run -d chrome` 结果：**成功**（第二次尝试）

```
Launching lib\main.dart on Chrome in debug mode...
Waiting for connection from debug service on Chrome...             14.1s

Flutter run key commands.
r Hot reload.
R Hot restart.
h List all available interactive commands.
d Detach (terminate "flutter run" but leave application running).
c Clear the screen
q Quit (terminate the application on the device).

This app is linked to the debug service: ws://127.0.0.1:62004/fPB4_q66kT4=/ws
Debug service listening on ws://127.0.0.1:62004/fPB4_q66kT4=/ws
A Dart VM Service on Chrome is available at: http://127.0.0.1:62004/fPB4_q66kT4=
The Flutter DevTools debugger and profiler on Chrome is available at:
  http://127.0.0.1:62004/fPB4_q66kT4=/devtools/?uri=ws://127.0.0.1:62004/fPB4_q66kT4=/ws
Starting application from main method in: org-dartlang-app:///web_entrypoint.dart.
```

**独立验证应用真的渲染出来了**（不只是进程起来了）——
查 Chrome DevTools 的目标列表，页面标题已经被运行中的 Flutter 应用改写：

```
type                 : page
title                : Flutter Demo                       ← 来自 MaterialApp.title
url                  : http://localhost:63237/
webSocketDebuggerUrl : ws://127.0.0.1:62062/devtools/page/E033D9A9A7425CD4D2061F872A2C94DE
```

`title: Flutter Demo` 是 `flutter create` 默认 `main.dart` 里 `MaterialApp(title: 'Flutter Demo')`
设的，**静态 `index.html` 里没有这个字符串** —— 只有 JS 真的跑起来才会是它。

退出方式：计划说「按 `q` 退出」。因为是后台非交互 shell，「q」送不进去，
改用终止进程 + 清理带 `flutter_tools_chrome_device` 的 Chrome 进程，效果相同。

---

## 8. 交付物清单（Task 0）

| 交付物 | 状态 |
|---|---|
| Flutter 工程（`flutter create --org com.mobis --project-name gym_tracker --platforms android,web .`） | OK 41 个文件，`android/` + `web/` 齐全 |
| 8 个依赖（sqflite / sqflite_common_ffi / sqflite_common_ffi_web / go_router / provider / uuid / wakelock_plus + cupertino_icons） | OK 见 §1 |
| `scripts/env.ps1` | OK 见 §5-2 |
| `test/smoke/database_smoke_test.dart` | OK 计划 Step 8 原文，2 测试全过 |
| `web/sqlite3.wasm`（748686 B） + `web/sqlite_sw.js`（263881 B） | OK |
| `docs/superpowers/plans/dev-environment-notes.md` | OK 本文件 |
| `flutter doctor -v` 全绿 | OK `No issues found!` |
| `flutter test` 全绿 | OK 3 个测试 |
| `flutter run -d chrome` | OK 第二次成功 |
| 注意： git 提交（计划 Step 11） | 未执行 **按要求未执行**，留给主 agent |

**没有任何一步是失败的。**两个需要重跑才成功的地方（`pub global activate webdev`、
`flutter run -d chrome`）都已在 §6-3 / §6-6 记录了原始错误与重跑结果。

---

## 9. 日常怎么跑测试（Task 12 补记）

```powershell
# 日常快速反馈：跳过 e2e（也顺带跳过 smoke）
flutter test test/domain test/data test/state test/layering_test.dart

# 提交前：完整跑一遍（**这一步不能省**）
flutter test
```

**约定**：端到端回归放在 `test/e2e/` 这个独立目录里，靠**路径**区分即可 ——
**不要**引入 `@Tags` 注解或 `dart_test.yaml`。多一层测试框架配置只会多一处
将来会失效的地方。

> **但 e2e 不能被永久排除。** 它是唯一能发现「分层各自都绿、但层与层之间
> 假设不一致」的那一层 —— 旧项目这条链第一次跑就抓出一个分层测试没抓到的问题。
> 本项目的 Task 12 也已经印证：它在实施期间暴露了「同时至多一段休息在进行」
> 这条不变量只由界面守着（详见计划 Task 11 那节的说明）。

---

## 10. ⭐ **`github.com` 被本机 Steam++ 中间人劫持 —— Java/Gradle 因此完全握手不上**
（Task 21 发现；同时是 §6-1 的真正根因）

### 现象

`flutter build apk --debug` **确定性失败**（重跑两次，错误逐字相同），
`.part` 文件始终 **0 字节**：

```
Exception in thread "main" javax.net.ssl.SSLHandshakeException: (certificate_unknown)
PKIX path building failed: sun.security.provider.certpath.SunCertPathBuilderException:
unable to find valid certification path to requested target
	at org.gradle.wrapper.Download.downloadInternal(Download.java:58)
	at org.gradle.wrapper.Install.createDist(Install.java:48)
Gradle task assembleDebug failed with exit code 1
```

**关键：失败发生在 Gradle 启动之前的 wrapper 下载阶段。** 所以
`--no-daemon`、调大超时、清缓存**全都无效** —— daemon 根本没参与。

### 根因链（每一跳都实测过）

1. `android/gradle/wrapper/gradle-wrapper.properties` →
   `https://services.gradle.org/distributions/gradle-9.3.1-all.zip`
2. `services.gradle.org` 返回 **307**，重定向到
   **`https://github.com/gradle/gradle-distributions/releases/download/...`**
3. Java 跟随重定向连 `github.com` → **收到一张本地签发的假证书** → PKIX 失败

决定性证据 —— 用 **JDK 自己的 TLS 栈**取证书：

```
=== keytool -printcert -sslserver github.com ===
签发者: C=CN, O=BeyondDimension, OU=Technical Department, CN=SteamTools Certificate

=== 对照：keytool -printcert -sslserver services.gradle.org ===
签发者: CN=WE1, O=Google Trust Services, C=US      ← 这一跳是好的
```

**`github.com` 被 Steam++ / Watt Toolkit（BeyondDimension 出品）中间人劫持**，
用自签的 `SteamTools Certificate` 冒充 GitHub。进程实测在跑，且**监听在 0.0.0.0:443**。

### 为什么只有一部分工具受影响

| 工具 | 是否受影响 | 原因 |
|---|---|---|
| Chrome / curl.exe（schannel） | 部分 | 该 CA **装进了 Windows 证书库**，它们信；但查不到吊销信息，所以 curl 需要 `--ssl-no-revoke`（**这就是 §6-1 的真正原因**） |
| Dart / pub | **不受影响** | 自己带 TLS 栈与根证书，且实际走的是未被动持的 CDN |
| **Java（Gradle wrapper）** | **完全打死** | 该 CA **没有装进 JDK 的 `cacerts`** → 根本不认识它 |

### 与旧文档 §9「网络下载量上限」的关系

**那条假说在这台机器上不成立，而且完全不是本次失败的原因。** 直接测带宽：

```
curl.exe -L --ssl-no-revoke -r 0-8388607 .../gradle-9.3.1-all.zip
http=206 downloaded=8388608 speed=3504427B/s time=2.393717s     ← 3.5 MB/s
完整文件 Content-Length: 234893460（224 MB），HTTP 200
```

**下载又快又通，Java 只是连证书都握不上手。** 与「能下 1MB 下不动 2GB」是两回事。

### 解法

**退出 Steam++ 的「网络加速」（或整个 Steam++）后重跑。** 劫持停止后
`github.com` 恢复真实证书（实测变成 `CN=Sectigo Public Server Authentication CA DV E36`），
构建即可进行。

**只要成功一次，Gradle 分发包就缓存进 `.tooling/gradle`，后续重建不再需要 github**
（Maven 依赖走 `dl.google.com` 与 `repo.maven.apache.org`，实测未被劫持）。

**这条对后续所有 Task 都成立** —— 任何需要 Java/Gradle 联网的步骤
（重建 APK、`flutter run` 到 Android）**都要先确认加速器不在拦**。
排查方法就一句：`keytool -printcert -sslserver github.com` 看签发者是不是
`Sectigo` / `DigiCert` 之类的真 CA，而不是 `SteamTools Certificate`。

> **没有采纳的两条路，以及为什么不采纳**（都涉及安全，需用户单独批准）：
> 把 SteamTools CA 导入 JDK `cacerts`（等于让构建链永久信任一个本地中间人根证书）；
> 关闭 TLS 校验（不可接受）。

---

## 11. ⭐ **PowerShell 5.1 的 `Get-Content`/`Set-Content` 往返会毁掉 UTF-8 源文件**（Phase 2 Task 2 踩到）

### 现象

用「读进来 → 字符串替换 → 写回去」的手法做变异验证：

```powershell
$orig = Get-Content $p -Raw
$mutated = $orig -replace '...', '...'
Set-Content $p -Value $mutated -NoNewline -Encoding utf8
```

跑完测试再写回 `$orig`，文件却已经废了：

- 全部中文注释变成乱码 —— `flat 时把` → `flat 鏃舵妸`
- 换行被吃掉若干处，`library;` 与上一行挤成一行
- 文件开头多了 BOM（`EF BB BF`），之后 `flutter test` 直接加载失败

### 根因

**`Get-Content` 在 Windows PowerShell 5.1 里默认按系统 ANSI 代码页解码**（本机是 GBK），
不是 UTF-8。于是 UTF-8 的中文字节被当成 GBK 解出一串乱码字符，
再用 `-Encoding utf8` 写回去，等于**双重编码**。BOM 是 `-Encoding utf8` 自己加的。

最坑的是：**`-Raw` 不改变这一点** —— 它只影响「按行还是整体」，
不影响用哪张代码页。ASCII 部分（代码本身）完好，所以看起来「只是注释坏了」，
实际文件已经不能编译（`﻿` + 丢换行）。

### 处置

**不要用 shell 做源文件的读-改-写。** 要改源文件就用 Edit 工具（它对编码是透明的）。
变异验证也一样 —— 多两次 Edit 往返，比毁掉一个文件便宜。

如果确实需要在 PowerShell 里读写 UTF-8 文本，只有这条是安全的：

```powershell
$orig = [System.IO.File]::ReadAllText($p, [System.Text.UTF8Encoding]::new($false))
[System.IO.File]::WriteAllText($p, $mutated, [System.Text.UTF8Encoding]::new($false))
```

`UTF8Encoding($false)` 的 `$false` 是「不写 BOM」。

### 代价与教训

`lib/domain/chart_geometry.dart` 当时**还没提交**（是刚写完正在做变异验证的新文件），
git 里没有副本。靠主 agent 上下文里留着的完整文件内容手工重写才救回来。
**新文件在做变异验证之前就该先提交一次** —— 那时它是干净的，
再改坏也只是一个 `git checkout` 的事。这条适用于所有「写完先折腾再提交」的流程。
