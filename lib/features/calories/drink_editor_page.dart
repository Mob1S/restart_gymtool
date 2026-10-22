import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/ids.dart';
import '../../plugins/flutter/plugin_ui_adapter.dart';
import '../../plugins/api/plugin_runtime.dart';
import '../../domain/beverage.dart';
import '../../domain/local_date.dart';
import '../../state/data_revision.dart';
import '../../ui/tokens.dart';
import '../../ui/widgets/app_card.dart';
import 'beverage_editor_page.dart';

class DrinkEditorPage extends StatefulWidget {
  final Beverage beverage;
  final LocalDate date;
  final DrinkRecord? record;
  final bool saveBeverage;
  const DrinkEditorPage({
    super.key,
    required this.beverage,
    required this.date,
    this.record,
    this.saveBeverage = false,
  });
  @override
  State<DrinkEditorPage> createState() => _DrinkEditorPageState();
}

class _DrinkEditorPageState extends State<DrinkEditorPage> {
  late Beverage _beverage = widget.beverage;
  late DrinkUnit _unit =
      widget.record?.unit ??
      (_beverage.volumeMl != null || _beverage.basis == EnergyBasis.perServing
          ? DrinkUnit.serving
          : DrinkUnit.ml);
  late final _amount = TextEditingController(
    text: widget.record?.amount ?? (_unit == DrinkUnit.serving ? '1' : '100'),
  );
  late DateTime _time = widget.record == null
      ? DateTime(
          widget.date.year,
          widget.date.month,
          widget.date.day,
          DateTime.now().hour,
          DateTime.now().minute,
        )
      : DateTime.fromMillisecondsSinceEpoch(widget.record!.occurredAt);
  bool _busy = false;
  bool _changedSnapshot = false;
  String? _error;
  void Function()? _removeActivity;
  @override
  void initState() {
    super.initState();
    _removeActivity = caloriesActivities(context)?.register(
      () => _busy ? StopDecision.busy : StopDecision.unsavedChanges,
      () async {},
    );
  }

  String get _preview {
    try {
      return _beverage.calculate(_amount.text, _unit)?.display ?? '待补热量';
    } catch (_) {
      return '请核对数量与单位';
    }
  }

  Future<void> _changeDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _time,
      firstDate: DateTime(1970),
      lastDate: DateTime(2100),
    );
    if (d == null || !mounted) return;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_time),
    );
    if (t != null && mounted) {
      setState(
        () => _time = DateTime(d.year, d.month, d.day, t.hour, t.minute),
      );
    }
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final record = DrinkRecord(
        id: widget.record?.id ?? newId(),
        beverageId: widget.record == null
            ? _beverage.id
            : widget.record!.beverageId,
        snapshot: _beverage,
        occurredAt: _time.millisecondsSinceEpoch,
        date: LocalDate.fromDateTime(_time),
        amount: _amount.text.trim(),
        unit: _unit,
      );
      await caloriesClient(
        context,
      ).saveRecord(record, newBeverage: widget.saveBeverage ? _beverage : null);
      if (!mounted) return;
      context.read<DataRevision?>()?.changed();
      Navigator.of(context).pop(record);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '保存失败：$e';
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !_busy,
    child: Scaffold(
      appBar: AppBar(title: Text(widget.record == null ? '记录饮料' : '修改饮用记录')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screenH),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _beverage.name,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                Text(_beverage.description),
                Text(_beverage.energyLabel),
                Text(
                  '${_beverage.source.label} · ${_beverage.verifiedAt == null ? '未核对' : '已核对'}',
                ),
                if (_beverage.sourceNote.isNotEmpty) Text(_beverage.sourceNote),
                if (_beverage.sourceUrl != null)
                  SelectableText(_beverage.sourceUrl!),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          TextField(
            controller: _amount,
            enabled: !_busy,
            decoration: const InputDecoration(labelText: '饮用量'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: AppSpacing.md),
          DropdownButtonFormField<DrinkUnit>(
            key: ValueKey(_unit),
            initialValue: _unit,
            decoration: const InputDecoration(labelText: '饮用单位'),
            items: [
              if (_beverage.basis == EnergyBasis.per100ml ||
                  _beverage.volumeMl != null)
                const DropdownMenuItem(value: DrinkUnit.ml, child: Text('mL')),
              if (_beverage.basis == EnergyBasis.perServing ||
                  _beverage.volumeMl != null)
                const DropdownMenuItem(
                  value: DrinkUnit.serving,
                  child: Text('瓶／杯／份'),
                ),
            ],
            onChanged: _busy
                ? null
                : (v) => setState(() {
                    _unit = v!;
                    _amount.text = v == DrinkUnit.serving
                        ? '1'
                        : (_beverage.volumeMl ?? '100');
                  }),
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            children: [
              for (final choice
                  in _unit == DrinkUnit.serving
                      ? ['0.5', '1', '2']
                      : ['100', '250', '500'])
                ActionChip(
                  label: Text(
                    '$choice ${_unit == DrinkUnit.serving ? '份' : 'mL'}',
                  ),
                  onPressed: _busy
                      ? null
                      : () => setState(() => _amount.text = choice),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            '本次热量：$_preview${_preview == '待补热量' || _preview.startsWith('请') ? '' : ' kcal'}',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('发生时间'),
            subtitle: Text(_time.toString().substring(0, 16)),
            trailing: const Icon(Icons.edit_calendar_outlined),
            onTap: _busy ? null : _changeDate,
          ),
          if (widget.record != null)
            TextButton(
              onPressed: _busy
                  ? null
                  : () async {
                      final b = await Navigator.of(context, rootNavigator: true)
                          .push<Beverage>(
                            MaterialPageRoute(
                              builder: (_) =>
                                  BeverageEditorPage(initial: _beverage),
                            ),
                          );
                      if (b != null && mounted) {
                        setState(() {
                          _beverage = b;
                          _changedSnapshot = true;
                          _unit = b.basis == EnergyBasis.per100ml
                              ? DrinkUnit.ml
                              : DrinkUnit.serving;
                        });
                      }
                    },
              child: const Text('修正本条记录的热量依据'),
            ),
          if (_changedSnapshot) const Text('只修正当前历史快照，其他记录和个人饮料库不变。'),
          if (_error != null)
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? '正在保存…' : '保存记录'),
          ),
        ],
      ),
    ),
  );
  @override
  void dispose() {
    _removeActivity?.call();
    _amount.dispose();
    super.dispose();
  }
}
