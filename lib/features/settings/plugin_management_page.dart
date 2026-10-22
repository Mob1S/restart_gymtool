import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../plugins/api/plugin_runtime.dart';
import '../../plugins/runtime/plugin_manager.dart';

class PluginManagementPage extends StatelessWidget {
  const PluginManagementPage({super.key});
  @override
  Widget build(BuildContext context) {
    final manager = context.watch<PluginManager>();
    return Scaffold(
      appBar: AppBar(title: const Text('插件管理')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('内置插件随应用提供。停用保留记录、媒体和设置，重新启用后可继续使用。'),
          const SizedBox(height: 16),
          for (final manifest in manager.manifests)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile(
                      title: Text(manifest.name),
                      subtitle: Text(
                        manifest.requiredByHost
                            ? '必需能力 · 始终启用'
                            : _state(manager.stateOf(manifest.id)),
                      ),
                      value: manager.isEnabled(manifest.id),
                      onChanged:
                          manifest.requiredByHost ||
                              {
                                PluginState.starting,
                                PluginState.stopping,
                              }.contains(manager.stateOf(manifest.id)) ||
                              !manifest.platforms.contains(manager.platform)
                          ? null
                          : (enabled) =>
                                _toggle(context, manager, manifest.id, enabled),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(manifest.description),
                          const SizedBox(height: 8),
                          Text(
                            '版本 ${manifest.version} · 支持 ${manifest.platforms.join(' / ')}',
                          ),
                          if (manifest.requiredCapabilities.isNotEmpty)
                            Text(
                              '所需能力：${manifest.requiredCapabilities.map(_capability).join('、')}',
                            ),
                          if (manifest.optionalCapabilities.isNotEmpty)
                            Text(
                              '可选能力：${manifest.optionalCapabilities.map(_capability).join('、')}',
                            ),
                          if (!manifest.platforms.contains(manager.platform))
                            const Text('当前平台不支持此插件'),
                          if (manager.errorOf(manifest.id) != null)
                            Text(
                              manager.errorOf(manifest.id)!.message,
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          if (manager.stateOf(manifest.id) ==
                                  PluginState.failed &&
                              manifest.platforms.contains(manager.platform))
                            TextButton(
                              onPressed: () =>
                                  _toggle(context, manager, manifest.id, true),
                              child: const Text('重试'),
                            ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String _state(PluginState state) => switch (state) {
  PluginState.disabled => '已停用',
  PluginState.starting => '正在启用',
  PluginState.enabled => '已启用',
  PluginState.stopping => '正在停用',
  PluginState.failed => '操作失败',
};
String _capability(String capability) => switch (capability) {
  'calories.library' => '个人饮料库',
  'calories.records' => '饮用记录',
  'motion.projects' => '本地分析项目',
  'training.set.read' => '读取训练组',
  'media.pick' => '选择媒体',
  'camera.capture' => '拍摄',
  'network.foodSearch' => '公共饮料搜索',
  _ => capability,
};
Future<void> _toggle(
  BuildContext context,
  PluginManager manager,
  String id,
  bool enabled,
) async {
  try {
    await manager.setEnabled(id, enabled);
  } on PluginException catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('操作未完成，请重试')));
    }
  }
}

class DisabledPluginPage extends StatelessWidget {
  final String pluginId;
  final String? destination;
  const DisabledPluginPage({
    super.key,
    required this.pluginId,
    this.destination,
  });
  @override
  Widget build(BuildContext context) {
    final manager = context.watch<PluginManager>();
    final manifest = manager.manifests
        .where((m) => m.id == pluginId)
        .firstOrNull;
    final supported =
        manifest != null && manifest.platforms.contains(manager.platform);
    return Scaffold(
      appBar: AppBar(
        title: Text(manifest?.name ?? '功能未启用'),
        leading: BackButton(onPressed: () => context.go('/')),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(supported ? '此功能尚未启用。启用后可继续，已有数据会保留。' : '当前平台不支持此插件。已有数据会保留。'),
            if (manager.errorOf(pluginId) != null)
              Text(manager.errorOf(pluginId)!.message),
            const SizedBox(height: 16),
            if (supported)
              FilledButton(
                onPressed:
                    {
                      PluginState.starting,
                      PluginState.stopping,
                    }.contains(manager.stateOf(pluginId))
                    ? null
                    : () async {
                        await _toggle(context, manager, pluginId, true);
                        if (context.mounted && manager.isEnabled(pluginId)) {
                          context.go(destination ?? '/');
                        }
                      },
                child: const Text('启用并继续'),
              ),
            TextButton(
              onPressed: () => context.go('/'),
              child: const Text('返回训练'),
            ),
          ],
        ),
      ),
    );
  }
}
