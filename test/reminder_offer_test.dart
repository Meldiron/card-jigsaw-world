// The reminder question after a daily gift names event notes, which promote events: Turn on is the
// explicit yes to them (guideline 4.5.4); Not now leaves them off.
import 'package:appwrite/models.dart' as models;
import 'package:carden/core/platform.dart';
import 'package:carden/core/theme/app_theme.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/features/daily/daily_reward_sheet.dart';
import 'package:carden/models/models.dart';
import 'package:carden/state/auth.dart';
import 'package:carden/state/profile.dart';
import 'package:carden/state/reminders.dart';
import 'package:carden/state/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoAuth extends AuthNotifier {
  @override
  Future<models.User?> build() async => null;
}

class _Guest extends ProfileNotifier {
  @override
  Future<Profile> build() async => Profile.guest('local');
}

class _Reminders extends RemindersController {
  _Reminders(super.ref);
  var enabled = false;
  @override
  Future<bool> enable() async => enabled = true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<(ProviderContainer, BuildContext, _Reminders)> pump(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({'onboarded': true});
    final store = await LocalStore.open();
    store.giftClaimDays = 2;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('cjw/reminders'),
      (call) async => call.method == 'status' ? 'notDetermined' : null,
    );
    late _Reminders reminders;
    late BuildContext ctx;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        platformCapsProvider.overrideWithValue(PlatformCaps.ios),
        authProvider.overrideWith(_NoAuth.new),
        profileProvider.overrideWith(_Guest.new),
        remindersProvider.overrideWith((ref) => reminders = _Reminders(ref)),
      ],
      child: MaterialApp(theme: AppTheme.light(), home: Builder(builder: (c) {
        ctx = c;
        return const Scaffold();
      })),
    ));
    final container = ProviderScope.containerOf(ctx);
    container.read(remindersProvider);
    await container.read(profileProvider.future);
    return (container, ctx, reminders);
  }

  testWidgets('Turn on: daily reminders and event notes, both named in the question', (tester) async {
    final (container, ctx, reminders) = await pump(tester);
    expect(container.read(eventRemindersProvider), isFalse);
    final asked = offerRemindersAfterGift(ctx, container);
    await tester.pumpAndSettle();
    expect(find.text('Get a daily reminder?'), findsOneWidget);
    expect(find.textContaining('and one the evening before a new event opens'), findsOneWidget);
    await tester.tap(find.text('Turn on'));
    await tester.pumpAndSettle();
    await asked;
    expect(reminders.enabled, isTrue);
    expect(container.read(eventRemindersProvider), isTrue);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('Not now: no reminders and no event notes', (tester) async {
    final (container, ctx, reminders) = await pump(tester);
    final asked = offerRemindersAfterGift(ctx, container);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    await asked;
    expect(reminders.enabled, isFalse);
    expect(container.read(eventRemindersProvider), isFalse);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
