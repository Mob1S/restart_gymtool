import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

@JS('gymMotion.call')
external JSPromise<JSString> _call(JSString method, JSString args);
@JS('gymMotion.subscribe')
external JSFunction _subscribe(JSFunction listener);

class MotionBridge {
  static bool get supported => true;
  late final Stream<Map<String, dynamic>> events = _events();
  Stream<Map<String, dynamic>> _events() {
    late StreamController<Map<String, dynamic>> controller;
    JSFunction? unsubscribe;
    controller = StreamController.broadcast(
      onListen: () {
        unsubscribe = _subscribe(
          ((JSString value) {
            controller.add(jsonDecode(value.toDart) as Map<String, dynamic>);
          }).toJS,
        );
      },
      onCancel: () {
        unsubscribe?.callAsFunction();
        unsubscribe = null;
      },
    );
    return controller.stream;
  }

  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic> args = const {},
  ]) async => jsonDecode(
    (await _call(method.toJS, jsonEncode(args).toJS).toDart).toDart,
  ) as Map<String, dynamic>;
}
