// Links into the game on the real app (live Appwrite backend), delivered the way iOS delivers them:
// the engine's `pushRouteInformation` on flutter/navigation with the link's full address, for the
// app's carden:// scheme and for universal links to the web site. A new player on the welcome
// screens follows links to a pack, the store, profiles, pictures (one in a pack they have not
// opened), a pack code and a friend code (both filled in), today's picture, Quick play, the wheel,
// Quests, a Library filter, the daily gift, the piggy bank, Settings, and links that are out of date.
//
// Run: tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart \
//        --target=integration_test/deep_links_test.dart -d <simulator>
import 'package:carden/app.dart';
import 'package:carden/core/sfx.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/features/gallery/library_screen.dart';
import 'package:carden/features/social/social_screen.dart';
import 'package:carden/router.dart';
import 'package:carden/state/catalog.dart';
import 'package:carden/state/rewards.dart';
import 'package:carden/state/settings.dart';
import 'package:carden/state/unlocks.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

Future<void> settle(WidgetTester tester, [int ms = 1500]) async {
  await tester.pump(const Duration(milliseconds: 50));
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

const _web = 'https://carden.appwrite.network';
const _owner = '6acbbf8a8898f585d3ca'; // a public profile to open and to add as a friend

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  Future<void> shot(WidgetTester tester, String name) async {
    await settle(tester, 400);
    await binding.takeScreenshot(name);
  }

  ProviderContainer container(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(CardenApp)));
  String top(WidgetTester tester) => container(tester).read(routerProvider).state.uri.toString();

  /// Sends [url] as iOS does when a link opens the app, and returns whether the app took it.
  Future<bool?> link(WidgetTester tester, String url, {int ms = 3000}) async {
    const codec = JSONMethodCodec();
    bool? handled;
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/navigation',
      codec.encodeMethodCall(MethodCall('pushRouteInformation', {'location': url})),
      (reply) => handled = reply == null ? null : codec.decodeEnvelope(reply) as bool?,
    );
    await settle(tester, ms);
    return handled;
  }

  /// Closes the sheet or alert on top.
  Future<void> close(WidgetTester tester) async {
    rootNavigatorKey.currentState!.pop();
    await settle(tester, 900);
  }

  /// Whether [f] is laid out inside the screen.
  bool onScreen(WidgetTester tester, Finder f) {
    if (f.evaluate().isEmpty) return false;
    final r = tester.getRect(f.first);
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    return r.left >= 0 && r.right <= size.width && r.top >= 0 && r.bottom <= size.height;
  }

  Future<void> back(WidgetTester tester) async {
    container(tester).read(routerProvider).pop();
    await settle(tester, 900);
  }

  testWidgets('links open their screens, from the welcome screens on', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    Sfx.instance.soundEnabled = false;
    Sfx.instance.musicEnabled = false;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        openFeaturesProvider.overrideWithValue(OpenFeatures.all),
        pendingUnlockIntroProvider.overrideWithValue(null),
      ],
      child: const CardenApp(),
    ));
    await settle(tester, 2500);
    expect(top(tester), '/welcome');
    final puzzles = await container(tester).read(allPuzzlesProvider.future);
    final butterfly = puzzles.firstWhere((z) => z.packId == 'pack-butterflies'); // a starter pack: open
    final owl = puzzles.firstWhere((z) => z.packId == 'pack-owls'); // priced since 2026-10-14

    // ---- A pack from an In-App Event, straight from the welcome screens.
    expect(await link(tester, 'carden://library/pack/pack-butterflies', ms: 4000), isTrue);
    expect(top(tester), '/library/pack/pack-butterflies');
    expect(container(tester).read(settingsProvider).onboarded, isTrue);
    await shot(tester, 'dl_01_pack_from_welcome');

    // ---- Universal link to the store: opens above the pack; closing it goes back there.
    expect(await link(tester, '$_web/store'), isTrue);
    expect(top(tester), '/store');
    expect(find.text('Store'), findsWidgets);
    await shot(tester, 'dl_02_store');
    await back(tester);
    expect(top(tester), '/library/pack/pack-butterflies');

    await link(tester, 'carden://vip');
    expect(top(tester), '/store?vip=1');
    expect(onScreen(tester, find.text('Carden VIP')), isTrue, reason: 'the store opens at VIP');
    await shot(tester, 'dl_03_vip');
    await back(tester);

    // ---- My profile, another player's profile.
    await link(tester, 'carden://profile');
    expect(top(tester), '/profile');
    await shot(tester, 'dl_04_profile');
    await link(tester, '$_web/player/$_owner', ms: 4000);
    expect(top(tester), '/player/$_owner');
    expect(find.text('Player not found'), findsNothing);
    await shot(tester, 'dl_05_player');
    await back(tester);
    expect(top(tester), '/profile');

    // ---- A picture (the widget's link), and one in a pack this player has not opened.
    await link(tester, 'carden://play/${butterfly.id}', ms: 4000);
    expect(top(tester), '/play/${butterfly.id}');
    expect(find.text(butterfly.title), findsWidgets);
    await shot(tester, 'dl_06_picture');
    await back(tester);
    await link(tester, '$_web/picture/${owl.id}', ms: 4000);
    expect(top(tester), '/library/pack/pack-owls', reason: 'no free board in a pack that is not open');
    expect(find.textContaining('Unlock for'), findsWidgets);
    await shot(tester, 'dl_07_closed_pack_picture');

    // ---- A pack code, filled in.
    await link(tester, '$_web/redeem?code=abcd-efgh-jklm-npqr');
    expect(find.text('Redeem a pack code'), findsOneWidget);
    expect(tester.widget<CupertinoTextField>(find.byKey(const ValueKey('redeem-code-field'))).controller!.text, 'ABCD-EFGH-JKLM-NPQR');
    await shot(tester, 'dl_08_redeem_code');
    await close(tester);

    // ---- A friend code, filled in on Social > Friends.
    await link(tester, 'carden://add-friend?code=$_owner');
    expect(top(tester), '/social');
    expect(container(tester).read(socialTabProvider), SocialTab.friends);
    expect(tester.widget<CupertinoTextField>(find.byKey(const ValueKey('add-friend-field'))).controller!.text, _owner);
    await shot(tester, 'dl_09_add_friend');
    await tester.tap(find.text('Not now'));
    await settle(tester, 900);

    // ---- Today's picture and Quick play.
    await link(tester, 'carden://daily', ms: 4000);
    final daily = container(tester).read(dailyPuzzleProvider)!;
    expect(top(tester), '/play/${daily.id}');
    await shot(tester, 'dl_10_daily');
    await back(tester);
    await link(tester, 'carden://quick', ms: 4000);
    expect(top(tester), startsWith('/play/'));
    expect(top(tester), contains('from=quick'));
    expect(find.text('Another picture'), findsWidgets);
    await shot(tester, 'dl_11_quick_play');
    await back(tester);

    // ---- The wheel, Quests, a Library filter.
    await link(tester, 'carden://wheel');
    expect(top(tester), '/wheel');
    expect(find.text('Lucky Wheel'), findsWidgets);
    await shot(tester, 'dl_12_wheel');
    await back(tester);
    await link(tester, '$_web/quests');
    expect(top(tester), '/events');
    await shot(tester, 'dl_13_quests');
    await link(tester, 'carden://library?filter=giant');
    expect(top(tester), '/library');
    expect(container(tester).read(libraryFilterProvider), 'Giant');
    expect(onScreen(tester, find.byKey(const ValueKey('library-chip-Giant'))), isTrue, reason: 'the chip scrolls into view');
    await shot(tester, 'dl_14_library_giant');

    // ---- Home sheets: the daily gift and the piggy bank.
    await link(tester, 'carden://gift');
    expect(top(tester), '/home');
    expect(find.text('Daily gift'), findsWidgets);
    await shot(tester, 'dl_15_daily_gift');
    await close(tester);
    await link(tester, 'carden://piggy');
    expect(find.text('Piggy bank'), findsWidgets);
    await shot(tester, 'dl_16_piggy');
    await close(tester);

    // ---- Settings, and links that are out of date.
    await link(tester, '$_web/settings');
    expect(top(tester), '/profile/settings');
    await shot(tester, 'dl_17_settings');
    await link(tester, 'carden://pack/pack-that-does-not-exist', ms: 3000);
    expect(top(tester), '/library/pack/pack-that-does-not-exist');
    expect(find.text('Pack not available'), findsOneWidget);
    await shot(tester, 'dl_18_pack_not_available');
    await link(tester, 'carden://play/picture-that-does-not-exist', ms: 4000);
    expect(find.text('Picture not available'), findsOneWidget);
    await shot(tester, 'dl_19_picture_not_available');
    await back(tester);

    // ---- Home, and a scheme that is not the game's (left to the router, which shows Home).
    await link(tester, '$_web/');
    expect(top(tester), '/home');
    expect(await link(tester, 'appwrite-callback-6acb4de5003e38d5ebd9://auth'), isTrue, reason: 'the router answers it');
    expect(top(tester), '/home');
    await shot(tester, 'dl_20_home');

    // ---- Through iOS itself: the app opens its own carden:// link (UIApplication.open), so
    // the scene delegate and the Flutter engine deliver it as they do for a tapped link.
    expect(await launchUrl(Uri.parse('carden://wheel'), mode: LaunchMode.externalApplication), isTrue);
    await settle(tester, 5000);
    expect(top(tester), '/wheel');
    await shot(tester, 'dl_21_wheel_through_ios');
  }, timeout: const Timeout(Duration(minutes: 8)));
}
