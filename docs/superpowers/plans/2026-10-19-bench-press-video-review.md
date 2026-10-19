# 卧推侧面视频复盘实施计划

实施状态：2026-10-19 已完成实验版代码、静态检查、603 项自动测试与 Android 安装包。各阶段结果、已知收敛和待真实视频/真机验收项以[实施记录](2026-10-19-bench-press-video-review-execution.md)为准。下方保留原任务清单，不能将编译或模拟媒体测试理解为视觉精度验收。

**Goal:** 从已完成训练组导入本地侧面卧推视频，完成杠铃追踪、骨架叠加、分次与修正，并持久化复盘。

**Architecture:** Android 解码器按真实帧时间戳供帧，OpenCV 局部光流跟踪杠铃片，MediaPipe Lite 输出姿态。Flutter 播放与修正、纯 Dart 指标、SQLite 元数据和私有媒体文件分开实现。

**Tech Stack:** 当前 Flutter / Dart，Android MediaExtractor / MediaCodec，OpenCV Android，MediaPipe Tasks Vision，video_player。

## Global Constraints

- 用户已确认单组、卧推、固定侧面、训练后本地复盘，并要求继续开发。
- 只有已完成组可以关联；每组一个复盘项目；分析不改写原重量、次数、RPE。
- 不生成绝对杠速、绝对距离、综合动作评分；缺失数据不得伪装有效。
- 首版 Android；Web 明确不支持视觉分析且保留原训练功能。
- 视频与分析不纳入 JSON 备份，恢复预览说明本机复盘清除；恢复失败不得丢失复盘。
- 没有真实视频、没有连接手机，自动检查与真机效果分别记录。
- 沿用现有主包，不部署未验证版本到用户手机；本轮在当前工作区顺序实施。

## 1. 原生视频与推理

**Files:** 新建 `android/app/src/main/kotlin/com/mobis/gym_tracker/review/VideoFrames.kt`、`BarTracker.kt`、`ReviewPlugin.kt`；修改 `MainActivity.kt`、`android/app/build.gradle.kts`；模型放入 `android/app/src/main/assets/`。

**Interfaces:** `gym_tracker/review` MethodChannel 接受 import / analyze / frame / load / write / remove / collect / cancel；`gym_tracker/review_progress` EventChannel 返回任务进度。帧结构为 `{t: 毫秒时间戳, x: 横向归一化坐标或 null, y: 纵向归一化坐标或 null, pose: [{x,y,v}]}`。结果包含所有视频帧的时间戳用于逐帧定位、按时间抽样的分析帧及算法版本。

- [ ] 固定依赖版本，下载官方 Lite 模型并记录 SHA-256、来源与许可证。
- [ ] 解码时记录 `MediaCodec.BufferInfo.presentationTimeUs`，处理旋转和 YUV 平面 row/pixel stride；只缓存有限帧。
- [ ] 实现局部特征的前后向光流校验与中位位移；不足或不一致时返回缺失，直到用户校正点重新初始化。
- [ ] 以独立可失败的 MediaPipe CPU VIDEO 任务处理姿态；所有资源在 finally 释放，工作线程响应取消。
- [ ] 视频副本进入 `noBackupFilesDir` 的 UUID 子目录；所有删除与读取校验受管理目录，原相册文件只读。
- [ ] 运行 Android 编译；记录真实素材验收未执行。

## 2. 数据与分析

**Files:** 新建 `lib/domain/video_review.dart`、`lib/data/repositories/video_review_repo.dart`、`lib/data/db/video_review_migration.dart`、`lib/data/files/video_review_bridge.dart`；修改 `migrations.dart` 与备份 snapshot 的 schema 标识；测试 `test/domain/video_review_test.dart`、`test/data/video_review_repo_test.dart`。

**Interfaces:** `ReviewFrame.fromJson(Map)`；`ReviewRep(startMs,bottomStartMs,bottomEndMs,endMs)`；`detectReviewReps(List<ReviewFrame>)`；`reviewMetrics(frames,reps)`；`VideoReviewRepo.load(setId)` / `save(setId,folder,payload)` / `delete(setId)` / `folders()`。

- [ ] 写明时间戳、缺口和人工边界测试，例如：

```dart
expect(ReviewRep(100, 1100, 1400, 2400).upSeconds, 1);
expect(ReviewRep(100, 1100, 1400, 2400).pauseSeconds, .3);
```

- [ ] 实现不可计算为 null、幅度中位基准、分次去抖、二维角度，人工分次必须按时间有序且不重叠。
- [ ] 新增 v9 迁移：独立表 `video_review(set_id PRIMARY KEY REFERENCES set_entry(id) ON DELETE CASCADE, folder TEXT, payload TEXT)`；不用触发器，遵守现有 SQL 多语句解析限制。
- [ ] 保存时在事务内重新校验组存在且已完成。文件先写新版本再提交引用，写库失败保留旧项目；孤儿文件在启动及数据变更后清理。
- [ ] 备份保持 v6 的训练数据契约，导出 schemaVersion 使用训练备份 schema 8；本地复盘 v9 不进入 JSON。通过级联删除实现恢复成功清除，事务回滚保留。
- [ ] 验证缺失组、未完成组、重复关联、替换、删除级联、备份不含视频与恢复回滚。

## 3. 回放与编辑

**Files:** 新建 `lib/features/review/video_review_page.dart`、`review_overlay.dart`、`rep_editor.dart`；修改 `pubspec.yaml`、`lib/app/router.dart`。

**Interfaces:** 页面参数仅 `setId`；VideoReviewBridge 对原生通道做 typed 转换；播放器使用本地 URI，不向 Web 引入 dart:io。

- [ ] 页面读取当前组描述、旧项目与文件；缺失文件不阻断训练记录。
- [ ] 导入、裁剪、首帧标点和区域半径调整；分析前暂停播放器并冻结输入，取消后旧结果保持可用。
- [ ] 根据实际帧时间戳实现上一帧/下一帧，分析抽样点不等同视频帧。
- [ ] 播放、0.25×/0.5×/1×、骨架和轨迹开关；轨迹缺口不连线。
- [ ] 次数选择跳转、增删边界、底部边界编辑；修正定位重分析，指标重算。
- [ ] 保存前检查边界和数据版本；返回时处理未保存改动；替换与删除有明确提示。
- [ ] 结果展示“实验性，待真实视频验证”，骨架独立失败可降级。

## 4. 接入与生命周期

**Files:** 修改 `completed_sets_sheet.dart`、`session_detail_page.dart`、`session_summary_view.dart`、`providers.dart`、`backup_section.dart`、`backup_preview_dialog.dart`；新增 `lib/state/video_review_cleanup.dart`。

- [ ] 已完成组新增独立复盘操作，原编辑交互保持。
- [ ] 清理仅操作受管理目录，跳过正在编辑/分析的工作文件夹；退出、重启、组删除、备份恢复后重试清理。
- [ ] 备份导出和恢复预览添加本地视频不备份、恢复清除说明；读取或准备失败不清理。
- [ ] 运行 `flutter analyze`、视觉模块测试及受影响存储/备份/训练界面测试。
- [ ] 运行完整 Flutter 测试与 Web / Android release 构建，记录失败原因并修复代码问题。
- [ ] 更新 README、变更日志和执行记录，区分构建结果与真实视频/手机效果未验收。

## 验收材料

真实视频需覆盖正常完整次数、明显停顿、杠铃片遮挡、出画、变帧率和旋转。按照设计文档 §9 人工核对位置与分次。用户已说明暂时无素材；此项保持未执行，不用合成数据冒充健身视频效果。
