/// Non-web platforms: there is no page to fetch from or reload.
Future<String?> fetchFresh(String url) => throw UnsupportedError('Only available on web.');

/// Non-web platforms: there is no page to reload.
void reloadPage() => throw UnsupportedError('Only available on web.');
