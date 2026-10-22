import '../../data/repositories/plugin_document_repo.dart';
import '../api/plugin_protocol.dart';
import '../runtime/plugin_scope.dart';
import 'plugin_host.dart';

/// The repository remains host-owned; callers can never select a namespace.
class ScopedPluginStore {
  ScopedPluginStore({required this.repository, required this.scope});

  final PluginDocumentRepo repository;
  final PluginScope scope;

  Future<JsonMap> read(JsonMap arguments) async {
    scope.ensureActive();
    _validateIdentity(arguments);
    final key = _key(arguments['key']);
    final value = await repository.read(scope.pluginId, key);
    scope.ensureActive();
    return {'value': copyPluginJson(value)};
  }

  Future<JsonMap> write(JsonMap arguments) async {
    scope.ensureActive();
    _validateIdentity(arguments);
    final dataVersion = arguments['dataVersion'] ?? 1;
    if (dataVersion is! int || dataVersion < 1) {
      throw const PluginException(PluginErrorCode.invalidData, '插件数据版本无效');
    }
    final operations = arguments['operations'];
    if (operations is! List || operations.isEmpty) {
      throw const PluginException(PluginErrorCode.invalidData, '插件写入操作不能为空');
    }
    final safe = operations.map(copyPluginJsonMap).toList();
    for (final operation in safe) {
      _validateIdentity(operation);
      _key(operation['key']);
      if (operation['delete'] != true && !operation.containsKey('value')) {
        throw const PluginException(PluginErrorCode.invalidData, '插件写入缺少内容');
      }
    }
    try {
      await repository.transaction((tx) async {
        for (final operation in safe) {
          // Check the instance again inside the write transaction.
          scope.ensureActive();
          final key = operation['key'] as String;
          if (operation['delete'] == true) {
            await tx.delete(scope.pluginId, key);
          } else {
            await tx.write(
              scope.pluginId,
              key,
              operation['value'],
              dataVersion: dataVersion,
            );
          }
        }
        scope.ensureActive();
      });
    } on PluginException {
      rethrow;
    } catch (_) {
      throw const PluginException(PluginErrorCode.storageFailure, '插件数据保存失败');
    }
    return const {'saved': true};
  }

  String _key(Object? value) {
    if (value is! String || value.isEmpty || value.length > 1024) {
      throw const PluginException(PluginErrorCode.invalidData, '插件文档标识无效');
    }
    return value;
  }

  void _validateIdentity(JsonMap arguments) {
    if (arguments.containsKey('pluginId') &&
        arguments['pluginId'] != scope.pluginId) {
      throw const PluginException(
        PluginErrorCode.permissionDenied,
        '无法访问其他插件的数据',
      );
    }
  }

  Map<String, HostMethod> get methods => {
    'storage.private.read': HostMethod(
      capability: 'storage.private.read',
      handle: read,
    ),
    'storage.private.write': HostMethod(
      capability: 'storage.private.write',
      handle: write,
    ),
  };
}
