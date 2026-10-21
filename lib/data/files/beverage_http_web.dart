import 'dart:js_interop';

@JS('gymBeverage.get')
external JSPromise<JSString> _get(JSString url);
Future<String> beverageHttpGet(Uri uri) async =>
    (await _get(uri.toString().toJS).toDart
            .timeout(const Duration(seconds: 14)))
        .toDart;
