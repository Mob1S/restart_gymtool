import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/plugin_manifest.dart';
import '../api/plugin_runtime.dart';
import 'in_process_runner.dart';
import 'plugin_catalog.dart';
import 'plugin_scope.dart';

typedef PluginHostFactory = PluginHost Function(PluginManifest, PluginScope);

/// Serializes lifecycle transitions while keeping desired and actual state apart.
class PluginManager extends ChangeNotifier {
  PluginManager({
    required this.catalog,
    required this.platform,
    required this.loadPreferences,
    required this.savePreference,
    required this.hostFactory,
    this.validateData,
    this.controlTimeout = const Duration(seconds: 10),
  });

  final PluginCatalog catalog;
  final String platform;
  final Future<Map<String, bool>> Function() loadPreferences;
  final Future<void> Function(String pluginId, bool enabled) savePreference;
  final PluginHostFactory hostFactory;
  final Future<void> Function(PluginDefinition definition)? validateData;
  final Duration controlTimeout;
  final Map<String, PluginManifest> _manifests = {};
  final Map<String, PluginState> _states = {};
  final Map<String, bool> _desired = {};
  final Map<String, PluginException> _errors = {};
  final Map<String, InProcessRunner> _instances = {};
  final Set<String> _invalidIds = {};
  Future<void> _tail = Future.value();
  bool _initialized = false;
  bool _disposed = false;
  int _generation = 0;

  List<PluginManifest> get manifests => List.unmodifiable(_manifests.values);
  PluginManifest? manifestFor(String id) => _manifests[id];
  PluginState stateOf(String id) => _states[id] ?? PluginState.disabled;
  PluginException? errorOf(String id) => _errors[id];
  bool isEnabled(String id) => stateOf(id) == PluginState.enabled;
  bool isDesiredEnabled(String id) => _desired[id] ?? false;
  bool get initialized => _initialized;
  bool get isProcessing => _states.values.any(
    (state) => state == PluginState.starting || state == PluginState.stopping,
  );

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return result;
  }

  void _publish() {
    if (!_disposed) notifyListeners();
  }

  PluginException _error(Object error, String id) => error is PluginException
      ? error
      : PluginException(
          PluginErrorCode.internalError,
          '插件操作失败，请重试',
          pluginId: id,
        );

  Future<void> initialize() => _enqueue(() async {
    if (_initialized) return;
    final discovered = await catalog.discover();
    for (final manifest in discovered) {
      if (_manifests.containsKey(manifest.id)) {
        _invalidIds.add(manifest.id);
        _states[manifest.id] = PluginState.failed;
        _errors[manifest.id] = PluginException(
          PluginErrorCode.invalidData,
          '插件标识重复',
          pluginId: manifest.id,
        );
      } else {
        _manifests[manifest.id] = manifest;
        _states[manifest.id] = PluginState.disabled;
      }
    }
    try {
      _desired.addAll(await loadPreferences());
    } catch (_) {
      // Required host functionality still starts when optional state cannot load.
      for (final manifest in manifests) {
        _errors[manifest.id] = PluginException(
          PluginErrorCode.storageFailure,
          '无法读取插件启用设置',
          pluginId: manifest.id,
        );
      }
    }
    _initialized = true;
    final ordered = [...manifests]
      ..sort((a, b) => (b.requiredByHost ? 1 : 0) - (a.requiredByHost ? 1 : 0));
    for (final manifest in ordered) {
      if (manifest.requiredByHost) _desired[manifest.id] = true;
      if (!isDesiredEnabled(manifest.id) || _invalidIds.contains(manifest.id)) {
        continue;
      }
      try {
        await _start(manifest.id, persist: false, visiting: {});
      } catch (_) {
        // Each plugin reports its own failure; other plugins continue starting.
      }
    }
    _publish();
  });

  Future<void> setEnabled(String pluginId, bool enabled) => _enqueue(() async {
    if (!_initialized) {
      throw const PluginException(PluginErrorCode.busy, '插件管理器尚未初始化');
    }
    final manifest = _manifests[pluginId];
    if (manifest == null) {
      throw PluginException(
        PluginErrorCode.invalidData,
        '找不到插件',
        pluginId: pluginId,
      );
    }
    if (!enabled && manifest.requiredByHost) {
      throw PluginException(
        PluginErrorCode.permissionDenied,
        '基础训练是必需功能，无法停用',
        pluginId: pluginId,
      );
    }
    if (enabled) {
      await _start(pluginId, persist: true, visiting: {});
    } else {
      await _disable(pluginId, persist: true);
    }
  });

  void _checkCompatible(PluginManifest manifest) {
    if (_invalidIds.contains(manifest.id)) throw _errors[manifest.id]!;
    if (!manifest.supportsApi(pluginProtocolVersion)) {
      throw PluginException(
        PluginErrorCode.unsupportedApi,
        '插件接口版本与应用不兼容',
        pluginId: manifest.id,
      );
    }
    if (!manifest.platforms.contains(platform)) {
      throw PluginException(
        PluginErrorCode.unsupportedPlatform,
        '当前平台不支持此插件',
        pluginId: manifest.id,
      );
    }
  }

  Future<void> _start(
    String id, {
    required bool persist,
    required Set<String> visiting,
  }) async {
    if (isEnabled(id)) {
      if (persist && !isDesiredEnabled(id)) await _save(id, true);
      return;
    }
    final manifest = _manifests[id]!;
    InProcessRunner? runner;
    PluginScope? pendingScope;
    try {
      _checkCompatible(manifest);
      if (!visiting.add(id)) {
        throw PluginException(
          PluginErrorCode.missingDependency,
          '插件依赖存在循环',
          pluginId: id,
        );
      }
      for (final dependency in manifest.dependencies) {
        final target = _manifests[dependency.id];
        if (target == null ||
            !target.supportsApi(pluginProtocolVersion) ||
            pluginProtocolVersion < dependency.apiMin ||
            pluginProtocolVersion > dependency.apiMax ||
            (!target.requiredByHost && !isDesiredEnabled(dependency.id))) {
          throw PluginException(
            PluginErrorCode.missingDependency,
            '请先启用所需的依赖插件',
            pluginId: id,
          );
        }
        await _start(dependency.id, persist: false, visiting: visiting);
      }
      visiting.remove(id);
      // A failed stop must be retried before constructing another instance.
      final previous = _instances[id];
      if (previous != null) {
        await previous.close();
        _instances.remove(id);
      }
      _states[id] = PluginState.starting;
      _errors.remove(id);
      _publish();
      final definition = catalog.definitionFor(id);
      if (definition == null) {
        throw PluginException(
          PluginErrorCode.invalidData,
          '插件实现不存在',
          pluginId: id,
        );
      }
      await validateData?.call(definition);
      final scope = PluginScope(id, generation: ++_generation);
      pendingScope = scope;
      final host = hostFactory(manifest, scope);
      if (!host.grantedCapabilities.containsAll(
        manifest.requiredCapabilities,
      )) {
        await scope.close();
        throw PluginException(
          PluginErrorCode.permissionDenied,
          '插件缺少所需能力授权',
          pluginId: id,
        );
      }
      runner = InProcessRunner(
        runtime: definition.createRuntime(),
        scope: scope,
        controlTimeout: controlTimeout,
      );
      _instances[id] = runner;
      await runner.control(() => runner!.runtime.start(host));
      scope.ensureActive();
      if (persist) await _save(id, true);
      _states[id] = PluginState.enabled;
      _errors.remove(id);
      _publish();
    } catch (error) {
      if (runner != null) {
        try {
          await runner.close();
          _instances.remove(id);
        } catch (_) {
          // Retain the runner so retry can confirm platform cleanup first.
        }
      } else {
        try {
          await pendingScope?.close();
        } catch (_) {}
      }
      final failure = _error(error, id);
      _states[id] = PluginState.failed;
      _errors[id] = failure;
      _publish();
      throw failure;
    }
  }

  Future<void> _save(String id, bool enabled) async {
    try {
      await savePreference(id, enabled);
      _desired[id] = enabled;
    } catch (_) {
      throw PluginException(
        PluginErrorCode.storageFailure,
        '插件设置保存失败，请重试',
        pluginId: id,
      );
    }
  }

  Future<void> _checkReady(String id) async {
    final runner = _instances[id];
    if (runner == null) return;
    runner.scope.suspendRequests();
    try {
      final decision = await runner.control(runner.runtime.prepareStop);
      if (decision != StopDecision.ready) {
        throw PluginException(
          decision == StopDecision.unsavedChanges
              ? PluginErrorCode.unsavedChanges
              : PluginErrorCode.busy,
          decision == StopDecision.unsavedChanges
              ? '请返回功能页面保存或放弃未保存内容后重试'
              : '功能正在处理任务，请完成任务后重试',
          pluginId: id,
        );
      }
    } catch (error) {
      final failure = _error(error, id);
      if (failure.code == PluginErrorCode.timeout) {
        try {
          await runner.close();
        } catch (_) {}
        _states[id] = PluginState.failed;
      } else {
        runner.scope.resumeRequests();
      }
      _errors[id] = failure;
      _publish();
      throw failure;
    }
  }

  Future<void> _disable(
    String id, {
    required bool persist,
    bool force = false,
  }) async {
    if (!force) {
      final dependent = manifests.where(
        (m) => isEnabled(m.id) && m.dependencies.any((d) => d.id == id),
      );
      if (dependent.isNotEmpty) {
        throw PluginException(
          PluginErrorCode.busy,
          '请先停用依赖此插件的功能',
          pluginId: id,
        );
      }
    }
    final runner = _instances[id];
    if (runner == null) {
      _states[id] = PluginState.disabled;
      try {
        if (persist) await _save(id, false);
      } catch (error) {
        _errors[id] = _error(error, id);
        _publish();
        rethrow;
      }
      _errors.remove(id);
      _publish();
      return;
    }
    if (!force) await _checkReady(id);
    _states[id] = PluginState.stopping;
    _errors.remove(id);
    _publish();
    try {
      await runner.close();
    } catch (error) {
      final failure = _error(error, id);
      _states[id] = PluginState.failed;
      _errors[id] = failure;
      _publish();
      throw failure;
    }
    _instances.remove(id);
    _states[id] = PluginState.disabled;
    try {
      if (persist) await _save(id, false);
      _errors.remove(id);
    } catch (error) {
      // Resources really are closed, even though the previous preference remains.
      _errors[id] = _error(error, id);
      _publish();
      rethrow;
    }
    _publish();
  }

  Future<JsonMap> invoke(
    String pluginId,
    String method,
    JsonMap arguments,
  ) async {
    final runner = _instances[pluginId];
    if (!isEnabled(pluginId) || runner == null) {
      throw PluginException(
        PluginErrorCode.pluginDisabled,
        '插件尚未启用',
        pluginId: pluginId,
      );
    }
    try {
      return await runner.invoke(method, arguments);
    } on PluginException catch (failure) {
      if (failure.code == PluginErrorCode.timeout) {
        await _enqueue(() async {
          if (!identical(_instances[pluginId], runner)) return;
          try {
            await runner.close();
            _instances.remove(pluginId);
          } catch (_) {}
          _states[pluginId] = PluginState.failed;
          _errors[pluginId] = failure;
          _publish();
        });
      }
      rethrow;
    }
  }

  Future<void> prepareForRestore() => _enqueue(() async {
    final ids = _instances.keys.toList();
    try {
      for (final id in ids) {
        await _checkReady(id);
      }
    } finally {
      for (final id in ids) {
        if (isEnabled(id)) _instances[id]?.scope.resumeRequests();
      }
    }
  });

  /// Keeps installation preferences intact and excludes lifecycle races during restore.
  Future<T> runWithPluginsPaused<T>(Future<T> Function() action) =>
      _enqueue(() async {
        final ids = _instances.keys.where(isEnabled).toList();
        try {
          for (final id in ids) {
            await _checkReady(id);
          }
        } catch (_) {
          for (final id in ids) {
            if (isEnabled(id)) _instances[id]?.scope.resumeRequests();
          }
          rethrow;
        }
        final stopped = <String>[];
        try {
          for (final id in ids.reversed) {
            // Required host UI and controllers remain mounted during restore.
            // Their capability scope is already suspended by the safety check.
            if (_manifests[id]!.requiredByHost) continue;
            await _disable(id, persist: false, force: true);
            stopped.add(id);
          }
          return await action();
        } finally {
          for (final id in stopped.reversed) {
            try {
              await _start(id, persist: false, visiting: {});
            } catch (_) {}
          }
          for (final id in ids) {
            if (isEnabled(id)) _instances[id]?.scope.resumeRequests();
          }
        }
      });

  Future<void> shutdown() => _enqueue(() async {
    Object? firstError;
    for (final id in _instances.keys.toList().reversed) {
      try {
        await _disable(id, persist: false, force: true);
      } catch (error) {
        firstError ??= error;
      }
    }
    if (firstError != null) throw firstError;
  });

  @override
  void dispose() {
    _disposed = true;
    // Owners should await shutdown. Revocation also protects late callbacks.
    for (final runner in _instances.values) {
      runner.scope.revoke();
    }
    super.dispose();
  }
}
