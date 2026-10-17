// Settings > Accessibility > Text size: Largest (200%) on the iPhone SE frame (docs/accessibility.md):
// the pack card's price and progress row, the chips over photos (Home's "Today", a pack's category)
// and Home's greeting show their words whole, without a layout error.
import 'package:appwrite/models.dart' as models;
import 'package:carden/core/theme/app_theme.dart';
import 'package:carden/data/local_store.dart';
import 'package:carden/features/gallery/pack_card.dart';
import 'package:carden/features/home/home_screen.dart';
import 'package:carden/models/models.dart';
import 'package:carden/state/auth.dart';
import 'package:carden/state/catalog.dart';
import 'package:carden/state/profile.dart';
import 'package:carden/state/progress.dart';
import 'package:carden/state/settings.dart';
import 'package:carden/widgets/ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _NoAuth extends AuthNotifier {
  @override
  Future<models.User?> build() async => null;
}

class _Profile extends ProfileNotifier {
  @override
  Future<Profile> build() async => Profile.guest('local');
}

class _Rows extends ProgressNotifier {
  @override
  Future<Map<String, PuzzleProgress>> build() async => const {};
}

Pack _pack(String id, Map<String, dynamic> row) => Pack.fromRow(id, {'name': 'Pack $id', 'category': 'Nature', 'imageCount': 4, ...row});

/// [text] is drawn whole: as tall as its lines need, and on no more lines than it may have.
void expectWhole(WidgetTester tester, Finder text) {
  expect(text, findsWidgets);
  for (final e in text.evaluate()) {
    final p = e.renderObject! as RenderParagraph;
    expect(p.didExceedMaxLines, isFalse, reason: '"${(e.widget as Text).data}" is cut short');
    expect(p.size.height, greaterThanOrEqualTo(p.getMaxIntrinsicHeight(p.size.width) - 0.5), reason: '"${(e.widget as Text).data}" is clipped');
  }
}

void main() {
  final packs = [
    _pack('priced', {'priceCoins': 3300, 'sortOrder': 1}),
    _pack('free', {'isFree': true, 'sortOrder': 2}),
  ];
  final pictures = [
    for (final p in packs)
      for (var i = 1; i <= 4; i++) Puzzle.fromRow('${p.id}-$i', {'packId': p.id, 'title': 'Picture $i', 'sortOrder': i}),
  ];

  Future<void> pump(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(375, 667);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'onboarded': true});
    final store = await LocalStore.open();
    final router = GoRouter(initialLocation: '/home', routes: [GoRoute(path: '/home', builder: (_, _) => home)]);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        authProvider.overrideWith(_NoAuth.new),
        profileProvider.overrideWith(_Profile.new),
        progressProvider.overrideWith(_Rows.new),
        packsProvider.overrideWith((ref) async => packs),
        allPuzzlesProvider.overrideWith((ref) async => pictures),
        eventsProvider.overrideWith((ref) async => const <GameEvent>[]),
      ],
      child: MaterialApp.router(
        theme: AppTheme.light(),
        routerConfig: router,
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2)), child: child!),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('pack cards in the Library grid: the price and the progress show whole', (tester) async {
    // Two columns on the SE, at the grid's 0.78 ratio.
    const width = (375 - 2 * 20 - 12) / 2;
    await pump(
      tester,
      Scaffold(
        body: Column(children: [
          Row(children: [
            for (final p in packs) SizedBox(width: width, height: width / 0.78, child: PackCard(pack: p, onTap: () {})),
          ]),
          // Home's picture of the day carries this chip.
          const Chip2(label: 'Today', icon: Icons.calendar_today, onImage: true),
        ]),
      ),
    );
    expect(tester.takeException(), isNull);
    expectWhole(tester, find.text('3,300'));
    expectWhole(tester, find.text('0/4'));
    expectWhole(tester, find.text('Nature'));
    expectWhole(tester, find.text('Today'));
  });

  testWidgets("Home: the greeting wraps instead of losing the player's name", (tester) async {
    await pump(tester, const HomeScreen());
    expect(tester.takeException(), isNull);
    expectWhole(tester, find.textContaining(RegExp(r'^Good ')));
  });
}
