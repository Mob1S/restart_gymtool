import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class VideoReviewBridge {
  static bool get supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  static const channel = MethodChannel('gym_tracker/review');
  static const events = EventChannel('gym_tracker/review_progress');
  Future<Map<String, dynamic>> call(
    String method,
    Map<String, dynamic> args,
  ) async => Map<String, dynamic>.from(
    await channel.invokeMethod<Map>(method, args) ?? {},
  );
  Future<void> cancel() => channel.invokeMethod('cancel');
  Future<void> release(String folder) =>
      channel.invokeMethod('release', {'folder': folder});
  Future<void> collect(List<String> keep, {Map<String, String>? results}) =>
      channel.invokeMethod('collect', {'keep': keep, 'results': results});
  Future<Map<String, dynamic>> load(String folder, String result) async =>
      jsonDecode(
        await channel.invokeMethod<String>('load', {
              'folder': folder,
              'result': result,
            }) ??
            '{}',
      ) as Map<String, dynamic>;
}
