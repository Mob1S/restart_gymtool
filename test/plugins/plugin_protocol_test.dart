import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/plugins/api/plugin_protocol.dart';

void main() {
  test('请求和事件可 JSON 编码往返', () {
    final request = PluginRequest(
      requestId: 'request-1',
      method: 'storage.private.write',
      arguments: {
        'items': [
          null,
          true,
          1,
          2.5,
          '记录',
          {'key': 'a'},
        ],
      },
    );
    final decoded = PluginRequest.fromJson(
      copyPluginJsonMap(jsonDecode(jsonEncode(request.toJson()))),
    );
    expect(decoded.toJson(), request.toJson());
    final event = PluginEvent(
      requestId: 'request-1',
      generation: 2,
      type: 'completed',
      payload: {'id': 'a'},
    );
    expect(
      PluginEvent.fromJson(
        copyPluginJsonMap(jsonDecode(jsonEncode(event.toJson()))),
      ).toJson(),
      event.toJson(),
    );
    for (final code in PluginErrorCode.values) {
      final error = PluginException(code, '错误', pluginId: 'community.test');
      expect(
        PluginException.fromJson(
          copyPluginJsonMap(jsonDecode(jsonEncode(error.toJson()))),
        ).code,
        code,
      );
    }
  });

  test('协议拒绝运行对象、非有限数和过深数据', () {
    for (final value in [
      Object(),
      double.nan,
      double.infinity,
      {1: 'value'},
    ]) {
      expect(() => copyPluginJson(value), throwsA(isA<PluginException>()));
    }
    Object? nested = 0;
    for (var i = 0; i < 34; i++) {
      nested = [nested];
    }
    expect(() => copyPluginJson(nested), throwsA(isA<PluginException>()));
  });

  test('已发布的消息不受原始列表和对象修改影响', () {
    final items = <Object?>[
      {'value': 1},
    ];
    final request = PluginRequest(
      requestId: '1',
      method: 'test',
      arguments: {'items': items},
    );
    items.clear();
    expect(request.arguments['items'], [
      {'value': 1},
    ]);
    expect(
      () => (request.arguments['items'] as List).clear(),
      throwsUnsupportedError,
    );
  });

  test('拒绝不支持的协议和无效请求', () {
    expect(
      () => PluginRequest(requestId: '1', method: 'x', protocolVersion: 2),
      throwsA(
        isA<PluginException>().having(
          (e) => e.code,
          'code',
          PluginErrorCode.unsupportedApi,
        ),
      ),
    );
    expect(
      () => PluginRequest.fromJson({'requestId': 1}),
      throwsA(isA<PluginException>()),
    );
    expect(
      () => PluginEvent.fromJson({'generation': -1}),
      throwsA(isA<PluginException>()),
    );
  });
}
