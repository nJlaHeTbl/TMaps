// Cloudflare Turnstile token for write requests. Only the web build can
// obtain one; other platforms return null.
export 'turnstile_token_stub.dart'
    if (dart.library.js_interop) 'turnstile_token_web.dart';
