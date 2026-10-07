/// 把接缝接口 `SqlExecutor` 经**仓储层**再导出给界面层。
///
/// ## 这个文件为什么存在
///
/// 计划 Task 18/19 的代码写的是 `import '../../data/db/sql_executor.dart';`
/// —— 界面层直接伸手进 `data/db/`。这与规格 §2.2 的规则 1
/// （「`features/` 与 `ui/` 永不直接 import `data/db/`，**只经
/// `data/repositories/`**」，由 `test/layering_test.dart` 机械强制）**直接冲突**。
/// 实测：照计划原文写，那条守卫会红，报出
/// `lib/features/workout/exercise_picker.dart → ../../data/db/sql_executor.dart`
/// 与 `lib/features/workout/summary_page.dart → ../../data/db/sql_executor.dart`。
///
/// 两边的态度是明确的：规格把「只经 repositories」写成了规则，守卫已经按它
/// 交付并长期是绿的。所以按规则办 —— **界面层要拿执行器，就从这一层拿**，
/// 而不是把守卫放宽（放宽等于让规则作废）。
///
/// ## 它只是再导出
///
/// 这里**不加任何代码**，只把 db/ 里的那个接口搬到界面层可以 import 的路径上。
/// 界面层拿到的仍然是同一个 `SqlExecutor`（三后端共用），
/// 差别只在「这个类型的名字从哪条路径进来」。
library;

export '../db/sql_executor.dart';
