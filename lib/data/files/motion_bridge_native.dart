import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class MotionBridge {
  static bool get supported => defaultTargetPlatform == TargetPlatform.android;
  static const _channel = MethodChannel('gym_tracker/review');
  static final Stream<Map<String, dynamic>> _events =
      const EventChannel('gym_tracker/review_progress')
          .receiveBroadcastStream()
          .map((e) => Map<String, dynamic>.from(e as Map))
          .asBroadcastStream();
  Stream<Map<String, dynamic>> get events => _events;
  Future<Map<String, dynamic>> call(
    String method, [
    Map<String, dynamic> args = const {},
  ]) async {
    final value = await _channel.invokeMethod(method, args);
    if (value is String) return jsonDecode(value) as Map<String, dynamic>;
    return value == null ? {} : Map<String, dynamic>.from(value as Map);
  }
}
