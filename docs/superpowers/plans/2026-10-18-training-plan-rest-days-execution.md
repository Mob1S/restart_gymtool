# 训练计划休息日实施记录

日期：2026-10-18（Asia/Shanghai）。规格与实施清单分别见[设计](../specs/2026-10-18-training-plan-rest-days-design.md)、[计划](2026-10-18-training-plan-rest-days.md)。

## 实现

- 周期条目具有 training/rest 类型，数量、顺序、名称自由设置；休息项没有动作清单，允许前导、连续及全休息周期。
- `resolveTrainingSchedule` 使用 civil date 差值：完成当天“今日已完成／明天休息”，次日起消耗休息项，遇到未完成训练停止；不会创建休息 session。
- 计划进度仍来自该计划最近完成的 live/legacy 记录，按 finished_at、rowid 排序。自由训练、manual、csv 不推进；手选只列训练类型，活动训练继续优先。
- 仅在首页真正启用且无可用完成记录时，事务写入一次 activated_on。使用 GoRouter 顶层 state 判断首页是否显示，管理页不会提前启用。已有日期不覆盖，旧计划有有效完成时继续保持日期为空。
- 启用日期不属于编辑冲突令牌；计划保存只修改可编辑字段。开训令牌另含启用日期、当前日期、计划内容和推荐状态，事务重读并拒绝休息项或过期令牌。
- 首页监听恢复前台和下一次本地午夜，跨日清除旧手选并重算。主区域按实际高度居中，大字号休息文字可增高，小屏和横屏保持可滚动。
- 训练改为休息先确认清除草稿动作，整个父计划保存时原子落库。历史 session、组、原始单位与名称快照保留，历史允许关联后来转为休息的条目。
- schema7 原子迁移新增 kind/activated_on；旧条目全部为 training。备份v5包含 kind/activatedOn，兼容v1–v4；非法类型、日期、引用或休息动作在写库前拒绝。

## 自动验证

- `dart format lib test`：通过。
- `flutter test --no-pub --reporter expanded`：**551项通过**，包含原有512项和新增39项。
- `flutter analyze --no-pub lib test`：无问题。
- 备份变异检查13项、导入与计划变异检查9项，共**22项保护逻辑破坏均被测试发现**。所有变异结束后按原始字节还原源码，再运行全量测试。
- 新增测试文件：domain/training_schedule、data/training_rest_days、data/backup_v5、widget/rest_days。
- 补充旧迁移／备份版本断言，保留旧格式输入、原始单位逐字段比较、回滚和容量边界断言；计划管理新增“保存后尚未启用”的回归断言。

本机日志在忽略目录 `.tmp/rest-final-verification.log`；变异证据在 `build/acceptance/backup-mutations-2026-10-18T07-44-43-233Z/` 与 `build/acceptance/import-plan-mutations-2026-10-18T07-48-33-817Z/`。

## 浏览器验收

使用独立 Chrome profile、独立 SQLite wasm/IndexedDB 和真实文件选择／下载，不写入用户原有浏览器或手机数据。

本轮已通过56项：原训练7、备份6、导入4、计划8、训练效率11、训练改版13、新增休息日7。休息用例覆盖真实编辑四天周期、完成当天提示、连续休息、跨日后的下一训练、自由训练不推进、文件重载一致及非法休息动作文件拒绝。

首次全套证据：

- `build/acceptance/browser-2026-10-18T07-34-05-458Z/`
- `build/acceptance/browser-backup-2026-10-18T07-35-50-550Z/`
- `build/acceptance/browser-import-2026-10-18T07-35-50-610Z/`
- `build/acceptance/browser-plans-2026-10-18T07-36-33-128Z/`
- `build/acceptance/browser-workout_efficiency-2026-10-18T07-35-50-654Z/`
- `build/acceptance/browser-training_redesign-2026-10-18T07-35-50-707Z/`
- `build/acceptance/browser-rest_days-2026-10-18T07-33-35-846Z/`

浏览器脚本对异步写入等候最终状态；首次开训使用真实 touch 事件。没有降低记录数量、原始单位或文件一致性断言。

最终源码 `bf49005` 的高风险路径再次验收34/34，运行时错误为0：

- 休息7项：`build/acceptance/browser-rest_days-2026-10-18T07-53-09-035Z/`
- 计划8项：`build/acceptance/browser-plans-2026-10-18T07-53-09-028Z/`
- 备份6项：`build/acceptance/browser-backup-2026-10-18T07-53-09-051Z/`
- 训练改版13项：`build/acceptance/browser-training_redesign-2026-10-18T07-53-09-058Z/`

## 构建与预览

- 最终 `flutter build web --no-pub --no-wasm-dry-run` 成功，产物在 `build/web/`。
- 本机预览为 `http://localhost:8080/`，HTTP200；已通过应用工具排入浏览器面板。
- 常规Android构建的Gradle元数据请求等待较久，改用现有依赖缓存执行离线构建。第一次离线构建发现缺少CMake；通过SDK Manager补齐 `cmake;3.22.1` 后再次构建成功。没有修改项目依赖或Android构建配置。
- Android实际成功命令（在android目录，先加载env.ps1）：`./gradlew.bat --offline -Ptarget-platform=android-arm,android-arm64,android-x64 -Ptarget=lib/main.dart -Ptree-shake-icons=true assembleRelease`；日志 `.tmp/rest-android-release.log`，BUILD SUCCESSFUL，1分32秒。
- APK：`build/app/outputs/flutter-apk/app-release.apk`，70,847,605字节；包名 `com.mobis.gym_tracker`，versionCode1，versionName1.0.0。
- SHA256：`B0C21F3F9EE6CFBFB1EB2EB64355BA8A5224A4B1C3462806262BB8C0CB9CE200`。

本轮没有安装或操作用户手机，休息日尚未做Android真机专项验收；10月17日的真机结果只属于当日版本。本轮日期与恢复逻辑已由真实SQLite仓储、Flutter界面及Chrome文件流程验证。
