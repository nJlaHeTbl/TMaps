import 'dart:js_interop';

@JS('tmapsTurnstile.getToken')
external JSPromise<JSString> _getToken(JSString siteKey);

/// Runs the Turnstile widget defined in `web/index.html` and returns a
/// single-use token. Each protected request needs a fresh token.
Future<String?> fetchTurnstileToken(String siteKey) async {
  final token = await _getToken(siteKey.toJS).toDart;
  return token.toDart;
}
