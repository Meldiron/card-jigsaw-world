import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

/// Pages the app links to. The privacy policy is the repository's `docs/privacy-policy.md` (the same
/// address as the App Store listing, `store/metadata/en-US/privacy_url.txt`); the terms of use are
/// Apple's standard licence agreement, as the listing says.
abstract final class AppLinks {
  static final privacyPolicy = Uri.parse('https://github.com/Meldiron/card-jigsaw-world/blob/main/docs/privacy-policy.md');
  static final termsOfUse = Uri.parse('https://www.apple.com/legal/internet-services/itunes/dev/stdeula/');
  static const supportEmail = 'support@almostapps.eu';
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
    return Uri.parse('mailto:$supportEmail?subject=${Uri.encodeComponent('Card Jigsaw World support')}${body.isEmpty ? '' : '&body=${Uri.encodeComponent(body)}'}');
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
