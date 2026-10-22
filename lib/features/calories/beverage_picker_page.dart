import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/ids.dart';
import '../../plugins/api/feature_clients.dart';
import '../../plugins/flutter/plugin_ui_adapter.dart';
import '../../plugins/api/plugin_runtime.dart';
import '../../domain/beverage.dart';
import '../../domain/local_date.dart';
import '../../state/beverage_search_controller.dart';
import '../../state/data_revision.dart';
import '../../ui/tokens.dart';
import 'beverage_editor_page.dart';
import 'drink_editor_page.dart';

class BeveragePickerPage extends StatefulWidget {
  final LocalDate date;
  final bool manage;
  const BeveragePickerPage({
    super.key,
    required this.date,
    this.manage = false,
  });
  @override
  State<BeveragePickerPage> createState() => _BeveragePickerPageState();
}

class _BeveragePickerPageState extends State<BeveragePickerPage> {
  late final _client = caloriesClient(context);
  late final _search = BeverageSearchController(
    find: _client.search,
    onCancel: _client.cancelSearch,
  );
  final _query = TextEditingController();
  List<Beverage>? _library;
  String? _error;
  bool _busy = false, _archived = false;
  Beverage? _pending;
  void Function()? _removeActivity;
  CaloriesClient get _repo => _client;
  @override
  void initState() {
    super.initState();
    _removeActivity = caloriesActivities(context)?.register(
      () => _busy
          ? StopDecision.busy
          : _pending != null
          ? StopDecision.unsavedChanges
          : StopDecision.ready,
      () async {
        await _search.cancelRequests();
      },
    );
    _search.addListener(_refresh);
    _load();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    try {
      final library = await _repo.library(includeArchived: true);
      if (mounted) {
        setState(() {
          _library = library;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = '饮料库读取失败，请重试');
    }
  }

  Future<void> _persist(Beverage b) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _repo.saveBeverage(b);
      if (!mounted) return;
      context.read<DataRevision?>()?.changed();
      _pending = null;
      await _load();
    } catch (e) {
      if (mounted) {
        setState(() {
          _pending = b;
          _error = '保存失败，资料已保留：$e';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _edit({
    Beverage? initial,
    bool? camera,
    bool public = false,
  }) async {
    if (public && initial != null) {
      setState(() => _busy = true);
      try {
        initial = await _client.details(initial);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('公共详情未加载，请对照包装补全热量资料。')));
        }
      }
      if (!mounted) return;
      setState(() => _busy = false);
    }
    if (public && initial != null) {
      initial = Beverage.fromJson({...initial.toJson(), 'id': newId()});
    }
    final b = await Navigator.of(context, rootNavigator: true).push<Beverage>(
      MaterialPageRoute(
        builder: (_) =>
            BeverageEditorPage(initial: initial, scanCamera: camera),
      ),
    );
    if (b == null || !mounted) return;
    if (widget.manage) {
      await _persist(b);
    } else {
      await _record(b, newBeverage: true);
    }
  }

  Future<void> _record(Beverage b, {bool newBeverage = false}) async {
    final record = await Navigator.of(context, rootNavigator: true)
        .push<DrinkRecord>(
          MaterialPageRoute(
            builder: (_) => DrinkEditorPage(
              beverage: b,
              date: widget.date,
              saveBeverage: newBeverage,
            ),
          ),
        );
    if (record != null && mounted) Navigator.of(context).pop(record);
  }

  Widget _row(Beverage b, {bool public = false}) => ListTile(
    contentPadding: EdgeInsets.zero,
    leading: Icon(
      b.archived
          ? Icons.archive_outlined
          : b.favorite
          ? Icons.star
          : Icons.local_drink_outlined,
    ),
    title: Text(b.name),
    subtitle: Text(
      [
        b.description,
        b.energyLabel,
        public ? 'Open Food Facts · 需核对' : b.source.label,
      ].where((s) => s.isNotEmpty).join('\n'),
    ),
    isThreeLine: true,
    onTap: _busy
        ? null
        : () {
            if (public || widget.manage) {
              _edit(initial: b, public: public);
            } else {
              _record(b);
            }
          },
    trailing: public
        ? const Icon(Icons.chevron_right)
        : PopupMenuButton<String>(
            enabled: !_busy,
            tooltip: '饮料操作',
            onSelected: (v) {
              if (v == 'edit') {
                _edit(initial: b);
              } else if (v == 'favorite') {
                _persist(b.copyWith(favorite: !b.favorite));
              } else {
                _persist(b.copyWith(archived: !b.archived));
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'edit', child: Text('编辑资料')),
              PopupMenuItem(
                value: 'favorite',
                child: Text(b.favorite ? '取消收藏' : '收藏'),
              ),
              PopupMenuItem(
                value: 'archive',
                child: Text(b.archived ? '恢复到饮料库' : '归档（保留历史）'),
              ),
            ],
          ),
  );
  @override
  Widget build(BuildContext context) {
    final query = _query.text.trim().toLowerCase();
    final local = (_library ?? [])
        .where(
          (b) =>
              b.archived == _archived &&
              '${b.name} ${b.description}'.toLowerCase().contains(query),
        )
        .toList();
    final status = _search.status;
    return Scaffold(
      appBar: AppBar(title: Text(widget.manage ? '个人饮料库' : '选择饮料')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.screenH),
        children: [
          TextField(
            controller: _query,
            decoration: const InputDecoration(
              labelText: '搜索饮料、品牌或规格',
              prefixIcon: Icon(Icons.search),
            ),
            onChanged: (v) {
              setState(() {});
              _search.update(v);
            },
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _edit(),
                icon: const Icon(Icons.add),
                label: const Text('手动添加'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _edit(camera: false),
                icon: const Icon(Icons.image_outlined),
                label: const Text('图片识别'),
              ),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _edit(camera: true),
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('拍照识别'),
              ),
            ],
          ),
          if (widget.manage)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('查看已归档饮料'),
              value: _archived,
              onChanged: (v) => setState(() => _archived = v),
            ),
          const SizedBox(height: AppSpacing.lg),
          Text('个人饮料库', style: Theme.of(context).textTheme.titleLarge),
          if (_error != null) ...[
            Text(_error!),
            TextButton(
              onPressed: _pending == null ? _load : () => _persist(_pending!),
              child: Text(_pending == null ? '重试' : '重试保存'),
            ),
          ],
          if (_busy || _library == null) const LinearProgressIndicator(),
          if (_library != null && local.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.xl),
              child: Text('没有匹配的个人饮料，可搜索公共资料或添加。'),
            ),
          for (final b in local) _row(b),
          const Divider(height: AppSpacing.xxl),
          Text('公共饮料搜索', style: Theme.of(context).textTheme.titleLarge),
          const Text('Open Food Facts · 社区贡献数据（ODbL）\n规格和热量请对照实际包装；中文覆盖可能有限。'),
          const SizedBox(height: AppSpacing.md),
          if (status == PublicSearchStatus.idle) const Text('输入至少两个字符开始搜索。'),
          if (status == PublicSearchStatus.loading)
            const LinearProgressIndicator(),
          if (status == PublicSearchStatus.empty)
            const Text('没有找到公共结果。可以用图片或手动添加。'),
          if (status == PublicSearchStatus.failed ||
              status == PublicSearchStatus.timeout) ...[
            Text(
              status == PublicSearchStatus.timeout
                  ? '公共搜索超时，请稍后重试。'
                  : '公共搜索暂不可用，请检查网络或稍后重试。个人饮料库仍可使用。',
            ),
            TextButton(
              onPressed: () => _search.update(_query.text, immediate: true),
              child: const Text('重试公共搜索'),
            ),
          ],
          for (final b in _search.results) _row(b, public: true),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _removeActivity?.call();
    _search.removeListener(_refresh);
    _search.dispose();
    _query.dispose();
    super.dispose();
  }
}
