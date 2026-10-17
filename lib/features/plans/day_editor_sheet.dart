import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/executor_access.dart';
import '../../data/repositories/exercise_repo.dart';
import '../../domain/training_plans.dart';
import '../workout/exercise_picker.dart';

Future<TrainingDayDraft?> showDayEditorSheet(
  BuildContext context, {
  TrainingDayDraft? day,
}) => showModalBottomSheet<TrainingDayDraft>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => _DayEditor(day: day),
);

class _DayEditor extends StatefulWidget {
  final TrainingDayDraft? day;
  const _DayEditor({this.day});
  @override
  State<_DayEditor> createState() => _DayEditorState();
}

class _DayEditorState extends State<_DayEditor> {
  late final TextEditingController _name;
  late List<String> _ids;
  Map<String, String> _names = {};
  bool _dirty = false, _allowClose = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.day?.name ?? '');
    _ids = [...?widget.day?.exerciseIds];
    _loadNames();
  }

  Future<void> _loadNames() async {
    final exercises = await listExercises(
      context.read<SqlExecutor>(),
      includeArchived: true,
    );
    if (mounted) {
      setState(() {
        _names = {
          for (final e in exercises)
            e.id: '${e.name}${e.isArchived ? '（归档）' : ''}',
        };
      });
    }
  }

  void _close(TrainingDayDraft? value) {
    setState(() => _allowClose = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context, value);
    });
  }

  Future<void> _cancel() async {
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('丢弃未保存的训练日？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('继续编辑'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('丢弃'),
            ),
          ],
        ),
      );
      if (discard != true || !mounted) return;
    }
    _close(null);
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _allowClose || !_dirty,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) _cancel();
    },
    child: Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.85,
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        widget.day == null ? '添加训练日' : '编辑训练日',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                    TextButton(onPressed: _cancel, child: const Text('取消')),
                    TextButton(
                      onPressed: () {
                        if (_name.text.trim().isEmpty) {
                          setState(() => _error = '请输入训练日名称');
                          return;
                        }
                        _close(
                          TrainingDayDraft(
                            id: widget.day?.id,
                            name: _name.text.trim(),
                            exerciseIds: _ids,
                          ),
                        );
                      },
                      child: const Text('完成'),
                    ),
                  ],
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList.list(
                children: [
                  TextField(
                    controller: _name,
                    decoration: InputDecoration(
                      labelText: '训练日名称',
                      errorText: _error,
                    ),
                    onChanged: (_) => setState(() {
                      _dirty = true;
                      _error = null;
                    }),
                  ),
                  const SizedBox(height: 16),
                  if (_ids.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('还没有动作。空训练日也可以保存，开训后可再添加。'),
                    ),
                  for (var i = 0; i < _ids.length; i++)
                    Card(
                      child: Column(
                        children: [
                          ListTile(
                            title: Text('${i + 1}. ${_names[_ids[i]] ?? '动作'}'),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.end,
                            children: [
                              IconButton(
                                tooltip: '上移动作',
                                onPressed: i == 0
                                    ? null
                                    : () => setState(() {
                                        _ids.insert(i - 1, _ids.removeAt(i));
                                        _dirty = true;
                                      }),
                                icon: const Icon(Icons.arrow_upward),
                              ),
                              IconButton(
                                tooltip: '下移动作',
                                onPressed: i == _ids.length - 1
                                    ? null
                                    : () => setState(() {
                                        _ids.insert(i + 1, _ids.removeAt(i));
                                        _dirty = true;
                                      }),
                                icon: const Icon(Icons.arrow_downward),
                              ),
                              IconButton(
                                tooltip: '移除训练日动作',
                                onPressed: () => setState(() {
                                  _ids.removeAt(i);
                                  _dirty = true;
                                }),
                                icon: const Icon(Icons.close),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final selected = await showExerciseMultiPicker(context);
                      if (!mounted || selected == null || selected.isEmpty) {
                        return;
                      }
                      setState(() {
                        _ids.addAll(selected.map((e) => e.id));
                        for (final e in selected) {
                          _names[e.id] = e.name;
                        }
                        _dirty = true;
                      });
                    },
                    icon: const Icon(Icons.add),
                    label: const Text('添加动作'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
