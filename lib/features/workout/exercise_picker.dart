import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/executor_access.dart';
import '../../data/repositories/exercise_picker_repo.dart';
import '../../data/repositories/exercise_preferences_repo.dart';
import '../../domain/exercise_preferences.dart';
import '../../domain/types.dart';
import '../../state/data_revision.dart';
import '../../state/exercise_preferences_controller.dart';
import '../../domain/workout_edit.dart';

Future<Exercise?> showExercisePicker(BuildContext context) =>
    _show<Exercise>(context, false);
Future<List<Exercise>?> showExerciseMultiPicker(BuildContext context) =>
    _show<List<Exercise>>(context, true);
Future<T?> _show<T>(BuildContext context, bool multi) =>
    showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: _ExercisePickerSheet(multi: multi),
      ),
    );

class _ExercisePickerSheet extends StatefulWidget {
  final bool multi;
  const _ExercisePickerSheet({required this.multi});
  @override
  State<_ExercisePickerSheet> createState() => _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends State<_ExercisePickerSheet> {
  ExercisePickerData? _data;
  String _query = '';
  bool _frequent = false;
  bool _initialized = false;
  final List<String> _selected = [];
  final Set<String> _saving = {};
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    try {
      final data = await loadExercisePickerData(context.read<SqlExecutor>());
      if (!mounted) return;
      setState(() {
        _data = data;
        if (!_initialized) {
          _frequent =
              data.recentIds.isNotEmpty ||
              data.preferences.values.any((p) => p.isFavorite);
        }
        _initialized = true;
      });
    } catch (_) {
      if (mounted) setState(() => _error = '动作加载失败，请重试');
    }
  }

  Future<void> _favorite(Exercise e) async {
    if (!_saving.add(e.id)) return;
    setState(() => _error = null);
    try {
      final current = _data!.preferences[e.id]!;
      final controller = context.read<ExercisePreferencesController?>();
      if (controller != null) {
        final result = await controller.save(
          e.id,
          expectedToken: current.token,
          isFavorite: !current.isFavorite,
        );
        if (result != WorkoutWriteResult.saved) {
          throw StateError(controller.message ?? '收藏未保存，请重试');
        }
      } else {
        await saveExercisePreference(
          context.read<SqlExecutor>(),
          e.id,
          expectedToken: current.token,
          isFavorite: !current.isFavorite,
        );
        if (mounted) context.read<DataRevision?>()?.changed();
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
    if (!mounted) return;
    await _load();
    if (mounted) setState(() => _saving.remove(e.id));
  }

  Widget _row(Exercise e) => ListTile(
    leading: widget.multi
        ? Icon(
            _selected.contains(e.id)
                ? Icons.check_box
                : Icons.check_box_outline_blank,
          )
        : null,
    selected: _selected.contains(e.id),
    title: Text(e.name),
    subtitle: e.equipment == null ? null : Text(e.equipment!),
    trailing: IconButton(
      constraints: const BoxConstraints.tightFor(width: 48, height: 48),
      padding: const EdgeInsets.all(12),
      tooltip: '收藏 ${e.name}',
      onPressed: _saving.contains(e.id) ? null : () => _favorite(e),
      icon: Icon(
        _data!.preferences[e.id]?.isFavorite == true
            ? Icons.star
            : Icons.star_border,
      ),
    ),
    onTap: () {
      if (!widget.multi) {
        Navigator.pop(context, e);
        return;
      }
      setState(() {
        if (!_selected.remove(e.id)) _selected.add(e.id);
      });
    },
  );
  @override
  Widget build(BuildContext context) => DraggableScrollableSheet(
    expand: false,
    initialChildSize: 0.85,
    minChildSize: 0.4,
    builder: (context, scroll) {
      final data = _data;
      if (data == null) {
        return Center(
          child: _error == null
              ? const CircularProgressIndicator()
              : TextButton(onPressed: _load, child: Text(_error!)),
        );
      }
      final groups = <String, List<Exercise>>{};
      if (_query.isNotEmpty || !_frequent) {
        for (final e in data.all.where(
          (e) => e.name.toLowerCase().contains(_query.toLowerCase()),
        )) {
          groups.putIfAbsent(e.muscleGroup ?? '其他', () => []).add(e);
        }
      } else {
        final favorites = data.all
            .where((e) => data.preferences[e.id]?.isFavorite == true)
            .toList();
        final recent = [
          for (final id in data.recentIds)
            for (final e in data.all)
              if (e.id == id && data.preferences[id]?.isFavorite != true) e,
        ];
        if (favorites.isNotEmpty) groups['收藏'] = favorites;
        if (recent.isNotEmpty) groups['最近使用'] = recent;
      }
      return SafeArea(
        top: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Semantics(
                label: '搜索动作',
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: '搜索动作',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) => setState(() => _query = v.trim()),
                ),
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                ChoiceChip(
                  label: const Text('常用'),
                  selected: _frequent,
                  onSelected: (_) => setState(() => _frequent = true),
                ),
                const SizedBox(width: 12),
                ChoiceChip(
                  label: const Text('全部'),
                  selected: !_frequent,
                  onSelected: (_) => setState(() => _frequent = false),
                ),
              ],
            ),
            if (_error != null) Text(_error!),
            Expanded(
              child: groups.isEmpty
                  ? const Center(child: Text('没有找到匹配的动作'))
                  : ListView(
                      controller: scroll,
                      children: [
                        for (final group in groups.entries) ...[
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                            child: Text(
                              group.key,
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                          ),
                          ...group.value.map(_row),
                        ],
                      ],
                    ),
            ),
            if (widget.multi)
              Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _selected.isEmpty
                        ? null
                        : () => Navigator.pop(context, [
                            for (final id in _selected)
                              data.all.firstWhere((e) => e.id == id),
                          ]),
                    child: Text('添加 ${_selected.length} 个动作'),
                  ),
                ),
              ),
          ],
        ),
      );
    },
  );
}
