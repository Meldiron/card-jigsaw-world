/// The browser page the web build runs in: fetch a file from our own site
/// past every cache, and reload the page. Web only; the stubs throw.
library;

export 'web_page_stub.dart' if (dart.library.js_interop) 'web_page_web.dart';
