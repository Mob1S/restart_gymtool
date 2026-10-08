import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// 执行器从**仓储层**拿，不从 data/db/ 直接拿 —— 见 executor_access.dart 的说明
import '../../data/repositories/executor_access.dart';
import '../../data/repositories/exercise_repo.dart';
import '../../domain/types.dart';
import '../../ui/theme.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/empty_state.dart';

/// 动作选择弹层：**按肌群分组、拼音序、带搜索**。
///
/// 这个弹层是旧项目 M2 那个**功能性缺口**的解药 ——
/// 当时「一次训练只能练一个动作」，用户真机用一次就发现换不了动作，
/// App 无法完成任何一次真实训练。这次它从第一版就在。
///
/// ## 下面这两个参数都不是可选的
///
/// Flutter 的 `showModalBottomSheet` **默认两样都不管**，实测：
///
/// - **键盘**：`bottom_sheet.dart` 里根本没有 `viewInsets` —— 弹层照旧铺到
///   屏幕最底，键盘直接盖住列表。实测 300dp 键盘下 6 行动作只剩 1 行露在外面，
///   而这是**搜索框带 `autofocus`** 的弹层，键盘一打开就在。
/// - **状态栏**：`useSafeArea` 默认 false，此时
///   `ModalBottomSheetRoute` 会对内容做 `MediaQuery.removePadding(removeTop: true)`
///   —— 于是弹层被拖到最高时，搜索框会钻到状态栏底下（实测只差 8dp）。
Future<Exercise?> showExercisePicker(BuildContext context) {
  return showModalBottomSheet<Exercise>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).colorScheme.surface,
    // 键盘让位：把弹层整体抬到键盘之上。
    // 读的是 `viewInsets`（键盘高度），**不是** SafeArea 的 padding。
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
      ),
      child: const _ExercisePickerSheet(),
    ),
  );
}

class _ExercisePickerSheet extends StatefulWidget {
  const _ExercisePickerSheet();
  @override
  State<_ExercisePickerSheet> createState() => _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends State<_ExercisePickerSheet> {
  List<Exercise>? _all;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final exec = context.read<SqlExecutor>();
    final list = await listExercises(exec);
    if (mounted) setState(() => _all = list);
  }

  @override
  Widget build(BuildContext context) {
    final c = appColors(context);
    final all = _all;

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      builder: (context, scrollController) {
        if (all == null) {
          return const Center(child: CircularProgressIndicator());
        }

        // 过滤 + 按肌群分组。**listExercises 已经按肌群名次 + 拼音序排好**，
        // 这里只需要按肌群切开，不要重排 —— 重排会让两处顺序不一致。
        final filtered = _query.isEmpty
            ? all
            : all.where((e) => e.name.contains(_query)).toList();

        final groups = <String, List<Exercise>>{};
        for (final e in filtered) {
          groups.putIfAbsent(e.muscleGroup ?? '其他', () => []).add(e);
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: '搜索动作',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(() => _query = v.trim()),
              ),
            ),
            Expanded(
              child: filtered.isEmpty
                  ? const EmptyState(message: '没有找到匹配的动作')
                  : ListView(
                      controller: scrollController,
                      children: [
                        for (final entry in groups.entries) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              AppSpacing.lg,
                              AppSpacing.md,
                              AppSpacing.lg,
                              AppSpacing.sm,
                            ),
                            child: Text(
                              entry.key,
                              style: TextStyle(
                                fontSize: AppFontSize.label,
                                letterSpacing: AppTracking.label,
                                color: c.textTertiary,
                              ),
                            ),
                          ),
                          for (final e in entry.value)
                            ListTile(
                              title: Text(e.name),
                              subtitle: e.equipment == null
                                  ? null
                                  : Text(e.equipment!),
                              onTap: () => Navigator.pop(context, e),
                            ),
                        ],
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}
