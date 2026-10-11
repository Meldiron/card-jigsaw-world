/// Full-page browser navigation (web only). Used for the OAuth redirect:
/// the browser leaves for the provider and returns to `/auth/callback`.
library;

export 'web_redirect_stub.dart' if (dart.library.js_interop) 'web_redirect_web.dart';
