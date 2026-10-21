import 'package:flutter/material.dart';

import '../../data/ids.dart';
import '../../domain/beverage.dart';
import '../../ui/tokens.dart';

/// Shared by manual entry, public results, OCR, library and historical edits.
class BeverageForm extends StatefulWidget {
  final Beverage? initial;
  final String? initialEnergy, initialVolume, initialName;
  final EnergyUnit? initialUnit;
  final EnergyBasis? initialBasis;
  final bool labelScan;
  const BeverageForm({
    super.key,
    this.initial,
    this.initialEnergy,
    this.initialVolume,
    this.initialName,
    this.initialUnit,
    this.initialBasis,
    this.labelScan = false,
  });
  @override
  State<BeverageForm> createState() => BeverageFormState();
}

class BeverageFormState extends State<BeverageForm> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(
    text: widget.initialName ?? widget.initial?.name,
  );
  late final _brand = TextEditingController(text: widget.initial?.brand);
  late final _variant = TextEditingController(text: widget.initial?.variant);
  late final _size = TextEditingController(text: widget.initial?.size);
  late final _sugar = TextEditingController(text: widget.initial?.sugar);
  late final _additions = TextEditingController(
    text: widget.initial?.additions,
  );
  late final _temperature = TextEditingController(
    text: widget.initial?.temperature,
  );
  late final _volume = TextEditingController(
    text: widget.labelScan
        ? widget.initialVolume
        : widget.initialVolume ?? widget.initial?.volumeMl,
  );
  late final _energy = TextEditingController(
    text: widget.labelScan
        ? widget.initialEnergy
        : widget.initialEnergy ?? widget.initial?.energyValue,
  );
  late final _note = TextEditingController(text: widget.initial?.sourceNote);
  late final _url = TextEditingController(text: widget.initial?.sourceUrl);
  late BeverageKind _kind = widget.initial?.kind ?? BeverageKind.packaged;
  late EnergyUnit? _unit = widget.labelScan
      ? widget.initialUnit
      : widget.initialUnit ?? widget.initial?.energyUnit ?? EnergyUnit.kcal;
  late EnergyBasis? _basis = widget.labelScan
      ? widget.initialBasis
      : widget.initialBasis ?? widget.initial?.basis ?? EnergyBasis.per100ml;
  late BeverageSource _source = widget.labelScan
      ? BeverageSource.label
      : widget.initial?.source ?? BeverageSource.estimate;
  bool _verified = false;

  void _configChanged(String _) {
    if (_kind == BeverageKind.prepared || widget.initial != null) {
      setState(() {
        _energy.clear();
        _source = BeverageSource.estimate;
        _verified = false;
      });
    }
  }

  Beverage? value() {
    if (!_form.currentState!.validate()) return null;
    final initial = widget.initial;
    final now = DateTime.now().millisecondsSinceEpoch;
    return Beverage(
      id: initial?.id ?? newId(),
      name: _name.text.trim(),
      brand: _brand.text.trim(),
      variant: _variant.text.trim(),
      size: _size.text.trim(),
      sugar: _sugar.text.trim(),
      additions: _additions.text.trim(),
      temperature: _temperature.text.trim(),
      kind: _kind,
      volumeMl: _volume.text.trim().isEmpty ? null : _volume.text.trim(),
      energyValue: _energy.text.trim().isEmpty ? null : _energy.text.trim(),
      energyUnit: _unit ?? EnergyUnit.kcal,
      basis: _basis ?? EnergyBasis.per100ml,
      source: _source,
      sourceNote: _note.text.trim(),
      sourceUrl: _url.text.trim().isEmpty ? null : _url.text.trim(),
      verifiedAt: _verified ? now : null,
      favorite: initial?.favorite ?? false,
      archived: initial?.archived ?? false,
      createdAt: initial?.createdAt ?? now,
      updatedAt: now,
    );
  }

  Widget _field(
    TextEditingController c,
    String label, {
    bool required = false,
    bool number = false,
    ValueChanged<String>? onChanged,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: AppSpacing.md),
    child: TextFormField(
      controller: c,
      decoration: InputDecoration(labelText: label),
      maxLength: number ? 40 : 500,
      buildCounter: (
        _, {
        required currentLength,
        required isFocused,
        maxLength,
      }) => null,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      onChanged: onChanged,
      validator: (v) {
        final text = v?.trim() ?? '';
        if (required && text.isEmpty) return '请填写$label';
        if (number &&
            text.isNotEmpty &&
            (!RegExp(r'^\d+(\.\d+)?$').hasMatch(text) ||
                (c == _volume && (double.tryParse(text) ?? 0) <= 0))) {
          return '请输入${c == _volume ? '正' : '非负'}十进制数';
        }
        return null;
      },
    ),
  );

  @override
  Widget build(BuildContext context) => Form(
    key: _form,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _field(_name, '饮料名称', required: true, onChanged: _configChanged),
        DropdownButtonFormField<BeverageKind>(
          initialValue: _kind,
          decoration: const InputDecoration(labelText: '类型'),
          items: const [
            DropdownMenuItem(value: BeverageKind.packaged, child: Text('包装饮料')),
            DropdownMenuItem(value: BeverageKind.prepared, child: Text('现制饮品')),
          ],
          onChanged: (v) => setState(() => _kind = v!),
        ),
        const SizedBox(height: AppSpacing.md),
        _field(_brand, '品牌', onChanged: _configChanged),
        _field(_variant, '版本（普通／无糖等）', onChanged: _configChanged),
        _field(
          _size,
          _kind == BeverageKind.prepared ? '杯型／规格' : '包装规格',
          onChanged: _configChanged,
        ),
        if (_kind == BeverageKind.prepared) ...[
          _field(_sugar, '糖度', onChanged: _configChanged),
          _field(_additions, '加料', onChanged: _configChanged),
          _field(_temperature, '冷热（可选）', onChanged: _configChanged),
          const Text('不同配置的热量需单独核对；糖度比例不代表全杯热量比例。'),
          const SizedBox(height: AppSpacing.md),
        ],
        _field(_volume, '每份体积 mL（未知可留空）', number: true),
        _field(_energy, '标注能量（留空为待补热量）', number: true),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            SizedBox(
              width: 130,
              child: DropdownButtonFormField<EnergyUnit>(
                isExpanded: true,
                initialValue: _unit,
                validator: (value) =>
                    _energy.text.trim().isNotEmpty && value == null
                    ? '请选择单位'
                    : null,
                decoration: const InputDecoration(labelText: '能量单位'),
                items: const [
                  DropdownMenuItem(value: EnergyUnit.kcal, child: Text('kcal')),
                  DropdownMenuItem(value: EnergyUnit.kj, child: Text('kJ')),
                ],
                onChanged: (v) => setState(() => _unit = v!),
              ),
            ),
            SizedBox(
              width: 180,
              child: DropdownButtonFormField<EnergyBasis>(
                isExpanded: true,
                initialValue: _basis,
                validator: (value) =>
                    _energy.text.trim().isNotEmpty && value == null
                    ? '请选择基准'
                    : null,
                decoration: const InputDecoration(labelText: '计量基准'),
                items: const [
                  DropdownMenuItem(
                    value: EnergyBasis.per100ml,
                    child: Text('每 100 mL'),
                  ),
                  DropdownMenuItem(
                    value: EnergyBasis.perServing,
                    child: Text('每瓶／杯／份'),
                  ),
                ],
                onChanged: (v) => setState(() => _basis = v!),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        const Text('每 100 g 不能直接当作每 100 mL；请提供可验证的每份依据。'),
        const SizedBox(height: AppSpacing.md),
        DropdownButtonFormField<BeverageSource>(
          key: ValueKey(_source),
          initialValue: _source,
          decoration: const InputDecoration(labelText: '数据来源'),
          items: [
            for (final s in BeverageSource.values)
              DropdownMenuItem(value: s, child: Text(s.label)),
          ],
          onChanged: (v) => setState(() => _source = v!),
        ),
        const SizedBox(height: AppSpacing.md),
        _field(_note, '来源说明'),
        _field(_url, '来源网址（可选）'),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: _verified,
          title: const Text('已核对当前规格与能量依据'),
          subtitle: const Text('核对状态独立于来源；公共数据不会因此成为官方数据。'),
          onChanged: (v) => setState(() => _verified = v!),
        ),
      ],
    ),
  );
  @override
  void dispose() {
    for (final c in [
      _name,
      _brand,
      _variant,
      _size,
      _sugar,
      _additions,
      _temperature,
      _volume,
      _energy,
      _note,
      _url,
    ]) {
      c.dispose();
    }
    super.dispose();
  }
}
