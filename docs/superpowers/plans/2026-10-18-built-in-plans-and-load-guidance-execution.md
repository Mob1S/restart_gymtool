# 内置计划、动作库与个人重量参考实施记录

日期：2026-10-18，Asia/Shanghai。批准依据为[设计](../specs/2026-10-18-built-in-plans-and-load-guidance-design.md)，执行步骤见[实施计划](2026-10-18-built-in-plans-and-load-guidance.md)。

## 交付内容

- 动作目录独立于计划导入升级，保留原有身份、器械偏好、自建内容和归档选择。新增 19 项，新库 71 项；其中腿举机提踵在实施时按 PHUL 原表补齐。别名覆盖同一份动作选择器。
- 凯谭整理参考版、StrongLifts 5×5、PHUL 均可预览并导入独立副本；支持替代器械、恢复归档动作、调整休息日位置、任意多日周期及逐组要求。
- 凯谭保留 11 个手动阶段及已批准整理约定；阶段编辑和推进保留训练日身份、自然日休息进度，已有训练使用开训快照。
- 同一训练日的重复动作保留独立出现位置；排序或移除第一项不会串用第二项的目标。
- 逐组目标支持 REP、RM、%1RM、RPE/RIR、范围、热身、可选组和停顿。目标用力程度不会写成实际反馈；实际反馈默认可选 RPE，支持 RIR、半级及清空。
- 分段首段即时落盘；开始下一段时停止组内休息计时。支持重启恢复、提前结束、整场结束、撤销末段、修改下一段器械单位和各段实际值。
- 个人参考使用同动作最近 90 天、最多 8 场可比表现，区分有余力依据和未知余力。采用近 3 场中位数、3 对 3 趋势比较、28 天陈旧判断和当前器械单位/档位。分段按对应实际段比较，高次数不扩展旧 e1RM 公式。
- 点击采用只改当前未完成段的重量，保留 REP/RPE，并保存计算版本和依据摘要；重新检查当前组、目标、偏好及历史。自重/助力提供历史读数，不生成普通负重 RM 建议。
- 历史支持实际反馈和分段编辑；容量累加各段、组数按逻辑组统计，分段不按连续次数换算 e1RM。CSV 分行保存各段，回导检查整组完整性、单位和反馈一致性。
- schema 8、备份 v6，保留 v1–v5 恢复。扩展数据计入记录/字节上限，失败事务回滚。目录同步失败会提示并保留进入应用管理已有数据的能力。

## 来源处理

凯谭采用用户确认的第三方整理资料并标注“整理参考版”。上斜第三阶段采用 4 组（前 2 组 RPE8、后 2 组 RPE9–9.5）；Y 字侧平举为 3 组 10—休息 5 秒—10；腿日默认高脚杯深蹲。没有将公开访客片段说成已经核验原作者全片。来源和限制继续保存在[调研](../../research/2026-10-18-built-in-plans-and-load-guidance.md)及[截图转录](../../research/2026-10-18-kaitan-user-reference-transcription.md)中。

## 自动验证

工具链沿用仓库环境，所有 Flutter/Dart/Gradle 命令先加载 `scripts/env.ps1`，命令按顺序执行。

| 检查 | 实际结果 |
| --- | --- |
| 改动前全量测试 | 551 项通过 |
| 最终 `flutter test --no-pub --timeout 90s` | **586 项全部通过** |
| 最终 `flutter analyze --no-pub` | **No issues found** |
| 既有备份故障注入脚本 | **13/13 检出** |
| 既有导入/计划故障注入脚本 | **9/9 检出** |
| `git diff --check` | 通过 |

新增回归覆盖目录升级/回滚、schema 8 原子迁移、备份扩展、独立重复动作、阶段快照、实际反馈、部分组恢复/撤销、器械单位保护、历史修改、CSV 分段缺失、参考过期和陈旧记录等。启动/恢复测试改为等待实际异步状态及弹窗关闭，避免固定 120ms 假定。

故障注入证据：

- `build/acceptance/backup-mutations-2026-10-18T13-24-53-382Z/results.json`：13 项。
- `build/acceptance/import-plan-mutations-2026-10-18T13-25-48-226Z/results.json`：9 项。

## 真实浏览器

使用独立 Edge headless profile、临时本地端口、真实 SQLite wasm/IndexedDB 和真实文件下载/恢复。

| 运行 | 结果 | 本地证据目录 |
| --- | --- | --- |
| 新计划及参考端到端 | **12/12，0 个运行异常** | `build/acceptance/browser-builtin_programs-2026-10-18T13-51-16-674Z` |
| 原训练/历史/进步回归 | **7/7，0 个运行异常** | `build/acceptance/browser-2026-10-18T13-51-16-733Z` |
| 自然日休息回归 | **7/7，0 个运行异常** | `build/acceptance/browser-rest_days-2026-10-18T13-51-51-699Z` |

新增场景实测了三份计划导入、首段恢复、阶段切换后快照不变、CSV 往返、历史改 RPE、lb 参考的主动采用，以及保留实际 14 REP/RPE9.5。分段示例实际保存 20kg×10、25kg×10，统计为 1 组、450kg。

动作条使用控件的可访问性点击动作；参考采用场景以键盘调整重量，以触摸调整 REP，并核对实际落库值。纯数字滑块的浏览器元数据读取未用作实际 REP 的证明。已检查 390×844、360×640、640×360 和 1280×800 的相应截图。

## 构建

Web：`flutter build web --no-pub --no-wasm-dry-run`，最终 **Built build/web**，36.4 秒。

Android：在 `android` 目录执行：

```powershell
. ..\scripts\env.ps1
.\gradlew.bat --offline '-Ptarget-platform=android-arm,android-arm64,android-x64' '-Ptarget=lib/main.dart' '-Ptree-shake-icons=true' assembleRelease
```

最终 **BUILD SUCCESSFUL**，1 分 7 秒，223 项任务（21 executed，202 up-to-date）。保留既有 Gradle 插件弃用提示，本次未改动构建依赖。

- APK：`build/app/outputs/flutter-apk/app-release.apk`。
- 大小：**71,929,169 字节**。
- SHA-256：`0E7C5E3AB5DD3DE42E79BB788EC8DE1CFE6537A09ED499EA73D65739F3F5EF66`。
- 本轮尚未执行 Android 真机专项验收；浏览器和 FFI 结果不作为真机验收结论。

## 提交与交付

- `617a642`：类型、目录、计划数据、事务写入、历史统计/CSV、参考引擎和数据测试。
- `7541583`：可编辑界面、逐组反馈、记录恢复、独立动作位置、目录失败兜底及浏览器脚本。
- README、changelog、设计补充和本记录随文档提交交付。最终正常推送与远程核对在交付时记录；保留用户预先存在的 `.tmp/` 与 `.superpowers/`。
