import 'dart:async';
import 'dart:convert';
import 'dart:io';

final _activeRequests = <HttpClient, Completer<void>>{};
final _sessions = <HttpClient, String>{};
bool _enabled = true;

void activateBeverageHttp() => _enabled = true;

Future<void> deactivateBeverageHttp() async {
  _enabled = false;
  final active = Map.of(_activeRequests);
  for (final client in active.keys) {
    client.close(force: true);
  }
  await Future.wait(active.values.map((finished) => finished.future));
}

Future<void> cancelBeverageHttpSession(String sessionId) async {
  final active = {
    for (final entry in _activeRequests.entries)
      if (_sessions[entry.key] == sessionId) entry.key: entry.value,
  };
  for (final client in active.keys) {
    client.close(force: true);
  }
  await Future.wait(active.values.map((finished) => finished.future));
}

Future<String> beverageHttpGet(Uri uri, {String sessionId = ''}) async {
  if (!_enabled) throw StateError('饮料热量已停用');
  final client = HttpClient()
    ..userAgent =
        'GymTracker/1.0 (local beverage tracker; Open Food Facts read-only client)';
  final finished = Completer<void>();
  _activeRequests[client] = finished;
  _sessions[client] = sessionId;
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
    _activeRequests.remove(client);
    _sessions.remove(client);
    finished.complete();
  }
}
