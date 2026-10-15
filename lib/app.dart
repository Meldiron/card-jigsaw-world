import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quick_actions/quick_actions.dart';

import 'core/app_links.dart';
import 'core/appwrite.dart';
import 'core/image_files.dart';
import 'core/platform.dart';
import 'core/reminders.dart';
import 'core/sfx.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/tokens.dart';
import 'features/links/deep_links.dart';
import 'features/store/purchase_host.dart';
import 'features/sync/sync_host.dart';
import 'features/update/update_host.dart';
import 'router.dart';
import 'state/auth.dart';
import 'state/catalog.dart';
import 'state/purchases.dart';
import 'state/reminders.dart';
import 'state/settings.dart';
import 'state/sync.dart';
import 'widgets/ui.dart';

class CardenApp extends ConsumerStatefulWidget {
  const CardenApp({super.key});

  @override
  ConsumerState<CardenApp> createState() => _CardenAppState();
}

class _CardenAppState extends ConsumerState<CardenApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ImageFiles.attach(ref.read(storageProvider));
    if (supportsQuickActions) _setUpQuickActions();
    if (supportsNotifications) _setUpReminders();
    // Apple: listen for transactions as soon as the app starts, so a purchase paid while the app
    // was closed, restarted or on another screen is added now. After the sign-in: the check needs
    // the session.
    if (supportsPurchases) _startPurchases();
  }

  Future<void> _startPurchases() async {
    try {
      await ref.read(authProvider.future);
    } catch (_) {}
    if (mounted) await ref.read(purchaseFlowProvider.notifier).start();
  }

  /// Home Screen long-press menu: "One last game?" opens a playable puzzle.
  /// Never called on web: the plugin has no implementation there.
  Future<void> _setUpQuickActions() async {
    const actions = QuickActions();
    await actions.initialize((type) async {
      if (type != 'one_last_game') return;
      if (!ref.read(settingsProvider).onboarded) ref.read(settingsProvider.notifier).setOnboarded();
      try {
        await ref.read(allPuzzlesProvider.future);
        await ref.read(packsProvider.future);
      } catch (_) {}
      final puzzle = ref.read(dailyPuzzleProvider) ?? pickRandomPlayable(ref);
      if (puzzle == null || !mounted) return;
      ref.read(routerProvider).push('/play/${puzzle.id}');
    });
    // The shortcut itself is declared statically in Info.plist
    // (UIApplicationShortcutItems) so it uses an SF Symbol and shows once.
  }

  /// A tapped daily reminder opens its daily puzzle (or Home); the week of
  /// reminders is planned again from the current state.
  void _setUpReminders() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ReminderChannel.listen((route) {
        if (!mounted) return;
        final router = ref.read(routerProvider);
        if (route.startsWith('/play/')) {
          router.push(route);
        } else {
          router.go(route);
        }
      });
      ref.read(remindersProvider).refresh();
    });
  }

  /// Links opened from outside the app on iPhone (the `carden://` scheme, universal links to
  /// the web site, the widget) reach this observer before the router's: [DeepLinks] shows them,
  /// with Home beneath a sheet or a page that opens above the tabs. Other schemes (the Appwrite
  /// sign-in redirect) go on to the router. On the web the link is the address the visit starts
  /// on (`routerProvider`), and browser back and forward stay with the router.
  @override
  Future<bool> didPushRouteInformation(RouteInformation routeInformation) async {
    if (isWeb) return false;
    final link = AppLink.parse(routeInformation.uri);
    if (link == null) return false;
    ref.read(deepLinksProvider).show(link);
    return true;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // On the web, resumed and inactive also follow the tab's focus.
    if (state == AppLifecycleState.resumed) {
      if (ref.read(settingsProvider).music) Sfx.instance.startMusic();
      ref.read(syncProvider.notifier).onResume();
      if (supportsPurchases) ref.read(purchaseFlowProvider.notifier).onResume();
      // Picks up a permission change made in iOS Settings.
      if (supportsNotifications) ref.read(remindersProvider).refresh();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive || state == AppLifecycleState.hidden) {
      Sfx.instance.stopMusic();
      ref.read(syncProvider.notifier).onPause();
      // Leaving the game: plan reminders from today's state (gift, daily puzzle).
      if (supportsNotifications && state == AppLifecycleState.paused) ref.read(remindersProvider).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Carden',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: appMessengerKey,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: settings.themeMode,
      routerConfig: router,
      builder: (context, child) {
        // Keep the UI readable on large accessibility font sizes.
        final mq = MediaQuery.of(context);
        // Toast host: a Scaffold above the Navigator shows the root
        // messenger's snack bars over every route, sheet and the tab bar.
        // Page Scaffolds register with the inner messenger instead, so a
        // toast is drawn once.
        final host = Scaffold(
          resizeToAvoidBottomInset: false,
          backgroundColor: Colors.transparent,
          body: ScaffoldMessenger(child: UpdateHost(child: SyncHost(child: PurchaseHost(child: child!)))),
        );
        // Text follows the system size up to iOS "xxxLarge" (1.35); bars cap themselves at 1.2 (ChromeText).
        final data = mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.35));
        if (!ref.watch(platformCapsProvider).isWeb) return MediaQuery(data: data, child: host);
        return PhoneFrame(mediaQuery: data, child: host);
      },
    );
  }
}

/// Web only: keeps the phone layout at phone width on desktop browsers.
///
/// Centres the app in a column of at most [maxWidth] logical pixels with the
/// canvas colour around it, and narrows the inherited [MediaQuery] so screens
/// that size themselves from `MediaQuery.sizeOf` see the column, not the
/// window. Narrow windows (phones) are untouched.
class PhoneFrame extends StatelessWidget {
  const PhoneFrame({super.key, required this.mediaQuery, required this.child});

  static const double maxWidth = 520;

  final MediaQueryData mediaQuery;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final canvas = Theme.of(context).extension<AppColors>()?.canvas ?? Theme.of(context).scaffoldBackgroundColor;
    return ColoredBox(
      color: canvas,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth.isFinite ? constraints.maxWidth : mediaQuery.size.width;
          final height = constraints.maxHeight.isFinite ? constraints.maxHeight : mediaQuery.size.height;
          final framed = width > maxWidth;
          final size = Size(framed ? maxWidth : width, height);
          final body = MediaQuery(data: mediaQuery.copyWith(size: size), child: child);
          if (!framed) return body;
          return Center(
            child: SizedBox(
              width: maxWidth,
              height: height,
              child: DecoratedBox(
                decoration: BoxDecoration(border: Border.symmetric(vertical: BorderSide(color: Theme.of(context).extension<AppColors>()?.stroke ?? Colors.transparent))),
                child: body,
              ),
            ),
          );
        },
      ),
    );
  }
}
