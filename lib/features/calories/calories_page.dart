import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/beverage_repo.dart';
import '../../data/repositories/executor_access.dart';
import '../../domain/beverage.dart';
import '../../domain/beverage_trends.dart';
import '../../domain/local_date.dart';
import '../../state/data_revision.dart';
import '../../state/data_revision_loader.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/app_card.dart';
import 'beverage_picker_page.dart';
import 'calorie_trends_page.dart';
import 'drink_editor_page.dart';

class CaloriesPage extends StatefulWidget {
  const CaloriesPage({super.key});
  @override
  State<CaloriesPage> createState() => _CaloriesPageState();
}

class _CaloriesPageState extends State<CaloriesPage>
    with DataRevisionLoader<CaloriesPage>, WidgetsBindingObserver {
  LocalDate _date = LocalDate.fromDateTime(DateTime.now());
  LocalDate _today = LocalDate.fromDateTime(DateTime.now());
  Timer? _midnight;
  List<Beverage> _library = [];
  List<DrinkRecord>? _records;
  String? _error;
  bool _deleting = false;
  int _generation = 0;
  BeverageRepo get _repo => BeverageRepo(context.read<SqlExecutor>());
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _schedule();
  }

  void _schedule() {
    _midnight?.cancel();
    _midnight = Timer(
      LocalDate.fromDateTime(DateTime.now()).nextStart
              .difference(DateTime.now()) +
          const Duration(seconds: 1),
      _checkDate,
    );
  }

  void _checkDate() {
    final now = LocalDate.fromDateTime(DateTime.now());
    if (_today != now) {
      if (_date == _today) _date = now;
      _today = now;
      reloadData();
    }
    _schedule();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkDate();
  }

  @override
  Future<void> reloadData() async {
    final generation = ++_generation;
    try {
      final library = await _repo.library();
      final records = await _repo.records(from: _date, through: _date);
      if (mounted && generation == _generation) {
        setState(() {
          _library = library;
          _records = records;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(() => _error = '记录读取失败，请重试');
      }
    }
  }

  void _changeDate(LocalDate date) {
    setState(() {
      _date = date;
      _records = null;
    });
    reloadData();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _date.start,
      firstDate: DateTime(1970),
      lastDate: DateTime(2100),
    );
    if (date != null && mounted) _changeDate(LocalDate.fromDateTime(date));
  }

  Future<void> _record({Beverage? beverage, DrinkRecord? existing}) async {
    final record = await Navigator.of(context, rootNavigator: true)
        .push<DrinkRecord>(
          MaterialPageRoute(
            builder: (_) => beverage == null
                ? BeveragePickerPage(date: _date)
                : DrinkEditorPage(
                    beverage: beverage,
                    date: _date,
                    record: existing,
                  ),
          ),
        );
    if (!mounted || record == null) return;
    await reloadData();
    if (!mounted || existing != null) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('饮料已记录'),
        action: SnackBarAction(
          label: '撤销',
          onPressed: () => _delete(record, confirm: false),
        ),
      ),
    );
  }

  Future<void> _delete(DrinkRecord record, {bool confirm = true}) async {
    if (!mounted || _deleting) return;
    if (confirm) {
      final allowed = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('删除饮用记录？'),
          content: Text('将删除本次 ${record.snapshot.name} 的饮用记录。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('删除'),
            ),
          ],
        ),
      );
      if (allowed != true || !mounted) return;
    }
    setState(() => _deleting = true);
    try {
      await _repo.deleteRecord(record.id);
      if (!mounted) return;
      context.read<DataRevision?>()?.changed();
      await reloadData();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('删除失败，请重试')));
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final total = DrinkTotal(_records ?? []);
    final quick = _library.take(6).toList();
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screenH),
        children: [
          Row(
            children: [
              IconButton(
                tooltip: '前一天',
                onPressed: () => _changeDate(
                  LocalDate.fromDateTime(
                    DateTime(_date.year, _date.month, _date.day - 1),
                  ),
                ),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: TextButton(
                  onPressed: _pickDate,
                  child: Text(
                    _date == _today ? '今天 · ${_date.key}' : _date.key,
                  ),
                ),
              ),
              IconButton(
                tooltip: '后一天',
                onPressed: () => _changeDate(
                  LocalDate.fromDateTime(
                    DateTime(_date.year, _date.month, _date.day + 1),
                  ),
                ),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          if (_date != _today)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _changeDate(_today),
                child: const Text('回到今天'),
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('已记录饮料热量'),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  _records == null ? '—' : total.display,
                  style: Theme.of(context).textTheme.headlineLarge,
                ),
                if (total.note.isNotEmpty) Text(total.note),
                const SizedBox(height: AppSpacing.sm),
                const Text('只记录饮料，不代表全天摄入。'),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              TextButton.icon(
                onPressed: () =>
                    Navigator.of(context, rootNavigator: true).push(
                      MaterialPageRoute(
                        builder: (_) => CalorieTrendsPage(date: _date),
                      ),
                    ),
                icon: const Icon(Icons.bar_chart),
                label: const Text('7 / 30 天趋势'),
              ),
              TextButton.icon(
                onPressed: () async {
                  await Navigator.of(context, rootNavigator: true).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          BeveragePickerPage(date: _date, manage: true),
                    ),
                  );
                  if (mounted) reloadData();
                },
                icon: const Icon(Icons.local_drink_outlined),
                label: const Text('管理饮料库'),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text('常喝 / 最近', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: AppSpacing.sm),
          if (quick.isEmpty) const Text('添加常喝的饮料，下次可直接选份量。'),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final b in quick)
                ActionChip(
                  avatar: Icon(
                    b.favorite ? Icons.star : Icons.local_drink_outlined,
                    size: 18,
                  ),
                  label: Text(b.name),
                  onPressed: () => _record(beverage: b),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.xl),
          Text('当天明细', style: Theme.of(context).textTheme.titleLarge),
          if (_error != null) ...[
            Text(_error!),
            TextButton(onPressed: reloadData, child: const Text('重试')),
          ] else if (_records == null)
            const LinearProgressIndicator()
          else if (_records!.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Text('尚未记录\n选择饮料，记录喝了多少。'),
            ),
          for (final r in _records ?? <DrinkRecord>[])
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(r.snapshot.name),
              subtitle: Text(
                '${r.snapshot.description}\n${r.amount} ${r.unit == DrinkUnit.ml ? 'mL' : '份'} · ${DateTime.fromMillisecondsSinceEpoch(r.occurredAt).toString().substring(11, 16)} · ${r.snapshot.source.label}',
              ),
              isThreeLine: true,
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    r.calories == null ? '待补热量' : '${r.calories!.display} kcal',
                  ),
                  PopupMenuButton<String>(
                    tooltip: '记录操作',
                    enabled: !_deleting,
                    onSelected: (v) => v == 'edit'
                        ? _record(beverage: r.snapshot, existing: r)
                        : _delete(r),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'edit', child: Text('修改')),
                      PopupMenuItem(value: 'delete', child: Text('删除')),
                    ],
                  ),
                ],
              ),
              onTap: () => _record(beverage: r.snapshot, existing: r),
            ),
          const SizedBox(height: AppSpacing.xl),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.screenH,
            AppSpacing.sm,
            AppSpacing.screenH,
            AppSpacing.sm,
          ),
          child: FilledButton.icon(
            onPressed: () => _record(),
            icon: const Icon(Icons.add),
            label: const Text('记录饮料'),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _midnight?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
