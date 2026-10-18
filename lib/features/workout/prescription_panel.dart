import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../domain/types.dart';
import '../../domain/load_reference.dart';
import '../../data/repositories/executor_access.dart';
import '../../data/repositories/load_reference_repo.dart';
import '../../domain/training_prescription.dart';
import '../../state/data_revision.dart';

class PrescriptionPanel extends StatefulWidget {
  final SetEntry pending;
  final SessionPrescription? snapshot;
  final bool enabled;
  final Future<void> Function(LoadReference) onAdopt;
  const PrescriptionPanel({
    super.key,
    required this.pending,
    this.snapshot,
    required this.enabled,
    required this.onAdopt,
  });
  @override
  State<PrescriptionPanel> createState() => _PrescriptionPanelState();
}

class _PrescriptionPanelState extends State<PrescriptionPanel> {
  LoadReference? _reference;
  Timer? _timer;
  DataRevision? _revision;
  int _generation = 0;
  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.pending.detail?.intraRestStartedAt != null) {
        setState(() {});
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final revision = context.read<DataRevision?>();
    if (revision != _revision) {
      _revision?.removeListener(_load);
      _revision = revision;
      revision?.addListener(_load);
    }
  }

  @override
  void didUpdateWidget(covariant PrescriptionPanel old) {
    super.didUpdateWidget(old);
    if (old.pending.detail?.encode() != widget.pending.detail?.encode() ||
        old.pending.reps != widget.pending.reps) {
      _load();
    }
  }

  @override
  void dispose() {
    _generation++;
    _timer?.cancel();
    _revision?.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    final generation = ++_generation;
    try {
      final db = context.read<SqlExecutor>();
      final reference = await loadReferenceForPending(db, widget.pending.id);
      if (mounted && generation == _generation) {
        setState(() {
          _reference = reference;
        });
      }
    } catch (_) {
      if (mounted && generation == _generation) {
        setState(
          () => _reference = const LoadReference(message: '参考暂不可用，可手动记录'),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.pending.detail, t = d?.target, r = _reference;
    final elapsed = d?.intraRestStartedAt == null
        ? 0
        : ((DateTime.now().millisecondsSinceEpoch - d!.intraRestStartedAt!) /
                  1000)
              .floor();
    final remaining = ((t?.pauseSeconds ?? 0) - elapsed).clamp(0, 3600);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (t != null)
            Text(
              '${widget.snapshot?.stageName ?? '计划目标'} · ${t.label}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          if (t?.note.isNotEmpty == true) Text(t!.note),
          if (d?.isRestPause == true)
            Text(
              '第 ${d!.currentSegment + 1} / ${t!.segmentReps.length} 段${d.firstCompletedAt == null
                  ? ''
                  : d.segmentStartedAt != null
                  ? ' · 本段进行中'
                  : remaining > 0
                  ? ' · 组内休息还剩 $remaining 秒'
                  : ' · 可以继续下一段'}',
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            ),
          if (r != null)
            ExpansionTile(
              key: ValueKey('reference-${widget.pending.id}'),
              dense: true,
              visualDensity: VisualDensity.compact,
              tilePadding: EdgeInsets.zero,
              title: Text(
                r.reading == null
                    ? '个人参考'
                    : '参考 ${r.reading!.label} · ${r.trend}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              trailing: r.reading == null
                  ? null
                  : TextButton(
                      key: const ValueKey('adopt-load-reference'),
                      onPressed: widget.enabled
                          ? () async {
                              await widget.onAdopt(r);
                              if (mounted) _load();
                            }
                          : null,
                      child: const Text('采用'),
                    ),
              children: [
                Text(r.message),
                for (final evidence in r.evidence)
                  Text(evidence, style: Theme.of(context).textTheme.bodySmall),
                TextButton(onPressed: _load, child: const Text('重新获取参考')),
              ],
            ),
        ],
      ),
    );
  }
}
