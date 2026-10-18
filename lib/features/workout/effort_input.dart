import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/training_prescription.dart';
import '../../data/repositories/executor_access.dart';
import '../../data/repositories/settings_repo.dart';

class EffortInput extends StatefulWidget {
  final Effort? value;
  final ValueChanged<Effort?> onChanged;
  final bool enabled, segment;
  const EffortInput({
    super.key,
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.segment = false,
  });
  @override
  State<EffortInput> createState() => _EffortInputState();
}

class _EffortInputState extends State<EffortInput> {
  String _mode = 'rpe';
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final mode = await getSetting(
        context.read<SqlExecutor>(),
        'effort_input_mode',
      );
      if (mounted && {'rpe', 'rir'}.contains(mode)) {
        setState(() => _mode = mode!);
      }
    } catch (_) {}
  }

  Future<void> _choose() async {
    final choices = <Effort?>[
      null,
      if (_mode == 'rpe') ...[
        const Effort('rpe', 6, bound: 'below'),
        for (var v = 12; v <= 20; v++) Effort('rpe', v / 2),
      ] else ...[
        for (var v = 0; v <= 10; v++) Effort('rir', v.toDouble()),
        const Effort('rir', 10, bound: 'above'),
      ],
    ];
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (sheet) => SizedBox(
        height: MediaQuery.sizeOf(sheet).height * .65,
        child: ListView(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                '${widget.segment ? '本段' : '本组'}用力程度（选填）',
                style: Theme.of(sheet).textTheme.titleLarge,
              ),
            ),
            for (final value in choices)
              ListTile(
                title: Text(value?.label ?? '不记录用力程度'),
                subtitle: value == null ? null : Text(value.explanation),
                onTap: () {
                  widget.onChanged(value);
                  Navigator.pop(sheet);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Wrap(
    alignment: WrapAlignment.center,
    crossAxisAlignment: WrapCrossAlignment.center,
    children: [
      TextButton(
        key: const ValueKey('effort-picker'),
        onPressed: widget.enabled ? _choose : null,
        child: Text(
          widget.value?.label ??
              '${widget.segment ? '本段 ' : ''}${_mode.toUpperCase()} · 选填',
        ),
      ),
      TextButton(
        onPressed: widget.enabled
            ? () async {
                final next = _mode == 'rpe' ? 'rir' : 'rpe';
                setState(() => _mode = next);
                try {
                  await setSetting(
                    context.read<SqlExecutor>(),
                    'effort_input_mode',
                    next,
                  );
                } catch (_) {}
              }
            : null,
        child: Text('切换 ${_mode == 'rpe' ? 'RIR' : 'RPE'}'),
      ),
      if (widget.value != null)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Text(
            widget.value!.explanation,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
    ],
  );
}
