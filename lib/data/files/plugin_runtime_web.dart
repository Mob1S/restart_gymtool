import 'dart:js_interop';

@JS('gymPluginRuntime.load')
external JSPromise<JSAny?> _load(JSString id);
@JS('gymPluginRuntime.deactivate')
external JSPromise<JSAny?> _deactivate(JSString id);
@JS('gymPluginRuntime.activate')
external JSPromise<JSAny?> _activate(JSString id);
@JS('gymPluginRuntime.cancel')
external JSPromise<JSAny?> _cancel(JSString id);
@JS('gymPluginRuntime.cancelSearch')
external JSPromise<JSAny?> _cancelSearch(JSString sessionId);

Future<void> cancelPluginSearch(String sessionId) async {
  await _cancelSearch(sessionId.toJS).toDart;
}

Future<void> cancelPluginRuntime(String id) async {
  await _cancel(id.toJS).toDart;
}

Future<void> activatePluginRuntime(String id) async {
  await _activate(id.toJS).toDart;
}

Future<void> loadPluginRuntime(String id) async {
  await _load(id.toJS).toDart;
}

Future<void> deactivatePluginRuntime(String id) async {
  await _deactivate(id.toJS).toDart;
}
