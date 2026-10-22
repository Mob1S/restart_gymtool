import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:gym_tracker/data/db/ffi_executor.dart';
import 'package:gym_tracker/data/db/sql_executor.dart';
import 'package:gym_tracker/data/repositories/plugin_document_repo.dart';
import 'package:gym_tracker/plugins/api/plugin_protocol.dart';
import 'package:gym_tracker/plugins/host/plugin_host.dart';
import 'package:gym_tracker/plugins/host/scoped_plugin_store.dart';
import 'package:gym_tracker/plugins/runtime/plugin_scope.dart';

class _RevokingExecutor implements SqlExecutor {
  _RevokingExecutor(this.delegate, this.scope);
  final SqlExecutor delegate;
  final PluginScope scope;
  @override
  Future<T> transaction<T>(Future<T> Function(SqlExecutor) action) =>
      delegate.transaction((tx) => action(_RevokingExecutor(tx, scope)));
  @override
  Future<List<T>> all<T>(String sql, [List<Object?>? params]) =>
      delegate.all<T>(sql, params);
  @override
  Future<T?> first<T>(String sql, [List<Object?>? params]) =>
      delegate.first<T>(sql, params);
  @override
  Future<void> run(String sql, [List<Object?>? params]) async {
    await delegate.run(sql, params);
    if (sql.startsWith('INSERT INTO plugin_document')) scope.revoke();
  }
}

void main() {
  test('实际控制请求使用唯一协议标识且业务参数保持原样', () async {
    final scope = PluginScope('community.one', generation: 7);
    final requests = <PluginRequest>[];
    final host = BoundPluginHost(
      scope: scope,
      grantedCapabilities: {'test'},
      onRequest: requests.add,
      methods: {
        'test': HostMethod(
          capability: 'test',
          handle: (args) async {
            expect(args, {'setId': 'stable-id'});
            return args;
          },
        ),
      },
    );
    await host.request('test', {'setId': 'stable-id'});
    await host.request('test', {'setId': 'stable-id'});
    expect(requests.map((r) => r.requestId).toSet(), hasLength(2));
    expect(
      requests.every((r) => r.protocolVersion == 1 && r.generation == 7),
      isTrue,
    );
    expect(PluginRequest.fromJson(requests.first.toJson()).arguments, {
      'setId': 'stable-id',
    });
    await scope.close();
  });

  test('控制请求超时后提交检查拒绝晚写入，不影响其他新请求', () async {
    final scope = PluginScope('community.one');
    final proceed = Completer<void>();
    final completed = Completer<void>();
    var writes = 0;
    final host = BoundPluginHost(
      scope: scope,
      grantedCapabilities: {'test'},
      controlTimeout: const Duration(milliseconds: 5),
      methods: {
        'slow': HostMethod(
          capability: 'test',
          handle: (_) async {
            await proceed.future;
            try {
              scope.ensureActive();
              writes++;
              return {};
            } finally {
              completed.complete();
            }
          },
        ),
        'fast': HostMethod(
          capability: 'test',
          handle: (_) async => {'ok': true},
        ),
      },
    );
    await expectLater(
      host.request('slow', {}),
      throwsA(
        isA<PluginException>().having(
          (e) => e.code,
          'code',
          PluginErrorCode.timeout,
        ),
      ),
    );
    proceed.complete();
    await completed.future;
    expect(writes, 0);
    expect(await host.request('fast', {}), {'ok': true});
    await scope.close();
  });

  test('私有存储相同key不串命名空间且批量写入完整提交', () async {
    final exec = await FfiExecutor.openMigrated();
    addTearDown(exec.close);
    final repo = PluginDocumentRepo(exec);
    final one = ScopedPluginStore(
      repository: repo,
      scope: PluginScope('community.one'),
    );
    final two = ScopedPluginStore(
      repository: repo,
      scope: PluginScope('community.two'),
    );
    await one.write({
      'operations': [
        {
          'key': 'preferences',
          'value': {'unit': 'kg'},
        },
        {'key': 'other', 'value': null},
      ],
    });
    await two.write({
      'operations': [
        {
          'key': 'preferences',
          'value': {'unit': 'lb'},
        },
      ],
    });
    expect(await one.read({'key': 'preferences'}), {
      'value': {'unit': 'kg'},
    });
    expect(await two.read({'key': 'preferences'}), {
      'value': {'unit': 'lb'},
    });
    await expectLater(
      one.read({'pluginId': 'community.two', 'key': 'preferences'}),
      throwsA(isA<PluginException>()),
    );
    expect(await repo.readAll('community.one'), {
      'preferences': {'unit': 'kg'},
      'other': null,
    });
  });

  test('事务过程中token撤销时所有私有文档写入均回滚', () async {
    final exec = await FfiExecutor.openMigrated();
    addTearDown(exec.close);
    final scope = PluginScope('community.one');
    final store = ScopedPluginStore(
      repository: PluginDocumentRepo(_RevokingExecutor(exec, scope)),
      scope: scope,
    );
    await expectLater(
      store.write({
        'operations': [
          {'key': 'first', 'value': 1},
          {'key': 'second', 'value': 2},
        ],
      }),
      throwsA(
        isA<PluginException>().having(
          (e) => e.code,
          'code',
          PluginErrorCode.pluginDisabled,
        ),
      ),
    );
    expect(await PluginDocumentRepo(exec).readAll('community.one'), isEmpty);
    expect(await PluginDocumentRepo(exec).dataVersion('community.one'), isNull);
  });

  test('拒绝未授权能力、未知方法和跨插件命名空间，不进入服务', () async {
    var calls = 0;
    final scope = PluginScope('community.one');
    final host = BoundPluginHost(
      scope: scope,
      grantedCapabilities: {},
      methods: {
        'camera.capture': HostMethod(
          capability: 'camera.capture',
          handle: (_) async {
            calls++;
            return {};
          },
        ),
        'storage.private.write': HostMethod(
          capability: 'storage.private.write',
          handle: (_) async {
            calls++;
            return {};
          },
        ),
      },
    );
    for (final method in [
      'camera.capture',
      'storage.private.write',
      'missing',
    ]) {
      await expectLater(
        host.request(method, {}),
        throwsA(isA<PluginException>()),
      );
    }
    expect(calls, 0);
    final granted = BoundPluginHost(
      scope: scope,
      grantedCapabilities: {'storage.private.write'},
      methods: {
        'storage.private.write': HostMethod(
          capability: 'storage.private.write',
          handle: (_) async {
            calls++;
            return {};
          },
        ),
      },
    );
    await expectLater(
      granted.request('storage.private.write', {'pluginId': 'community.two'}),
      throwsA(
        isA<PluginException>().having(
          (e) => e.code,
          'code',
          PluginErrorCode.permissionDenied,
        ),
      ),
    );
    expect(calls, 0);
    await scope.close();
  });

  test('token撤销拒绝新请求并丢弃在途结果', () async {
    final completer = Completer<JsonMap>();
    var calls = 0;
    final scope = PluginScope('community.one');
    final host = BoundPluginHost(
      scope: scope,
      grantedCapabilities: {'test'},
      methods: {
        'test': HostMethod(
          capability: 'test',
          handle: (_) {
            calls++;
            return completer.future;
          },
        ),
      },
    );
    final result = host.request('test', {});
    scope.revoke();
    completer.complete({'old': true});
    await expectLater(
      result,
      throwsA(
        isA<PluginException>().having(
          (e) => e.code,
          'code',
          PluginErrorCode.pluginDisabled,
        ),
      ),
    );
    await expectLater(
      host.request('test', {}),
      throwsA(isA<PluginException>()),
    );
    expect(calls, 1);
  });

  test('实例关闭后延迟监听以流错误拒绝且不订阅源', () async {
    final events = StreamController<JsonMap>.broadcast();
    addTearDown(events.close);
    final scope = PluginScope('community.one');
    final host = BoundPluginHost(
      scope: scope,
      grantedCapabilities: {'events'},
      topics: {
        'events': HostTopic(capability: 'events', events: events.stream),
      },
    );
    final delayed = host.subscribe('events');
    await scope.close();
    await expectLater(
      delayed,
      emitsInOrder([
        emitsError(
          isA<PluginException>().having(
            (error) => error.code,
            'code',
            PluginErrorCode.pluginDisabled,
          ),
        ),
        emitsDone,
      ]),
    );
    expect(events.hasListener, isFalse);
  });

  test('旧事件不进入订阅，关闭等待源订阅取消且清理幂等', () async {
    var cancellations = 0;
    final events = StreamController<JsonMap>.broadcast(
      onCancel: () {
        cancellations++;
      },
    );
    final scope = PluginScope('community.one');
    final host = BoundPluginHost(
      scope: scope,
      grantedCapabilities: {'events'},
      topics: {
        'events': HostTopic(capability: 'events', events: events.stream),
      },
    );
    final received = <JsonMap>[];
    final subscription = host.subscribe('events').listen(received.add);
    events.add({'generation': 1});
    await Future<void>.delayed(Duration.zero);
    scope.revoke();
    events.add({'generation': 1, 'late': true});
    await scope.close();
    await scope.close();
    await Future<void>.delayed(Duration.zero);
    expect(received, hasLength(1));
    final event = PluginEvent.fromJson(received.single);
    expect(event.requestId, isNotEmpty);
    expect(event.generation, scope.generation);
    expect(event.type, 'events');
    expect(event.payload, {'generation': 1});
    expect(cancellations, 1);
    await subscription.cancel();
    await events.close();
  });

  test('所有注册即使有一项关闭失败也会被回收', () async {
    final scope = PluginScope('community.one');
    final closed = <int>[];
    var fail = true;
    scope.addCleanup(() {
      closed.add(1);
    });
    scope.addCleanup(() {
      closed.add(2);
      if (fail) throw StateError('failed');
    });
    scope.addCleanup(() async {
      closed.add(3);
    });
    await expectLater(scope.close(), throwsStateError);
    expect(closed, [3, 2, 1]);
    expect(scope.isActive, isFalse);
    fail = false;
    await scope.close();
    await scope.close();
    expect(closed, [3, 2, 1, 2]);
  });
}
