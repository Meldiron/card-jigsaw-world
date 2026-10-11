/// Non-web platforms: a top-level browser navigation does not exist.
void navigateTo(String url) => throw UnsupportedError('Browser redirects are only available on web.');
