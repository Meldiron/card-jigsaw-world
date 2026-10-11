import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quick_actions/quick_actions.dart';

import 'core/sfx.dart';
import 'core/theme/app_theme.dart';
import 'router.dart';
import 'state/catalog.dart';
import 'state/settings.dart';

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
    _setUpQuickActions();
  }

  /// Home Screen long-press menu: "One last game?" opens a playable puzzle.
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
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: settings.themeMode,
      routerConfig: router,
      builder: (context, child) {
        // Keep the UI readable on large accessibility font sizes.
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.2)),
          child: child!,
        );
      },
    );
  }
}
