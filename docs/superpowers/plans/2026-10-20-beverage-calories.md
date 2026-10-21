# 饮料热量管理 Implementation Plan

> **For agentic workers:** Execute this plan inline, task by task, preserving existing motion-analysis changes.

**Goal:** 按 2026-10-20 已确认设计实现本地饮料库、记录、趋势、公共搜索、设备端标签识别和备份。

**Architecture:** 精确有理数计算与不可变快照独立于 Flutter。SQLite v11 添加饮料及记录表；备份 v7/schema 11 纳入两表，旧备份保留本机饮料。搜索与 OCR 使用独立平台适配器，共用主题与五项导航。

**Tech Stack:** Flutter/Dart、SQLite、Open Food Facts、Android ML Kit Chinese、Web Tesseract.js。

## Global Constraints

- kcal = kJ / 4.184；十进制输入精确计算，汇总后取一位小数。
- 明确零、待补热量、未记录分别表达；历史使用快照。
- 不将每 100 g 换为每 100 mL；现制糖度不自动推算。
- 20 MiB / 100,000 总记录上限；恢复一次事务，保留动作分析边界。
- 底栏：训练／热量／动作分析／历史／进步；五主页右上角设置，push 返回原页。
- OCR 不上传图片；临时图片不持久化。公共结果必须核对。

## Tasks

- [x] 1. 完成真实 OFF 接口评估与字段核对；Web 名称搜索实网失败，中文覆盖未宣称完成，限制已记录。固定 Web OCR 引擎、中英模型及许可。
- [x] 2. `lib/domain/beverage*.dart`：精确计算、来源/基准/规格、不可变饮用快照、7/30 天汇总、保守标签解析；领域测试覆盖精度、零/未知、基准及非法输入。
- [x] 3. `lib/data/db/beverage_migration.dart`、`beverage_repo.dart`：v11 原子迁移、库管理、记录增改删、事务容量检查；测试历史隔离、跨日和回滚。
- [x] 4. `backup.dart`、`backup_repo.dart`、预览：v7/schema11、必需数组与结构验证、旧备份保留、新备份替换及往返测试。
- [x] 5. 搜索控制器：防抖、节流、缓存、过期响应隔离；平台 HTTP 适配器与 OFF 安全字段映射。OCR 平台桥与核对表单集成。
- [x] 6. `lib/features/calories/`：日期/合计、常喝最近、个人库、搜索、新建/编辑、份量/时间、撤销、删除、趋势；错误保存输入，防重提交。
- [x] 7. 全局主题/共用组件及导航迁移；设置独立路由保留返回栈；保护分析会话。
- [x] 8. 静态检查、650 项测试、11 项浏览器检查及 Web/Android release 构建通过；真机项目和外部服务限制另列验收单，未冒充已验收。

## Validation commands

```powershell
. ./scripts/env.ps1
flutter analyze
flutter test --reporter expanded
flutter build web --no-pub
flutter build apk --release --no-pub
```

用户已请求实现现有设计，本次继续内联执行，不重复设计审批；不提交已有未提交工作。
