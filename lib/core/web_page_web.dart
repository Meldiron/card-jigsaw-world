import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// The body of [url] fetched past the browser cache, or null when the server
/// does not answer with 200.
Future<String?> fetchFresh(String url) async {
  final res = await web.window.fetch(url.toJS, web.RequestInit(cache: 'no-store')).toDart;
  if (!res.ok) return null;
  return (await res.text().toDart).toDart;
}

/// Loads the page again. The site serves every file with `max-age=0,
/// must-revalidate`, so the reload runs the newest deployment.
void reloadPage() => web.window.location.reload();
