import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'plugin_runtime_web.dart';

@JS('gymMotion.call')
external JSPromise<JSString> _call(JSString method, JSString args);
@JS('gymMotion.subscribe')
external JSFunction _subscribe(JSFunction listener);

class MotionBridge {
  static int _generation = 0;
  static int get generation => _generation;
  static bool get supported => true;
  Future<void> activate() async {
    await activatePluginRuntime('motion');
    _generation++;
  }

  Future<void> deactivate() => deactivatePluginRuntime('motion');
  late final Stream<Map<String, dynamic>> events = _events();
  Stream<Map<String, dynamic>> _events() {
    late StreamController<Map<String, dynamic>> controller;
    JSFunction? unsubscribe;
    var generation = 0;
    controller = StreamController.broadcast(
      onListen: () async {
        final current = ++generation;
        try {
          await loadPluginRuntime('motion');
          if (current != generation || !controller.hasListener) return;
          unsubscribe = _subscribe(
            ((JSString value) {
              controller.add(jsonDecode(value.toDart) as Map<String, dynamic>);
            }).toJS,
          );
        } catch (error, stack) {
          if (current == generation && controller.hasListener) {
            controller.addError(error, stack);
          }
        }
      },
      onCancel: () {
        generation++;
        unsubscribe?.callAsFunction();
        unsubscribe = null;
      },
    );
    return controller.stream;
  }

  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic> args = const {},
  ]) async {
    await loadPluginRuntime('motion');
    return jsonDecode(
      (await _call(method.toJS, jsonEncode(args).toJS).toDart).toDart,
    ) as Map<String, dynamic>;
  }
}
