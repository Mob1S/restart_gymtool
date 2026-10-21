# 独立动作分析实施记录

日期：2026-10-19。对应设计：`docs/superpowers/specs/2026-10-19-motion-analysis-design.md`。

## 已实现

- 底部五项导航：训练、历史、动作分析、进步、设置；`/analysis/...` 保持中间项高亮。两个模式无需训练记录即可进入，`/review/:setId` 转入关联组的分析会话。
- `MotionAnalysisController` 管理会话代次、增量观察、取消、输入准备、重算、保存与释放。导入画面由已处理帧推进，摄像头显示处理后的帧；旧会话回调不能写入新会话。重算失败不切换持久化结果引用。
- Web：本地视频解码、片段选择、真实帧时间戳、Worker 中的 MediaPipe Pose Lite + OpenCV LK 前后向校验、局部一致性及模板匹配。模型与运行库随站点提供，锁定版本、来源、许可证及 SHA-256，`node scripts/verify_motion_assets.mjs` 可校验。
- Web 摄像头适配器：安全上下文/权限/设备检查、后置优先、切换、冻结当前识别帧后标记、单个在途推理、实际输入跳过计数、能力选择录像格式、无音频录像、停止/三分钟上限/后台中断、Blob 持久化及 URL 释放。缺少录像能力时明确允许仅预览。
- Android：Camera2/ImageReader 有界输入、后台 MediaPipe/OpenCV、无音频 MediaRecorder、权限申请、切换、冻结标记、停止与中断结果。原生 Texture 将图像和叠加一起绘制，平台通道传观察元数据，不逐帧搬运原始图像像素。
- 复盘：骨架/轨迹开关、跟踪丢失断段、正常/慢速播放、前后帧、次数跳转、重新标记、人工次数边界修正、二维肘角与相对幅度；视觉次数独立于训练次数。镜像仅影响显示，计算使用原始归一化坐标。
- schema 10：独立 ID、可空组关联、每组一个项目的冲突提示、旧行迁移、删除组解关联。恢复训练备份保留项目并事务性解除关联；失败回滚恢复旧关联。旧仓储/媒体清理器共用新项目引用。JSON 训练备份维持原有格式，不含本地媒体路径或视觉结果。
- Web Blob/结果写入 IndexedDB 并检查配额；Android 使用 `noBackupFilesDir`。写入新结果后才更新 SQL 项目引用。离开页面释放摄像头、推理和临时媒体引用；删除只清理应用管理的副本。

## 已执行的验证

- Flutter 静态检查无问题；完整回归已通过，最终次数与日志见下方验证结果。
- Web release 构建与 Android debug APK 构建成功。Android 直接使用 Gradle `:app:assembleDebug --offline --no-problems-report --max-workers=2`，避开本机旧 Gradle 问题报告文件的 ACL 限制；未改宽该文件权限。
- Web 真实视频 Worker 集成测试：2 秒片段 31 个增量观察，31 帧输出 33 点骨架、30 帧有杠铃位置；实际源帧时间戳递增，重载结果一致，取消及时响应，刷新后由 IndexedDB Blob 重新创建对象 URL。这里只验证管线实际运行，不能据此声称关键点或杠铃位置正确。
- 360px 浏览器界面测试：真实文件选择 → 片段滑块 → 标记 → 增量分析 → 保存 → 首页显示独立项目。一个约 3 秒片段产生 46 个观察。所有分析来自真实视频；没有使用模拟识别或模拟摄像头作为验收。
- 仓储与状态回归覆盖 v9 迁移、独立保存、关联冲突、删组保留、训练恢复/失败回滚、取消后迟到结果、时间间隔缺口及重标记断段。

## 素材与未验收项

功能素材为 `build/review-samples/bench-press-pexels-32239226.mp4`，Igor Vieira / Pexels，来源和使用条件保留在同目录 `SOURCE.txt`。约 23 秒，斜侧面、偏暗并有镜头移动，不能作为固定机位精度基准。UI 测试保留跟踪丢失提示；不会用骨架点替代失踪的杠铃，也不会把未知区间计入有效指标。

浏览器摄像头实测返回权限拒绝；ADB 设备列表为空。摄像头实拍、设备切换/镜像/后台中断后的录像回放、目标手机的性能与兼容性 **未验收**。相关实现已编译，但编译不替代设备验证。

尚无设计指定的 3 段清晰固定侧面及 2 段遮挡/出画/移动机位的人工标注数据，未统计位置误差、次数边界误差、肩/肘/腕有效比例、明显错侧或跳点，也未进行 Lite/Full 同样本比较。5% 杠铃片直径和 0.2 秒边界目标均 **未证明达到**。没有提供评分、绝对距离/速度或伤病判断。

## 复现与产物

```powershell
. .\scripts\env.ps1
flutter analyze --no-pub
flutter test --no-pub --concurrency=2 --reporter expanded
flutter build web --no-pub --no-wasm-dry-run
node scripts/verify_motion_assets.mjs
node scripts/browser_motion_smoke.mjs
node scripts/browser_motion_ui_smoke.mjs
```

浏览器测试需要 Chrome 及本地素材，并使用隔离浏览器配置。摄像头部署需 HTTPS 或本机 localhost；手机访问普通局域网 HTTP 地址不保证可用。

- Web：`build/web/`。
- APK：`build/app/outputs/apk/debug/app-debug.apk`。
- 完整测试：`.tmp/motion-tests-release.log`。
- Android 构建：`.tmp/motion-android-final.log`。
- 浏览器证据：`build/acceptance/browser-2026-10-19T08-33-07-827Z/`（Worker）；本次 UI 测试的 `results.json`、逐阶段 PNG/可访问性快照位于 `build/acceptance/` 的对应时间目录。

代码与文档保留在当前工作区；未自动提交、发布或修改其他聊天。
