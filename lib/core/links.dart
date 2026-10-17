import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

/// Pages the app links to. The privacy policy is the repository's `docs/privacy-policy.md` (the same
/// address as the App Store listing, `store/metadata/en-US/privacy_url.txt`); the terms of use are
/// its `docs/terms-of-use.md` (Apple's standard licence agreement, which applies, plus Carden's own
/// terms), the address the listing's description gives.
abstract final class AppLinks {
  static final privacyPolicy = Uri.parse('https://github.com/Meldiron/carden/blob/main/docs/privacy-policy.md');
  static final termsOfUse = Uri.parse('https://github.com/Meldiron/carden/blob/main/docs/terms-of-use.md');

  /// Where people get the app: the public TestFlight link until Carden is on the App Store, then
  /// `https://apps.apple.com/app/id6821644423` (docs/release-checklist.md, "After approval"). The web
  /// page of a Play together invite offers it too (`GET_CARDEN` in web/index.html, kept equal by
  /// test/deep_links_test.dart).
  static final getCarden = Uri.parse('https://testflight.apple.com/join/7nPCfg6A');

  /// The App Store's subscription management (opens the system sheet on iPhone).
  static final manageSubscriptions = Uri.parse('https://apps.apple.com/account/subscriptions');
  static const supportEmail = 'contact@almostapps.eu';
  static final support = Uri(scheme: 'mailto', path: supportEmail);

  /// An email to support with a subject, and below the space for the message the app version and
  /// the player id, so support can find the account.
  static Uri supportMail({String? version, String? platform, String? playerId}) {
    final details = [
      if (version != null && version.isNotEmpty) 'Version $version${platform == null ? '' : ' · $platform'}',
      if (playerId != null) 'Player id: $playerId',
    ];
    final body = details.isEmpty ? '' : '\n\n\n---\n${details.join('\n')}';
    // Encoded by hand: mail apps show a "+" for a space encoded the form way.
    return Uri.parse('mailto:$supportEmail?subject=${Uri.encodeComponent('Carden support')}${body.isEmpty ? '' : '&body=${Uri.encodeComponent(body)}'}');
  }
}

/// Opens [url] in the in-app browser (Safari view on iPhone, a new tab on the web); false when
/// nothing could open it.
Future<bool> openLink(Uri url) async {
  try {
    final mode = url.scheme == 'mailto' ? LaunchMode.externalApplication : LaunchMode.inAppBrowserView;
    return await launchUrl(url, mode: mode, webOnlyWindowName: '_blank');
  } catch (e) {
    debugPrint('open $url failed: $e');
    return false;
  }
}
