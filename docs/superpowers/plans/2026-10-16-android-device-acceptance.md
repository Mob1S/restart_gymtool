# Android 真机验收记录

> **后续用户指令**：开发阶段只生成并覆盖主包，在主包新增 / 删除测试记录，不再使用独立验收包。以下为此前已发生的历史过程与证据；其中独立包接续步骤不再作为后续工作要求。

## 现场与范围

2026-10-16，荣耀 Magic6 Pro（BVL-AN16），Android SDK 36，分辨率 1280 × 2800。设备序列号和原始界面证据保存在本机 build 目录。

用户授权继续测试。已构建并安装独立包 `com.mobis.gym_tracker.acceptance`，备份恢复、导入与删除只在该包执行。尚未更新、清库或操作主应用的训练数据。

证据目录：`build/acceptance/android-2026-10-16-final/`。`actions.jsonl` 记录实际操作、返回结果和中断；`databases/<步骤>/data.json` 为只读取出的 SQLite 快照，取证同时检查 integrity_check 与 foreign_key_check。`exports/` 为通过 Android 系统保存界面真实写出后拉回的文件。

## 已有实际结果

| 项目 | 实际情况与证据 |
|---|---|
| 独立包安装 / 首次启动 | 成功；`01-test-home.png`，首页无溢出，4 个导航入口可见 |
| 新库结构 / 播种 | v4、8 张业务表、52 个预置动作、0 场训练；`databases/A1-fresh/`。A1 的选择动作步骤尚待执行 |
| A2：旧 v2 恢复 | 真正经过系统选择文件、预览、确认；`databases/A2-legacy-v2/` 与 fixture 所有字段逐项一致，包含归档动作、活动训练、占位组、非空休息原值与计划 |
| A3：真实文件导出 | 初始库已通过系统保存并拉回 `exports/GymAcceptance-initial.json`，每张表逐字段与新库一致；含训练记录的往返尚待完成 |
| A9：取消确认 | 点击恢复预览的取消后，`databases/A9-cancel-preview/` 与 `A1-fresh/` 完全一致；取消选文件与取消保存尚待执行 |
| P1：旧计划界面 | `P1-legacy-plan.png` 与 `P1-archived-plan-exercise.png`；旧计划「推日」、动作顺序和「我的推胸（归档）」标记正确 |

只读比对汇总：`partial-verification.json`。不以这些局部结果代替完整矩阵通过。

## 当前中断点

12:44 左右，准备将恢复后的非空库导出时，ADB USB 连接中断。用户重新插线并解锁后，Windows 仍识别手机 USB Composite Device 与 ADB Interface，但 ADB 设备列表为空。重启服务、尝试两种 USB 后端后仍未恢复；已恢复默认后端，并请用户重新开启 USB 调试和选择文件传输。

用户随后回复「现在不方便操作」。本轮停止设备交互，保留现有证据与独立包断点；完整验收未完成，尚无应用功能失败的结论。

原生文件选择器的「下载内容」来源没有列出 ADB 推送的 fixture。改从「荣耀Magic6 Pro → Download → GymAcceptance_20261016」后可正常选择。这属于验收文件导航路径，不是应用恢复错误。

断连时独立包保留旧 v2 测试数据，主应用未改动。公共 Download 中新增了本轮 `GymAcceptance_20261016/` fixture 目录与 `GymAcceptance-initial.json`；没有删除已有文件。

## 接续清单

1. 先确认 ADB 状态为 device，记录当前屏幕；可能停在系统保存对话框。从中断处完成非空库导出，而非重复写入。
2. 补 A1 选择动作；A3 / A4 非空导出、清独立包后恢复；A5 结束、强杀、继续；A6 空库与深色偏好；A7 v1；A8 三种坏备份；A9 取消选文件 / 保存。
3. 完成 Phase 3B 的三来源 CSV、单位、坏行、同日多场、重复、手动补记、活动训练保留与备份往返。
4. 完成 Phase 4 P2–P6、D1–D5、B1；P1 已有界面与数据库证据。
5. 更新主应用时只用保留数据的安装方式，检查直杆哑铃桌面图标与启动；测试结束卸载独立包，记录清理范围。
6. 默认 debug 已重建，独立包副本为证据目录下 `gym-acceptance-debug.apk`。发布包仍为 [图标复验记录](./2026-10-16-icon-and-retest.md) 中的安装包；不要把独立包当作主应用交付。

只读核对与操作脚本为 `scripts/android_data_acceptance.mjs`，仅支持固定的验收操作；清库与卸载固定针对 `.acceptance`，主包仅支持保留数据安装与启动。命令示例：

```powershell
node scripts/android_data_acceptance.mjs '{"type":"info"}'
node scripts/android_data_acceptance.mjs '{"type":"snapshot","label":"resume-current"}'
```

默认 debug 重建后已核对主包名 `com.mobis.gym_tracker`，大小 175,084,193 字节，SHA-256 `98A97C4E820B5EE1DB21E19843A36116771E6016456605CE0AF258AA2F8B839F`。release 未重建，大小与哈希保持图标复验记录中的值。
