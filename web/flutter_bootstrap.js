{{flutter_js}}
{{flutter_build_config}}

// The engine is shipped with the web build; training must not require a CDN.
_flutter.loader.load({config: {canvasKitBaseUrl: 'canvaskit/'}});
