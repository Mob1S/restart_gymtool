import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

@JS('gymBeverage.scan')
external JSPromise<JSString> _scan(JSBoolean camera);
@JS('gymBeverage.cancel')
external void _cancel();

class BeverageOcr {
  Future<({String text, Uint8List image})?> scan({required bool camera}) async {
    final result = jsonDecode((await _scan(camera.toJS).toDart).toDart);
    if (result == null) return null;
    return (
      text: result['text'] as String,
      image: base64Decode(result['image'] as String),
    );
  }

  Future<void> cancel() async => _cancel();
}
