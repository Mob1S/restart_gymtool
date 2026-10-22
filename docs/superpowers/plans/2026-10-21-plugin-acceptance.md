# 渐进式插件架构实施与验收

实施日期：2026-10-21 至 2026-10-22（Asia/Shanghai）。对应计划：`2026-10-21-plugin-architecture.md`，基线提交 `f4969fa`。用户提出实施要求后执行，原计划文件保持原样。

## 已实现

| 计划任务 | 交付 |
|---|---|
| 1 公共契约与目录 | 纯 Dart 清单、请求/事件/错误协议、兼容与依赖检查；发现不启动运行时；分层检查 |
| 2 安装识别与私有存储 | schema 12；历史迁移前持久化 fresh/legacy；默认偏好与命名空间 JSON 事务 |
| 3 生命周期与能力 | 串行启停、实例令牌、10 秒控制超时、故障隔离、可等待且可重试的关闭；实际支持能力与声明取交集 |
| 4 管理与导航 | 设置 → 插件管理；按稳定 ID 过滤底栏；通用路由归属守卫；冷启动及重启保留深链接目标 |
| 5 热量插件 | 受限业务客户端；数据库留在宿主；离开页面取消所属搜索请求；OCR/搜索按需初始化 |
| 6 备份 | v8 / schema 12，兼容 v1–v7；停用数据参与备份；未知命名空间完整往返；预览失效及事务回滚 |
| 7 动作分析插件 | 页面实例退出注册、训练组扩展入口、可等待 closeSession；Web/Android 资源代次与完整停用 |
| 8 示例与文档 | 两个任意 ID 的测试示例、动态设置入口过滤、SDK 文档、浏览器脚本及本验收记录 |

基础训练 `gym.training` 始终可用。新安装关闭 `gym.calories` 与 `gym.motion`，底栏为训练／历史／进步；插件化前的安装升级启用两项可选功能；之后保留用户选择。恢复不覆盖本机插件启用状态。停用不删除记录、设置或已保存媒体。

业务页面使用公共能力客户端，SQL 及旧饮料/分析表由宿主兼容服务持有。媒体帧与纹理留在平台适配层，控制请求与事件含 requestId 和实例 generation。过期实例不能关闭后来激活的媒体资源，失效或超时请求在事务提交前被拒绝。

## 自动检查

| 检查 | 实际结果与证据 |
|---|---|
| Dart 格式 | 321 个文件无变化；`dart format --output=none --set-exit-if-changed lib test` |
| 静态检查 | 零问题；`build/plugin-analyze.log` |
| 完整 Flutter 测试 | 739 项全部通过；`build/plugin-all-tests.log`；Windows 下使用 `--concurrency 2` |
| JavaScript 生命周期 | `node scripts/plugin_runtime_test.mjs` 通过；涵盖并发加载、失败重试、取消、关闭失败重试、旧事件和搜索会话隔离 |
| Web release | 构建成功；`build/plugin-web-build.log`；CanvasKit 从构建包本地加载 |
| Android release | 构建成功；`build/plugin-apk-build.log`；APK 签名验证通过 |

最终 APK：`build/app/outputs/flutter-apk/app-release.apk`，243,400,033 字节。

SHA-256：`090020f7d00febad42d711d20acf9ef63dfd97b7dbbeaf4db066aa9b509f6585`。

构建产物使用 Android Debug 签名；真机覆盖安装记录见下。Android 原生关闭逻辑另有独立 Kotlin 编译验证，未发布。

## 浏览器证据

所有浏览器使用临时独立配置、随机本地端口和测试 SQLite/IndexedDB；未访问用户主数据库。每个证据目录包含 `results.json`、截图、语义树和相关数据快照。Chrome 在受限沙箱内无法启动 GPU 子进程，经自动审批在沙箱外运行测试。

| 脚本 | 实际结果 | 证据目录（项目内） |
|---|---|---|
| `browser_plugins_smoke.mjs` | 6 项通过 | `build/acceptance/browser-plugins-2026-10-21T15-59-11-364Z` |
| `browser_smoke.mjs` | 7 项通过 | `build/acceptance/browser-2026-10-21T15-59-24-127Z` |
| `browser_training_redesign_smoke.mjs` | 13 项通过 | `build/acceptance/browser-training_redesign-2026-10-21T16-05-57-882Z` |
| `browser_backup_smoke.mjs` | 6 项通过 | `build/acceptance/browser-backup-2026-10-21T16-09-58-316Z` |
| `browser_calories_smoke.mjs` | 10 项通过 | `build/acceptance/browser-calories-2026-10-21T16-06-03-335Z` |
| `browser_motion_ui_smoke.mjs` | 3 项通过 | `build/acceptance/browser-2026-10-21T16-08-13-259Z` |
| `browser_motion_smoke.mjs` | 7 项检查通过，摄像头不可用 | `build/acceptance/browser-2026-10-21T16-08-14-244Z` |

共 52 项浏览器检查通过。原有备份脚本同时修正了旧格式夹具不能带 v8 plugins 字段、旧备份恢复后同步内置动作库、横屏导航遮挡及滑块需滚动到可见区域等判据；这些脚本修正没有改写业务数据格式或跳过字段断言。

插件专项实际验证了：

- 新库三项导航且未加载可选运行时；深链接先显示说明，启用后继续目标。
- 关闭热量后重启，未知插件的 ID、版本、嵌套内容保持一致并可导出。
- 动作分析停用后拒绝能力调用，再次启用及重启可用。
- 启停可选插件前后，活动训练与训练组快照逐字段一致。
- 在专用测试库移除 schema 12 增量、清空训练并设置 schema 11 后重启，得到五项导航和 schema 12。

第一次浏览器检查暴露的冷启动 URL 重置已修复并加入 Widget 回归；CDN 引擎加载失败通过使用随包 CanvasKit 解决。历史脚本已同步当前备份版本，并在使用可选功能前通过界面启用。

真实视频使用既有素材 `build/review-samples/bench-press-pexels-32239226.mp4`（23,357 ms）。Flutter 文件选择器导入后完成 46 帧增量事件、保存并列出独立项目；底层真实 Worker 检查得到 31 帧姿态、30 帧跟踪，并确认初始化及推理取消后仍可继续使用、Blob 与结果重启保留。测试浏览器没有可用摄像头／权限，因此摄像头只完成不可用状态检查。

热量回归实际执行本地中英文 OCR、离线录入、零值与备份往返。Open Food Facts 名称搜索与商品接口仍返回 fetch 失败／超时，证据保存在热量目录的 `real-off.json`；该检查通过的是明确显示外部不可用及本地功能保留，没有将公共数据请求记作成功。

## Android 真机验收

2026-10-22 已连接 BVL-AN16 手机，使用 `adb install -r` 成功覆盖安装主包 `com.mobis.gym_tracker`，未卸载或清除数据。安装后 `am start -W` 返回 `Status: ok`，应用进程存在；功能验收由用户手动进行，以下条目仍待确认。

首次覆盖因构建环境的 Debug 签名与手机原签名不同被系统拒绝。已使用与手机证书匹配的现有 `C:/Users/mobis/.android/debug.keystore` 对同一构建另存签名，证书 SHA-256 为 `12c27dff7491b11c53edae67b46a83faa7b46a6327818bacf88f3d7f192479d7`。实际安装包为 `build/app/outputs/flutter-apk/app-release-device.apk`，APK SHA-256 为 `97258857bf8d4c6064e0c3916d2f3500708f13c34bb12959b2fbaa0f8d683f94`。

以下功能不能以安装成功、构建、替身或浏览器检查替代：

| 步骤 | 需要观察 | 状态 |
|---|---|---|
| 新安装及旧版本覆盖更新 | 三项／五项默认、空记录老用户识别、后续选择保留 | 待真机 |
| 摄像头预览或录制时停用 | 拒绝停用并提示返回任务处理 | 待真机 |
| 离开分析再停用、重新启用 | 相机指示关闭、无旧事件、新预览可用 | 待真机 |
| OCR 中取消与停用 | 等待识别器和解码线程退出，失败可重试 | 待真机 |
| 拒绝权限、切后台、重启 | 基础训练可用、状态准确、无重复媒体资源 | 待真机 |
| 保存后停用再启用 | 饮料快照、稳定 ID、分析项目和媒体保留 | 待真机 |

使用可恢复的明确测试数据进行整库恢复验收；Android 安装继续沿用项目主包覆盖更新约定。

## 发布边界

内置插件仍占安装包空间；本期没有社区目录、独立下载、签名分发、隔离执行或独立升级。进程内能力接口用于结构约束和受控异步故障隔离，不构成恶意代码安全沙箱。JSON 备份不包含视频或视觉结果；恢复保留本机分析项目并解除旧训练组关联。公共饮料搜索仍受外部服务可用性影响，个人库与手动记录保持可用。

插件 SDK、数据版本规则、示例接入及未来发现/执行/UI 边界见 `docs/plugins/development.md`。
