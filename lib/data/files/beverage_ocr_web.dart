import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'plugin_runtime_web.dart';

@JS('gymBeverage.scan')
external JSPromise<JSString> _scan(JSBoolean camera);

class BeverageOcr {
  static int _generation = 0;
  static int get generation => _generation;
  Future<void> activate() async {
    await activatePluginRuntime('beverage');
    _generation++;
  }

  Future<void> deactivate() => deactivatePluginRuntime('beverage');

  Future<({String text, Uint8List image})?> scan({required bool camera}) async {
    await loadPluginRuntime('beverage');
    final result = jsonDecode((await _scan(camera.toJS).toDart).toDart);
    if (result == null) return null;
    return (
      text: result['text'] as String,
      image: base64Decode(result['image'] as String),
    );
  }

  Future<void> cancel() async {
    await cancelPluginRuntime('beverage');
  }
}
