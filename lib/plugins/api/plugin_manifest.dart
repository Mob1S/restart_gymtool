import 'plugin_protocol.dart';

class PluginDependency {
  const PluginDependency({required this.id, this.apiMin = 1, this.apiMax = 1});

  final String id;
  final int apiMin;
  final int apiMax;

  JsonMap toJson() => {'id': id, 'apiMin': apiMin, 'apiMax': apiMax};

  factory PluginDependency.fromJson(JsonMap json) {
    if (json['id'] is! String ||
        json['apiMin'] is! int ||
        json['apiMax'] is! int) {
      throw const PluginException(PluginErrorCode.invalidData, '插件依赖格式无效');
    }
    return PluginDependency(
      id: json['id'] as String,
      apiMin: json['apiMin'] as int,
      apiMax: json['apiMax'] as int,
    );
  }
}

class PluginManifest {
  PluginManifest({
    required this.id,
    required this.name,
    required this.description,
    required this.version,
    this.apiMin = 1,
    this.apiMax = 1,
    required Set<String> platforms,
    Set<String> requiredCapabilities = const {},
    Set<String> optionalCapabilities = const {},
    List<PluginDependency> dependencies = const [],
    this.requiredByHost = false,
  }) : platforms = Set.unmodifiable(platforms),
       requiredCapabilities = Set.unmodifiable(requiredCapabilities),
       optionalCapabilities = Set.unmodifiable(optionalCapabilities),
       dependencies = List.unmodifiable(dependencies) {
    if (!RegExp(r'^[a-z][a-z0-9]*(?:\.[a-z][a-z0-9_-]*)+$').hasMatch(id) ||
        name.trim().isEmpty ||
        version.trim().isEmpty ||
        apiMin < 1 ||
        apiMax < apiMin ||
        platforms.isEmpty ||
        dependencies.any(
          (d) => d.id == id || d.apiMin < 1 || d.apiMax < d.apiMin,
        )) {
      throw const PluginException(PluginErrorCode.invalidData, '插件清单格式无效');
    }
  }

  final String id;
  final String name;
  final String description;
  final String version;
  final int apiMin;
  final int apiMax;
  final Set<String> platforms;
  final Set<String> requiredCapabilities;
  final Set<String> optionalCapabilities;
  final List<PluginDependency> dependencies;
  final bool requiredByHost;

  bool supportsApi(int version) => version >= apiMin && version <= apiMax;

  JsonMap toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'version': version,
    'apiMin': apiMin,
    'apiMax': apiMax,
    'platforms': platforms.toList(),
    'requiredCapabilities': requiredCapabilities.toList(),
    'optionalCapabilities': optionalCapabilities.toList(),
    'dependencies': dependencies.map((d) => d.toJson()).toList(),
    'requiredByHost': requiredByHost,
  };

  factory PluginManifest.fromJson(JsonMap json) {
    Set<String> strings(String key) {
      final value = json[key];
      if (value is! List || value.any((e) => e is! String)) {
        throw const PluginException(PluginErrorCode.invalidData, '插件清单列表无效');
      }
      return value.cast<String>().toSet();
    }

    if ([
          'id',
          'name',
          'description',
          'version',
        ].any((k) => json[k] is! String) ||
        json['apiMin'] is! int ||
        json['apiMax'] is! int ||
        json['requiredByHost'] is! bool ||
        json['dependencies'] is! List) {
      throw const PluginException(PluginErrorCode.invalidData, '插件清单格式无效');
    }
    return PluginManifest(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String,
      version: json['version'] as String,
      apiMin: json['apiMin'] as int,
      apiMax: json['apiMax'] as int,
      platforms: strings('platforms'),
      requiredCapabilities: strings('requiredCapabilities'),
      optionalCapabilities: strings('optionalCapabilities'),
      dependencies: (json['dependencies'] as List)
          .map((d) => PluginDependency.fromJson(copyPluginJsonMap(d)))
          .toList(),
      requiredByHost: json['requiredByHost'] as bool,
    );
  }
}
