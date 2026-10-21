# 饮料热量管理实施与验收记录

日期：2026-10-21。依据 [2026-10-20 设计](../specs/2026-10-20-beverage-calories-and-unified-ui-design.md) 实施。沿用工作区已有动作分析实现，热量迁移和导航在此基础上集成；收到用户推送指令后，一并提交已验证的整合版本。

## 已实现

- 独立热量主页、日期选择、已记录合计、收藏／最近饮料、每日明细；新建、编辑、补记、删除及新增撤销。
- 包装与现制饮料资料、糖度／加料／冷热配置、收藏、归档及恢复；同名不同规格可并存。改现制配置清除沿用能量，避免将糖度比例当作整杯比例。
- 十进制输入和 BigInt 有理数精确计算；按每 100 mL 或每份、kcal 或 kJ 换算。汇总后显示一位小数，小于 0.1 的正值保留提示。零、未知与没有记录分别表达。
- 每条饮用记录保留来源、核对时间、规格、原始标注、数量、所属本地日期和精确结果快照。改库条目不重算旧记录，可单独修正历史依据。
- 截至所选日期的近 7／30 天趋势及饮料贡献；未记录保留缺口，未知条目不制造热量。
- SQLite schema **11** 增加饮料与记录表，兼容此前 schema 10 的分析项目。
- JSON 备份 **v7 / schema 11** 纳入两表，严格校验快照、索引字段、引用、必需数组与容量；一次事务恢复。旧 v1–v6 保留本机饮料，新 v7 明确空数组可清空；视频和动作分析备份边界不扩大。
- 底栏训练／热量／动作分析／历史／进步；五主页右上角设置，独立返回。饮料任务页使用根导航器，避免双标题和底栏遮挡。
- 复用共用主题，统一表单、按钮、弹层和标题；主按钮支持大字体自然增高，路由过渡尊重减少动态效果。

## 搜索与识别

公共名称搜索接入真实 Open Food Facts Search-a-licious，商品详情走官方产品 API。个人库优先显示；防抖 700 ms、请求间隔至少 6 秒、10 分钟缓存、最多 20 个查询，旧响应不能覆盖新查询。来源保持公共数据库身份；不将泛称 `_100g` 字段擅自换成体积基准。

终端真实英文搜索曾返回 Coca-Cola 500 mL、355 mL、Coca Cola Plus 330 mL；产品 `5449000000996` 的实际 API 返回每份 330 mL、140 kcal 等字段，已据此核对映射。原始探测文件位于 `.tmp/calories/probe-0.json`、`probe-1.json`。

**Web 名称搜索尚未通过实网可用性验收。** 最终 Chrome 中英文名称请求均为 `TypeError: Failed to fetch`，而同浏览器产品 API 正常。已保留失败提示、重试、个人库及手动入口；没有使用假结果、收费 API 或自建代理冒充接通。服务方也有 [CORS 问题报告 #427](https://github.com/openfoodfacts/search-a-licious/issues/427)。这里不把该报告当作当前失败的唯一原因，也不承诺中文商品覆盖。Android 使用原生 HTTP，不受浏览器 CORS 机制限制，真机网络仍需实际验证。

Android 使用打包的 ML Kit 中文识别 `16.0.1`，相机保存完整临时照片后本地识别；Web 随产物提供 Tesseract.js `6.0.1`、core `6.0.0`、tessdata_fast `4.1.0` 的中英模型。Web 对缺少标签锚点的结果重试其他方向；取消终止 worker。原图不上传、不进入备份。15 个本地资源的版本、长度和 SHA-256 已校验，完整许可与清单位于 `web/beverage/vendor/`。

受控中文截图的清晰、90° 横放、小字样本均能提取 `180 kJ`、`每 100 mL` 和 `330 mL`；反光遮挡样本未确定有效基准，表单要求补全，没有补造数值。最终一轮耗时分别约 8.2／15.1／7.0／22.5 秒，仅代表该 Chrome 环境。

另用 [Coca Cola Plus 实际包装营养标签](https://images.openfoodfacts.org/images/products/489/000/810/1306/nutrition_fr.5.400.jpg) 跑通图片输入、设备端 OCR、原图核对、取消不写入。约 4.6 秒取得文字，能量行可读到零，但计量基准识别不全，因此没有自动生成热量。**这证明流程可运行，不代表实际照片的完整字段提取准确率已达标；仍需核对。** Android 相机、反光和小字效果由真机验收确认。

## 验证结果与证据

- `flutter analyze`：无问题。
- 全量 **650 项测试通过**，本功能新增 33 项。包括精度、非法数量、零与未知、历史隔离、跨日、v10 迁移、新旧备份、回滚、搜索过期响应、配置失效、OCR 覆盖旧表单、五页设置返回和小屏大字体。
- 最终悬空撤销保护后，热量页面 4 项定向测试复测通过。
- Web release 构建通过；**10 项真实 Chrome 主流程检查通过**，涵盖录入、半份、SQLite 持久化、趋势、本地 OCR、取消、离线零值、新备份往返、旧备份保留、横屏、减少动态效果、训练记录／历史／进步／分析入口。
- 另 **1 项真实包装照片核对流程通过**。合计 11 项浏览器检查；其中公共服务检查只记录了外部不可用状态，不算名称搜索成功。
- Android 主应用 release 构建、APK 签名验证、包名和权限检查通过；未安装或操作用户手机。

主要证据：

- `build/acceptance/browser-calories-2026-10-21T05-03-44-005Z/results.json`
- 同目录 `ocr-evidence.json`、`real-off.json`、截图及实际下载／恢复的 JSON 文件。
- `build/acceptance/browser-calories-2026-10-21T05-06-44-751Z/results.json`
- 同目录 `actual-photo-ocr.json`、`actual-package-label.jpg`、`actual-photo-review.png`。
- `.tmp/calories/verified-tests.jsonl`、`apk-build.log` 和 OCR 下载日志。

复核命令：

```powershell
. ./scripts/env.ps1
flutter analyze
flutter test --concurrency=2 --reporter expanded
node scripts/verify_beverage_assets.mjs
flutter build web --no-pub --no-wasm-dry-run
node scripts/browser_calories_smoke.mjs
node scripts/browser_calories_smoke.mjs --label-only
./scripts/build_calories_release.ps1
```

Windows 构建使用项目内已有 `android-user-home` 和签名身份，并停用旧账号 Gradle daemon，避免旧缓存路径与账号权限污染。Release 使用固定构建标记 `BEVERAGE_RELEASE=2026-10-21`。这些为构建环境设置，不影响用户数据。

## 交付

主安装包：`build/app/outputs/flutter-apk/app-release.apk`。

- 包名：`com.mobis.gym_tracker`。
- 版本：`1.0.0`，versionCode `1`；最低 Android SDK 24。
- 大小：243,023,045 bytes，约 231.8 MiB。
- SHA-256：`1E884052CC552F28789207495B428F5E1B644658C81FD6FE84A51F61B278E0AB`。
- 签名证书 SHA-256：`f48133b2669712046491e49baa78e22c5bf0f2473e19696f87811cdb28db0458`。

[Android 真机验收单](2026-10-21-calories-device-acceptance.md) 已准备，覆盖升级保留数据、导航、计算、相机权限、拍照／选图、离线、备份与原功能回归。以上真机项目尚未执行，不将构建成功当作真机验收通过。
