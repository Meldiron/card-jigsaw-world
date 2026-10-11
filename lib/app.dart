import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quick_actions/quick_actions.dart';

import 'core/platform.dart';
import 'core/sfx.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/tokens.dart';
import 'router.dart';
import 'state/catalog.dart';
import 'state/settings.dart';
import 'widgets/ui.dart';

class CardJigsawApp extends ConsumerStatefulWidget {
  const CardJigsawApp({super.key});

  @override
  ConsumerState<CardJigsawApp> createState() => _CardJigsawAppState();
}

class _CardJigsawAppState extends ConsumerState<CardJigsawApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (supportsQuickActions) _setUpQuickActions();
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

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (ref.read(settingsProvider).music) Sfx.instance.startMusic();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      Sfx.instance.stopMusic();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'Card Jigsaw World',
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
          body: ScaffoldMessenger(child: child!),
        );
        final data = mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.2));
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
