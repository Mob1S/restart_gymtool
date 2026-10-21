import 'package:flutter/services.dart';

class BeverageOcr {
  static const _channel = MethodChannel('gym_tracker/beverage_ocr');
  Future<({String text, Uint8List image})?> scan({required bool camera}) async {
    final result = await _channel.invokeMapMethod<String, dynamic>('scan', {
      'camera': camera,
    });
    if (result == null) return null;
    return (
      text: result['text'] as String,
      image: result['image'] as Uint8List,
    );
  }

  Future<void> cancel() async {
    try {
      await _channel.invokeMethod<void>('cancel');
    } on MissingPluginException {
      /* Unsupported desktop. */
    }
  }
}
