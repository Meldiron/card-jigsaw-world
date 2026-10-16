// Offensive names and pack code links on the real iPhone app (live Appwrite backend, a QA guest):
// Profile > tap the name > an offensive name is refused and the old name stays; a pack code link
// (`carden://redeem?code=`) opens no code entry on iPhone, where codes are not redeemed.
//
//   tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/name_filter_test.dart -d <simulator>
import 'package:carden/app.dart';
import 'package:carden/core/sfx.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/state/profile.dart';
import 'package:carden/state/settings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> settle(WidgetTester tester, [int ms = 1500]) async {
  await tester.pump(const Duration(milliseconds: 50));
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (DateTime.now().isBefore(end)) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  Future<void> shot(WidgetTester tester, String name, {int wait = 300}) async {
    if (wait > 0) await settle(tester, wait);
    await binding.takeScreenshot(name);
  }

  Future<void> tapText(WidgetTester tester, String text, {int ms = 1200}) async {
    final f = find.text(text);
    expect(f, findsWidgets, reason: 'expected "$text" on screen');
    await tester.tap(f.first, warnIfMissed: false);
    await settle(tester, ms);
  }

  testWidgets('an offensive name is refused; a pack code link opens nothing on iPhone', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    Sfx.instance.soundEnabled = false;
    Sfx.instance.musicEnabled = false;
    await tester.pumpWidget(ProviderScope(overrides: [localStoreProvider.overrideWithValue(store)], child: const CardenApp()));
    await settle(tester, 1500);
    await tapText(tester, 'Continue');
    await tapText(tester, 'Continue');
    await tapText(tester, 'Start playing', ms: 5000);
    await settle(tester, 4000);
    final container = ProviderScope.containerOf(tester.element(find.byType(CardenApp)));

    // Profile > tap the name > type an offensive one > Save.
    await tapText(tester, 'Profile', ms: 2500);
    final before = container.read(profileProvider).value!.displayName;
    await tapText(tester, before);
    expect(find.text('Your name'), findsOneWidget);
    await tester.enterText(find.byType(CupertinoTextField).last, 'Big F4ck');
    await settle(tester, 600);
    await shot(tester, 'name_01_offensive_typed');
    await tapText(tester, 'Save', ms: 800);
    expect(find.text('That name is not allowed. Choose another one.'), findsOneWidget);
    await shot(tester, 'name_02_refused', wait: 0);
    await settle(tester, 2000);
    expect(container.read(profileProvider).value!.displayName, before, reason: 'the old name stays');

    // An ordinary name is saved.
    await tapText(tester, before);
    await tester.enterText(find.byType(CupertinoTextField).last, 'Tropical Peacock');
    await settle(tester, 600);
    await tapText(tester, 'Save', ms: 2500);
    expect(container.read(profileProvider).value!.displayName, 'Tropical Peacock');
    expect(find.text('Tropical Peacock'), findsWidgets);
    await shot(tester, 'name_03_ordinary_saved');

    // A pack code link: the iPhone app has no code entry.
    const codec = JSONMethodCodec();
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/navigation',
      codec.encodeMethodCall(const MethodCall('pushRouteInformation', {'location': 'carden://redeem?code=abcd-efgh-jklm-npqr'})),
      (_) {},
    );
    await settle(tester, 3000);
    expect(find.text('Redeem a pack code'), findsNothing);
    expect(find.byKey(const ValueKey('redeem-code-field')), findsNothing);
    await shot(tester, 'name_04_redeem_link_nothing');

    // Settings has no pack code row on iPhone either.
    await tester.tap(find.byIcon(CupertinoIcons.gear_alt_fill).first, warnIfMissed: false);
    await settle(tester, 2000);
    await tester.dragUntilVisible(find.text('Blocked players'), find.byType(Scrollable).first, const Offset(0, -250));
    await settle(tester, 800);
    expect(find.text('Redeem a pack code'), findsNothing);
    await shot(tester, 'name_05_settings_account');
    expect(container.read(settingsProvider).onboarded, isTrue);
  });
}
