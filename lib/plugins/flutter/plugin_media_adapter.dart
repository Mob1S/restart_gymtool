import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../data/files/beverage_ocr.dart';
import '../../data/files/motion_bridge.dart';
import '../api/plugin_runtime.dart';
import '../host/plugin_host.dart';
import 'plugin_ui_adapter.dart';

/// Textures and frame bytes remain in the platform adapter, outside JSON control.
class ScopedMotionBridge extends MotionBridge {
  final PluginHost host;
  final int _generation;
  ScopedMotionBridge(this.host) : _generation = MotionBridge.generation;

  bool get _ownsGeneration => _generation == MotionBridge.generation;
  bool get _acceptsEvents =>
      _ownsGeneration &&
      (host is! BoundPluginHost ||
          (host as BoundPluginHost).scope.acceptsRequests);

  void _authorize(String capability) {
    if (host is BoundPluginHost) (host as BoundPluginHost).scope.ensureActive();
    if (!_ownsGeneration) {
      throw const PluginException(PluginErrorCode.pluginDisabled, '媒体会话已失效');
    }
    if (!host.grantedCapabilities.contains(capability)) {
      throw const PluginException(
        PluginErrorCode.permissionDenied,
        '没有使用媒体能力的权限',
      );
    }
  }

  @override
  Stream<Map<String, dynamic>> get events {
    _authorize('media.pick');
    return Stream.multi((listener) {
      try {
        _authorize('media.pick');
      } catch (error, stack) {
        listener.addError(error, stack);
        listener.close();
        return;
      }
      final subscription = super.events.listen(
        (event) {
          if (_acceptsEvents) listener.add(event);
        },
        onError: (Object error, StackTrace stack) {
          if (_acceptsEvents) listener.addError(error, stack);
        },
        onDone: listener.close,
      );
      listener.onCancel = subscription.cancel;
      if (host is BoundPluginHost) {
        (host as BoundPluginHost).scope.addCleanup(subscription.cancel);
      }
    }, isBroadcast: true);
  }

  @override
  Future<void> activate() async => throw const PluginException(
    PluginErrorCode.permissionDenied,
    '插件生命周期由宿主管理',
  );
  @override
  Future<void> deactivate() async => throw const PluginException(
    PluginErrorCode.permissionDenied,
    '插件生命周期由宿主管理',
  );
  @override
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic> args = const {},
  ]) async {
    const cleanup = {'close', 'cancel', 'release'};
    if (method == 'activate' || method == 'deactivate') {
      throw const PluginException(
        PluginErrorCode.permissionDenied,
        '插件生命周期由宿主管理',
      );
    }
    // Shutdown can revoke the host before its registered page cleanup runs.
    // A later activation owns another generation and must remain untouched.
    if (cleanup.contains(method) && !_ownsGeneration) return {};
    if (cleanup.contains(method) &&
        !host.grantedCapabilities.contains('media.pick') &&
        !host.grantedCapabilities.contains('camera.capture')) {
      throw const PluginException(
        PluginErrorCode.permissionDenied,
        '没有使用媒体能力的权限',
      );
    }
    if (!cleanup.contains(method)) {
      _authorize(
        {
              'camera',
              'freezeCamera',
              'startCamera',
              'stopCamera',
              'mark',
            }.contains(method)
            ? 'camera.capture'
            : 'media.pick',
      );
    }
    final result = await super.call(method, args);
    if (!cleanup.contains(method)) {
      _authorize(
        {
              'camera',
              'freezeCamera',
              'startCamera',
              'stopCamera',
              'mark',
            }.contains(method)
            ? 'camera.capture'
            : 'media.pick',
      );
    }
    return result;
  }
}

class ScopedBeverageOcr extends BeverageOcr {
  final PluginHost host;
  final int _generation;
  ScopedBeverageOcr(this.host) : _generation = BeverageOcr.generation;

  @override
  Future<void> activate() async => throw const PluginException(
    PluginErrorCode.permissionDenied,
    '插件生命周期由宿主管理',
  );
  @override
  Future<void> deactivate() async => throw const PluginException(
    PluginErrorCode.permissionDenied,
    '插件生命周期由宿主管理',
  );

  @override
  Future<void> cancel() async {
    if (_generation != BeverageOcr.generation) return;
    if (!host.grantedCapabilities.contains('media.pick') &&
        !host.grantedCapabilities.contains('camera.capture')) {
      throw const PluginException(
        PluginErrorCode.permissionDenied,
        '没有使用标签识别的权限',
      );
    }
    await super.cancel();
  }

  @override
  Future<({String text, Uint8List image})?> scan({required bool camera}) async {
    final capability = camera ? 'camera.capture' : 'media.pick';
    void check() {
      if (_generation != BeverageOcr.generation) {
        throw const PluginException(
          PluginErrorCode.pluginDisabled,
          '标签识别会话已失效',
        );
      }
      if (host is BoundPluginHost) {
        (host as BoundPluginHost).scope.ensureActive();
      }
      if (!host.grantedCapabilities.contains(capability)) {
        throw const PluginException(
          PluginErrorCode.permissionDenied,
          '没有使用标签识别的权限',
        );
      }
    }

    check();
    final result = await super.scan(camera: camera);
    check();
    return result;
  }
}

MotionBridge motionBridge(BuildContext context) {
  final access = context.read<PluginFeatureAccess?>();
  return access == null
      ? MotionBridge()
      : ScopedMotionBridge(access.motion.host);
}

BeverageOcr beverageOcr(BuildContext context) {
  final access = context.read<PluginFeatureAccess?>();
  return access == null
      ? BeverageOcr()
      : ScopedBeverageOcr(access.calories.host);
}
