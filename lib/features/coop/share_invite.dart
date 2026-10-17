import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../../state/coop/coop_models.dart';
import '../../widgets/icons.dart';
import '../../widgets/ui.dart';

/// The invite's words, before the link.
String inviteText(String? pictureTitle) {
  final t = pictureTitle?.trim() ?? '';
  return t.isEmpty || t == 'Untitled' ? 'Play a picture with me in Carden' : 'Play $t with me in Carden';
}

/// Shares the invite to [game]: the iPhone's share sheet (Messages, WhatsApp, Messenger,
/// Instagram, Snapchat...) or the browser's (Web Share API). Where a browser has none, the link is
/// copied instead.
///
/// share_plus was checked before it was added (owner rule: the app talks only to Appwrite and Apple):
/// on iPhone it opens UIActivityViewController and builds the link preview's title itself (no
/// metadata fetch); on the web it calls `navigator.share`, and its mailto fallback stays off here.
Future<void> shareInvite(BuildContext context, CoopGame game, {String? pictureTitle}) async {
  final text = '${inviteText(pictureTitle)}\n${game.joinUrl}';
  final box = context.findRenderObject();
  final origin = box is RenderBox && box.hasSize ? box.localToGlobal(Offset.zero) & box.size : null;
  try {
    await SharePlus.instance.share(ShareParams(
      text: text,
      subject: inviteText(pictureTitle),
      sharePositionOrigin: origin,
      mailToFallbackEnabled: false,
      downloadFallbackEnabled: false,
    ));
  } catch (_) {
    if (context.mounted) await copyInvite(context, game);
  }
}

/// Copies the invite link (a browser without a share sheet).
Future<void> copyInvite(BuildContext context, CoopGame game) async {
  await Clipboard.setData(ClipboardData(text: '${game.joinUrl}'));
  if (context.mounted) showToast(context, 'Invite link copied', icon: AppIcons.copy);
}
