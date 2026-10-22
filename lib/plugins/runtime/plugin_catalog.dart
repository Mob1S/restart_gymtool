import '../api/plugin_manifest.dart';
import '../api/plugin_runtime.dart';

class PluginDefinition {
  PluginDefinition({
    required this.manifest,
    required this.createRuntime,
    Set<int> supportedDataVersions = const {1},
  }) : supportedDataVersions = Set.unmodifiable(supportedDataVersions) {
    if (supportedDataVersions.isEmpty ||
        supportedDataVersions.any((v) => v < 1)) {
      throw const PluginException(PluginErrorCode.invalidData, '插件支持的数据版本无效');
    }
  }

  final PluginManifest manifest;
  final PluginRuntime Function() createRuntime;
  final Set<int> supportedDataVersions;
}

abstract interface class PluginCatalog {
  Future<List<PluginManifest>> discover();
  PluginDefinition? definitionFor(String pluginId);
}

/// Discovery is deliberately separate from runtime construction.
class StaticPluginCatalog implements PluginCatalog {
  StaticPluginCatalog(List<PluginDefinition> definitions)
    : definitions = List.unmodifiable(definitions);

  final List<PluginDefinition> definitions;

  @override
  Future<List<PluginManifest>> discover() async =>
      definitions.map((d) => d.manifest).toList(growable: false);

  @override
  PluginDefinition? definitionFor(String pluginId) {
    final matches = definitions.where((d) => d.manifest.id == pluginId);
    if (matches.length > 1) {
      throw PluginException(
        PluginErrorCode.invalidData,
        '插件标识重复',
        pluginId: pluginId,
      );
    }
    return matches.isEmpty ? null : matches.single;
  }
}
