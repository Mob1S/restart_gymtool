import 'dart:async';
import 'dart:convert';
import 'dart:io';

Future<String> beverageHttpGet(Uri uri) async {
  final client = HttpClient()
    ..userAgent =
        'GymTracker/1.0 (local beverage tracker; Open Food Facts read-only client)';
  try {
    return await (() async {
      final request = await client.getUrl(uri);
      final response = await request.close();
      if (response.statusCode != 200) throw const HttpException('公共服务暂时不可用');
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
        if (bytes.length > 2 * 1024 * 1024) throw const HttpException('公共响应过大');
      }
      return utf8.decode(bytes);
    })().timeout(const Duration(seconds: 15));
  } finally {
    client.close(force: true);
  }
}
