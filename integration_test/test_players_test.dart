// QA test players and the profile statistics (live Appwrite backend, fresh guest):
//   tools/dev/qa-run.sh drive --driver=test_driver/integration_test.dart \
//     --target=integration_test/test_players_test.dart -d CDD7317C-19D6-486D-B258-8AB8A607297D
// Checks that the QA run's guest is flagged and out of the league as everyone else sees it (while
// it still sees its own row), and captures Profile > Statistics (Total Completion, Quests
// completed) and another player's profile to screenshots/qa_*.png. Facts go to
// build/integration_response_data.json.
import 'package:card_jigsaw_world/app.dart';
import 'package:card_jigsaw_world/core/appwrite.dart';
import 'package:card_jigsaw_world/core/qa.dart';
import 'package:card_jigsaw_world/core/sfx.dart';
import 'package:card_jigsaw_world/data/local_store.dart';
import 'package:card_jigsaw_world/data/repositories.dart';
import 'package:card_jigsaw_world/models/models.dart';
import 'package:card_jigsaw_world/router.dart';
import 'package:card_jigsaw_world/state/auth.dart';
import 'package:card_jigsaw_world/state/catalog.dart';
import 'package:card_jigsaw_world/state/profile.dart';
import 'package:card_jigsaw_world/state/progress.dart';
import 'package:card_jigsaw_world/state/settings.dart';
import 'package:card_jigsaw_world/state/social.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The owner's account: a real player whose public profile is shown.
const ownerId = '6acbbf8a8898f585d3ca';

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

  Future<void> shot(WidgetTester tester, String name) async {
    await settle(tester, 600);
    await binding.takeScreenshot(name);
  }

  /// Scrolls so [text] sits at [at] of the viewport height (below the glass header).
  Future<void> showNearTop(WidgetTester tester, String text, {double at = 0.12}) async {
    await Scrollable.ensureVisible(tester.element(find.text(text).first), alignment: at);
    await settle(tester, 800);
  }

  Future<void> tapText(WidgetTester tester, String text, {int ms = 1200}) async {
    final f = find.text(text);
    expect(f, findsWidgets, reason: 'expected "$text" on screen');
    await tester.tap(f.first, warnIfMissed: false);
    await settle(tester, ms);
  }

  testWidgets('a QA guest is flagged, kept out of the league, and the statistics show quests and completion', (tester) async {
    expect(QaRun.enabled, isTrue, reason: 'run through tools/dev/qa-run.sh');
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    Sfx.instance.soundEnabled = false;
    Sfx.instance.musicEnabled = false;
    await tester.pumpWidget(ProviderScope(overrides: [localStoreProvider.overrideWithValue(store)], child: const CardJigsawApp()));
    await settle(tester, 1500);
    await tapText(tester, 'Continue');
    await tapText(tester, 'Continue');
    await tapText(tester, 'Start playing', ms: 5000);
    await settle(tester, 4000);
    if (find.text('Claim').evaluate().isNotEmpty) {
      await tapText(tester, 'Claim');
      if (find.textContaining('Claim day').evaluate().isNotEmpty) {
        await tester.tap(find.textContaining('Claim day'), warnIfMissed: false);
        await settle(tester, 1500);
      }
      await tester.tapAt(const Offset(220, 80));
      await settle(tester, 1000);
    }

    final c = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
    final user = c.read(authProvider).value!;
    var me = await c.read(profileProvider.future);
    final facts = <String, Object?>{'userId': me.id, 'runId': QaRun.id, 'prefs': user.prefs.data, 'isTest': me.isTest};
    expect(me.isTest, isTrue, reason: 'the QA guest is a test player');
    expect(user.prefs.data['qa'], isTrue);

    // Solve like the game does (progress row, then the profile's rewards): every picture of the
    // smallest free pack with three stars, and two more pictures with two stars.
    final packs = await c.read(packsProvider.future);
    final puzzles = await c.read(allPuzzlesProvider.future);
    List<Puzzle> of(Pack p) => puzzles.where((z) => z.packId == p.id && !z.isLockedByDate).toList();
    final free = packs.where((p) => p.isFree && !p.hasWindow && !p.isDaily && of(p).length >= 2).toList()..sort((a, b) => of(a).length.compareTo(of(b).length));
    final full = free.first, partial = free[1];
    Future<void> solve(Puzzle z, int stars) async {
      await c.read(progressProvider.notifier).save(z.id, {
        'gridSize': 16, 'mode': 'cards', 'layout': '', 'moves': 20, 'elapsedSeconds': 40, 'hintsUsed': 0,
        'completed': true, 'stars': stars, 'bestMoves': 20, 'bestSeconds': 40, 'completedAt': DateTime.now().toUtc().toIso8601String(),
      });
      await c.read(profileProvider.notifier).recordCompletion(cells: 16, stars: stars, firstTime: true, moves: 20, seconds: 40);
    }

    for (final z in of(full)) {
      await solve(z, 3);
    }
    for (final z in of(partial).take(2)) {
      await solve(z, 2);
    }
    await settle(tester, 3000);

    // Claim the "Solve 3 puzzles" quest on the Quests tab, the way a player does.
    await tapText(tester, 'Quests', ms: 2500);
    await shot(tester, 'qa_00_quests');
    final claim = find.text('Claim');
    if (claim.evaluate().isNotEmpty) {
      await tester.tap(claim.first, warnIfMissed: false);
      await settle(tester, 2500);
    }
    me = c.read(profileProvider).value!;
    facts['questsCompleted'] = me.questsCompleted;
    facts['solved'] = me.puzzlesCompleted;
    facts['public'] = {'picturesSolved': me.picturesSolved, 'picturesPerfect': me.picturesPerfect, 'packsCompleted': me.packsCompleted, 'packsPerfect': me.packsPerfect};
    expect(me.questsCompleted, greaterThanOrEqualTo(1));
    expect(me.packsCompleted, greaterThanOrEqualTo(1), reason: 'the public completion numbers follow the progress rows');

    // The league as everyone else sees it (server-side filter), page by page: no test player.
    final repo = ProfileRepository(c.read(tablesProvider));
    final everyone = <Profile>[];
    String? after;
    while (true) {
      final page = await repo.leaderboardPage(limit: 100, after: after);
      everyone.addAll(page.items);
      if (page.items.length < 100) break;
      after = page.lastId;
    }
    facts['leagueForOthers'] = everyone.length;
    facts['meInLeagueForOthers'] = everyone.any((p) => p.id == me.id);
    facts['testPlayersInLeagueForOthers'] = everyone.where((p) => p.isTest).length;
    expect(everyone.any((p) => p.id == me.id), isFalse, reason: 'other players never see the QA guest');
    expect(everyone.where((p) => p.isTest), isEmpty);
    // The QA guest itself still finds its own row.
    final mine = await repo.leaderboardPage(limit: 100, viewer: me);
    facts['meInMyLeague'] = mine.items.any((p) => p.id == me.id);
    final rank = await repo.leaderboardRank(me);
    facts['myRank'] = '${rank.rank} of ${rank.total}';
    expect(rank.total, everyone.length + 1);

    // Profile > Statistics: Total Completion and the quests tile.
    await tapText(tester, 'Profile', ms: 3000);
    final profileScroll = find.byType(CustomScrollView).last;
    await tester.dragUntilVisible(find.text('Total Completion'), profileScroll, const Offset(0, -250));
    await showNearTop(tester, 'Total Completion');
    await shot(tester, 'qa_01_profile_completion');
    await showNearTop(tester, 'Quests completed', at: 0.45);
    await shot(tester, 'qa_02_profile_quests');

    // Another player's profile (the owner's public numbers).
    c.read(routerProvider).push('/player/$ownerId');
    await settle(tester, 3500);
    await shot(tester, 'qa_03_player');
    final playerScroll = find.byType(ListView).first;
    await tester.dragUntilVisible(find.text('Total Completion'), playerScroll, const Offset(0, -250));
    await showNearTop(tester, 'Total Completion', at: 0.2);
    await shot(tester, 'qa_04_player_completion');
    await showNearTop(tester, 'Quests completed', at: 0.45);
    await shot(tester, 'qa_05_player_quests');
    if (find.byIcon(CupertinoIcons.back).evaluate().isNotEmpty) {
      await tester.tap(find.byIcon(CupertinoIcons.back).first, warnIfMissed: false);
      await settle(tester, 1500);
    }

    // The league as the QA guest sees it.
    await tapText(tester, 'Social', ms: 4000);
    await shot(tester, 'qa_06_league_as_test_player');
    final shown = c.read(leaderboardProvider).value?.items ?? const <Profile>[];
    facts['leagueRowsShownToMe'] = shown.length;
    facts['otherTestPlayersShownToMe'] = shown.where((p) => p.isTest && p.id != me.id).length;
    expect(shown.where((p) => p.isTest && p.id != me.id), isEmpty);
    // Next to the screenshots the driver saves (it reads them from the same map).
    binding.reportData = {...?binding.reportData, 'facts': facts};
    debugPrint('QA FACTS $facts');
  }, timeout: const Timeout(Duration(minutes: 10)));
}
