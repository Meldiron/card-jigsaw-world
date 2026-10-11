import 'dart:js_interop';

@JS('location.href')
external set _locationHref(String value);

/// Replaces the page with [url]; the app reloads when the browser comes back.
void navigateTo(String url) => _locationHref = url;
