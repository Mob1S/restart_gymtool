import 'dart:js_interop';

import 'plugin_runtime_web.dart';

@JS('gymBeverage.get')
external JSPromise<JSString> _get(JSString url, JSString sessionId);
Future<void> cancelBeverageHttpSession(String sessionId) async {
  // Cancellation must not initialize a never-used optional runtime.
  await cancelPluginSearch(sessionId);
}

Future<String> beverageHttpGet(Uri uri, {String sessionId = ''}) async {
  await loadPluginRuntime('beverage');
  return (await _get(
    uri.toString().toJS,
    sessionId.toJS,
  ).toDart.timeout(const Duration(seconds: 14))).toDart;
}
