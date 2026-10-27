# 2026-10-27 · 主页面续练与训练记录对比实施记录

已按[批准设计](../specs/2026-10-27-opengym-training-feedback-design.md)和[实施计划](2026-10-27-opengym-training-feedback.md)完成首批 openGym 交互借鉴。目标仓库为 `C:\someprojects\restart_gymtool`，分支为 `codex/opengym-training-feedback`；参考仓库 `C:\someprojects\openGym` 未修改。

## 已实现的行为

- 训练、历史、进步及已启用插件的主页面，在原导航上方显示训练名称、已完成父组数和续练入口。三项／五项导航顺序沿用现有配置。记录页、设置和任务详情不覆盖续练条。
- 应用启动统一恢复活动训练；并发读取共用一次请求。同一进程往返保留所选动作，冷启动按持久化状态恢复；加载失败可重试，保存／恢复过程禁止重复操作。开始训练会等待启动恢复，避免丢失点击或创建重复训练。
- 总结和历史详情共用本次／上次对比：稳定动作 ID、严格早于本次的已结束训练、同时间候选按 session ID 确定次序。按实际开训时间选择，补录顺序不影响基线。
- 展示日期、原始 kg／lb 读数、次数、热身／正式／未分类及可选 RPE／RIR。同动作多次出现保留位置边界；分段组只计一个父组，各段容量计一次。容量表示训练量，不生成力量结论、PR 或自动进阶。
- 编辑、删除、补录、导入和备份恢复通过现有数据修订机制重新读取。加载代次保护基础总结及对比；对比失败保留本场总结并单独重试。

没有增加依赖、数据库迁移或备份字段；保持 schema 12、备份 v8。按现有 Dart 分层独立实现，未复制 openGym 的 React 代码、动作数据或媒体。

## 自动检查

| 检查 | 本轮实际结果 | 证据（相对仓库根目录） |
| --- | --- | --- |
| Dart 格式 | 23 个文件，0 个需要调整 | `build/acceptance/training-feedback/format.log` |
| Flutter 全套测试 | 780 / 780 通过 | `build/acceptance/training-feedback/flutter-test-verified.log` |
| 静态检查 | 0 个问题 | `build/acceptance/training-feedback/analyze.log` |
| Web release | 构建成功 | `build/acceptance/training-feedback/web-build-final.log` |
| 新增浏览器流程 | 7 / 7 通过，无运行时异常 | `build/acceptance/browser-training_feedback-2026-10-27T10-50-26-341Z/results.json` |
| 插件浏览器回归 | 6 / 6 通过，无运行时异常 | `build/acceptance/browser-plugins-2026-10-27T10-55-17-959Z/results.json` |
| 原训练／历史／进步浏览器回归 | 7 / 7 通过，无运行时异常 | `build/acceptance/browser-2026-10-27T10-59-05-722Z/results.json` |
| Android release | 构建成功，APK 签名校验通过（v2） | `build/acceptance/training-feedback/android-build.log`、`apk-signature.log` |

新增测试覆盖前次筛选、同名不同 ID、相同时间、重复动作位置、原始单位、分段计数、数据修订、过期响应、恢复并发、失败重试、启动时开始训练以及真实路由。续练条和对比区另在 320px、双倍字号、深浅主题下验证无布局异常。

浏览器使用真实 SQLite wasm／IndexedDB、独立 Chrome profile 和合成备份，未访问用户现有浏览器或手机数据。7 个新增流程包括：冷启动直接进入进步页续练、往返保留动作与休息时间且无重复场次、五标签顺序、结束后的原始对比／首次记录、将前次 60 kg × 7 修正为 × 6 后容量差由 60 kg 更新为 120 kg、浅色窄屏、删除前次后重新显示首次记录。导出仍为 v8／schema 12。

人工检查了续练、暗色总结及浅色窄屏截图。Flutter 会把静态总结文字合并为一个语义节点，验收脚本按内容断言并滚动截图，不假定每行文字都有独立节点。

插件回归覆盖新安装的三标签、停用深链接保护、未知插件备份往返、动作分析启停、启停时活动训练不变及旧 schema 11 空库迁移。脚本现在等待备份恢复结束、插件状态保存和刷新后的新文档，避免读取提前出现的首页或刷新前的旧语义。

三套浏览器检查合计 20 / 20 通过。原流程回归验证单组记录、休息、结束、历史详情、三种走势图、重载持久化、50 kg × 8 × 4 的 1600 kg 容量和估算 1RM 62，以及未知动作深链接。原脚本已适配变长总结的滚动与懒加载完成按钮；底栏按实际 tab 节点点击，避免误选过渡中的文字节点。

APK：`build/app/outputs/flutter-apk/app-release.apk`，243,645,825 字节。SHA-256：

```text
F03ABAB47C53D0BFCFD14C11826A895AA0497E1B5E475A8D0E9C9D6C017DF716
```

APK 沿用项目现有开发签名；本轮未安装到手机。

## 环境和交付边界

本机仓库已从 `C:\ccproject` 迁移至 `C:\someprojects`。执行 `flutter pub get --offline --enforce-lockfile` 重建生成配置，未改依赖锁；`scripts/env.ps1` 改为按自身目录定位工具链。验证进程只设置所需 SDK／缓存路径，没有覆盖用户 HOME。

Web 构建使用默认 JavaScript 目标。Wasm 预检查仍报告已有 `video_player_web` 的 JS interop 类型兼容警告，本轮未宣称纯 Wasm 目标可用。

本轮尚未执行 Android 真机交互验收；构建产物与浏览器结果不能替代设备上的交互验证。

最终格式检查与暂存 diff 检查通过，独立代码复核未发现待修正问题。提交只包含本轮源码、测试、脚本和文档；原有 `.superpowers/`、`.tmp/`、`.vscode/` 保留，构建缓存和验收数据不入库。本轮没有推送或发布。
