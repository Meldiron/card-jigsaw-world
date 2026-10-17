// The legal pages the app links to (Settings > About, under the VIP plans, the sign-in screen) are
// the same pages the App Store listing names, and the terms of use are the repository's own page,
// which keeps Apple's standard licence agreement in force.
import 'dart:io' show File;

import 'package:carden/core/links.dart';
import 'package:flutter_test/flutter_test.dart';

const _repoBlob = 'https://github.com/Meldiron/carden/blob/main/';

void main() {
  test('terms of use: the repository page the listing gives, which keeps the Apple EULA', () {
    final url = AppLinks.termsOfUse.toString();
    expect(url, startsWith(_repoBlob));
    final page = File(url.substring(_repoBlob.length));
    expect(page.existsSync(), isTrue, reason: '$url is a file in this repository');
    expect(page.readAsStringSync(), contains('https://www.apple.com/legal/internet-services/itunes/dev/stdeula/'));
    final description = File('store/metadata/en-US/description.txt').readAsLinesSync();
    expect(description.where((l) => l.startsWith('Terms of use: ')).single, 'Terms of use: $url');
  });

  test('privacy policy: the repository page the listing gives', () {
    final url = AppLinks.privacyPolicy.toString();
    expect(File(url.substring(_repoBlob.length)).existsSync(), isTrue);
    expect(File('store/metadata/en-US/privacy_url.txt').readAsStringSync().trim(), url);
    final description = File('store/metadata/en-US/description.txt').readAsLinesSync();
    expect(description.where((l) => l.startsWith('Privacy policy: ')).single, 'Privacy policy: $url');
  });
}
