import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/local_store.dart';
import '../game/board.dart';
import '../game/image_loader.dart';
import '../models/models.dart';
import 'catalog.dart';
import 'profile.dart';
import 'progress.dart';
import 'rewards.dart';
import 'settings.dart';
import 'unlocks.dart';

/// A new player's first steps (owner, 2026-10-16; docs/first-steps.md): the welcome pages end on
/// a first board with a hint for each step, Home starts with three things and grows as they play
/// ([Reveal]), locked tabs say when they open, and tips come at the moment they matter. "Unlock
/// anyway" opens one thing (a tab) or everything (Home) at once; Settings > Guided start turns it
/// back on. Players who started before this have no record here and see the whole app.
@immutable
class FirstSteps {
  const FirstSteps({this.guided = false, this.showEverything = false, this.firstBoard = true, this.tips = const {}, this.early = const {}});

  /// This device started as a new player: the guided start applies (set when onboarding ends).
  final bool guided;

  /// "Unlock anyway" on Home, or Settings > Guided start off: everything is open.
  final bool showEverything;

  /// The welcome pages end on a first board (integration suites of the whole app turn it off).
  final bool firstBoard;

  /// One-time tips already shown (`tab:<name>` for a tab's "new" dot, `stuck`, `tip:library`, ...).
  final Set<String> tips;

  /// [Reveal]s opened early with "Unlock anyway" (a locked tab).
  final Set<String> early;

  bool get calm => guided && !showEverything;

  static const storeKey = 'firstSteps';

  factory FirstSteps.fromJson(Map<String, dynamic>? j) => FirstSteps(
        guided: j?['guided'] == true,
        showEverything: j?['showEverything'] == true,
        firstBoard: j?['firstBoard'] != false,
        tips: {for (final t in (j?['tips'] as List?) ?? const []) '$t'},
        early: {for (final t in (j?['early'] as List?) ?? const []) '$t'},
      );

  Map<String, dynamic> toJson() => {
        'guided': guided,
        'showEverything': showEverything,
        'firstBoard': firstBoard,
        'tips': tips.toList()..sort(),
        'early': early.toList()..sort(),
      };

  FirstSteps copyWith({bool? guided, bool? showEverything, bool? firstBoard, Set<String>? tips, Set<String>? early}) => FirstSteps(
        guided: guided ?? this.guided,
        showEverything: showEverything ?? this.showEverything,
        firstBoard: firstBoard ?? this.firstBoard,
        tips: tips ?? this.tips,
        early: early ?? this.early,
      );

  /// Onboarding ended on this device (the welcome pages, a first link, a sign-in): a player with no
  /// record yet gets the guided start. Called by `SettingsNotifier.setOnboarded`.
  static Future<void> markNewPlayer(LocalStore store) async {
    if (store.getJson(storeKey) != null) return;
    await store.setJson(storeKey, const FirstSteps(guided: true).toJson());
  }

  /// Integration suites that test the whole app start as a player who is past the first steps: no
  /// first board, no hints, every tab and section open.
  static Future<void> skipFor(LocalStore store) async {
    store.tutorialSeen = true;
    await store.setJson(storeKey, const FirstSteps(firstBoard: false).toJson());
  }
}

class FirstStepsNotifier extends Notifier<FirstSteps> {
  LocalStore get _s => ref.read(localStoreProvider);

  @override
  FirstSteps build() => FirstSteps.fromJson(ref.watch(localStoreProvider).getJson(FirstSteps.storeKey));

  void _save(FirstSteps v) {
    _s.setJson(FirstSteps.storeKey, v.toJson());
    state = v;
  }

  /// Reads the record again (after `markNewPlayer` wrote it).
  void reload() => state = FirstSteps.fromJson(_s.getJson(FirstSteps.storeKey));

  /// "Unlock anyway" on Home: everything opens now, with no tips about it.
  void showEverything() => _save(state.copyWith(showEverything: true));

  /// "Unlock anyway" on a locked tab or section: [r] opens now (no "new" dot for a tab).
  void openEarly(Reveal r) => _save(state.copyWith(early: {...state.early, r.name}, tips: {...state.tips, if (r.tab != null) 'tab:${r.name}'}));

  /// Settings > Guided start. Turning it on keeps what the player has reached open, with no
  /// "new" dots for tabs they had.
  void setGuided(bool on) {
    final solved = ref.read(solvedCountProvider);
    final reached = [for (final r in Reveal.values) if (solved >= r.solves && r.tab != null) r];
    _save(state.copyWith(
      guided: on || state.guided,
      showEverything: !on,
      early: on ? const {} : state.early,
      tips: on ? {...state.tips, for (final r in reached) 'tab:${r.name}'} : state.tips,
    ));
  }

  void sawTip(String key) {
    if (state.tips.contains(key)) return;
    _save(state.copyWith(tips: {...state.tips, key}));
  }
}

final firstStepsProvider = NotifierProvider<FirstStepsNotifier, FirstSteps>(FirstStepsNotifier.new);

/// What the guided start keeps back until the player is ready for it, in the order it opens, by
/// pictures solved (owner, 2026-10-16: daily 5, daily gift 10, Lucky Wheel 15, Quests 20,
/// achievements 25, piggy bank 30, live events 35, Social 50).
enum Reveal {
  packs(solves: 2, label: 'Packs on Home', plural: true, blurb: 'The packs you play, new packs and the ones you finish.'),
  quickPlay(solves: 3, label: 'Quick play'),
  daily(solves: 5, label: 'Daily puzzle', blurb: 'A new picture every day, the same for everyone, with a bonus.'),
  saveProgress(solves: 5, label: 'Save your progress'),
  streak(solves: 10, label: 'Daily gift', blurb: 'A gift every day you play, bigger with your streak.'),
  wheel(solves: 15, label: 'Lucky Wheel', blurb: 'Spin for coins, tickets and hints.'),
  quests(solves: 20, label: 'Quests', plural: true, tab: 2, blurb: 'Daily and weekly goals that pay coins and tickets.'),
  promos(solves: 20, label: 'Store offers', plural: true),
  achievements(solves: 25, label: 'Achievements', plural: true, blurb: 'Goals across all your play, each with a reward.'),
  piggy(solves: 30, label: 'Piggy bank', blurb: 'Saves a few coins from every picture.'),
  liveEvents(solves: 35, label: 'Live events', plural: true, blurb: 'World-day packs, each open for a week.'),
  social(solves: 50, label: 'Social', tab: 3, blurb: 'A weekly league, friends and messages from Carden.');

  const Reveal({required this.solves, required this.label, this.plural = false, this.blurb = '', this.tab});

  /// Pictures solved it waits for.
  final int solves;
  final String label;
  final bool plural;

  /// What it is, in one line (the Home list of what is to come, the locked tab's alert).
  final String blurb;

  /// Its tab in the tab bar (Quests 2, Social 3), when it is one.
  final int? tab;

  /// Listed under "More opens as you play".
  bool get listed => blurb.isNotEmpty;

  /// When it opens, as the alerts and the list say it.
  String get when => solves == 1 ? 'after your first picture' : 'after $solves pictures';

  /// "Quests open after 20 pictures", "Social opens after 50 pictures".
  String get opensTitle => '$label ${plural ? 'open' : 'opens'} $when';

  /// The chip in the list of what is to come.
  String get short => '$solves pictures';
}

/// Pictures the player has finished (local progress, so a first solve counts at once).
final solvedCountProvider = Provider<int>((ref) {
  final rows = ref.watch(progressProvider).value ?? const <String, PuzzleProgress>{};
  return rows.values.where((p) => p.completed).length;
});

/// Is [r] open? Always, unless the guided start applies and the player has not reached it.
bool revealOpen(Reveal r, {required FirstSteps steps, required int solved}) => !steps.calm || steps.early.contains(r.name) || solved >= r.solves;

final revealsProvider = Provider<Set<Reveal>>((ref) {
  final steps = ref.watch(firstStepsProvider);
  final solved = ref.watch(solvedCountProvider);
  return {for (final r in Reveal.values) if (revealOpen(r, steps: steps, solved: solved)) r};
});

/// What is still to come, in the order it opens ("More opens as you play" on Home).
final upcomingRevealsProvider = Provider<List<Reveal>>((ref) {
  final open = ref.watch(revealsProvider);
  return [for (final r in Reveal.values) if (!open.contains(r) && r.listed) r];
});

/// A tab that opened by playing and has not been visited: it carries a dot until then.
final newTabsProvider = Provider<Set<int>>((ref) {
  final steps = ref.watch(firstStepsProvider);
  if (!steps.calm) return const {};
  final open = ref.watch(revealsProvider);
  return {for (final r in Reveal.values) if (r.tab != null && open.contains(r) && !steps.tips.contains('tab:${r.name}')) r.tab!};
});

/// The first board: Pink Sands Beach from the free starter pack Tropical Beaches, else the pack's
/// first picture, else today's picture; a 3x3 Cards board. Picked for being easy on nine cards:
/// of the six starter packs' pictures it is among the few whose nine cards all differ clearly in
/// colour and detail (sky, palm, sea, path), and it is calm.
const firstBoardPuzzle = 'p-83816959304c';
const firstBoardPack = 'pack-tropical-beaches';

typedef FirstBoard = ({Puzzle puzzle, String route});

final firstBoardProvider = Provider<FirstBoard?>((ref) {
  final puzzles = ref.watch(allPuzzlesProvider).value;
  if (puzzles == null) return null;
  final starter = puzzles.where((z) => z.packId == firstBoardPack).toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  final pick = starter.where((z) => z.id == firstBoardPuzzle).firstOrNull ?? starter.firstOrNull ?? ref.watch(dailyPuzzleProvider);
  if (pick == null) return null;
  return (puzzle: pick, route: '/game/${pick.id}/${BoardCode.toPath(firstBoardSpec.fullCode)}?first=1');
});

/// Nine cards: the smallest board of the ladder.
const firstBoardSpec = BoardSpec(GameMode.cards, 3, 3, 'Cozy');

/// Decodes the first board's picture while the welcome pages are open, so the board is dealt at
/// once (the decode is kept for the session by [puzzleImageProvider]).
final firstBoardPrefetchProvider = Provider.autoDispose<void>((ref) {
  final first = ref.watch(firstBoardProvider);
  if (first != null) ref.watch(puzzleImageProvider(first.puzzle.imageUrl));
});

/// Should the welcome pages lead into the first board? Only for a new player on this device.
bool wantsFirstBoard(Ref ref) {
  final steps = ref.read(firstStepsProvider);
  return steps.guided && steps.firstBoard && ref.read(solvedCountProvider) == 0 && (ref.read(profileProvider).value?.level ?? 1) <= 1;
}

/// The one suggestion on the guided Home: the next small thing worth doing.
@immutable
class NextStep {
  const NextStep({required this.key, required this.label, required this.title, required this.subtitle, required this.route, this.puzzle});
  final String key;

  /// The small line above the title ("Start here", "Next in Wild Nature").
  final String label;
  final String title;
  final String subtitle;
  final String route;

  /// Its picture, shown on the card.
  final Puzzle? puzzle;
}

final nextStepProvider = Provider<NextStep?>((ref) {
  final steps = ref.watch(firstStepsProvider);
  if (!steps.calm) return null;
  final solved = ref.watch(solvedCountProvider);
  final progress = ref.watch(progressProvider).value ?? const <String, PuzzleProgress>{};
  final puzzles = ref.watch(allPuzzlesProvider).value ?? const <Puzzle>[];
  if (solved == 0) {
    final first = ref.watch(firstBoardProvider);
    // A first board already started shows as Continue.
    if (first == null || progress[first.puzzle.id]?.inProgress == true) return null;
    return NextStep(key: 'first', label: 'Start here', title: 'Your first picture', subtitle: 'Nine cards and no clock. A minute or two.', route: first.route, puzzle: first.puzzle);
  }
  final pack = puzzles.where((z) => z.packId == firstBoardPack).toList()..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  final packName = ref.watch(packsProvider).value?.where((p) => p.id == firstBoardPack).firstOrNull?.name ?? 'your first pack';
  final done = pack.where((z) => progress[z.id]?.completed == true).length;
  final next = pack.where((z) => progress[z.id]?.completed != true && progress[z.id]?.inProgress != true).firstOrNull;
  final features = ref.watch(openFeaturesProvider);
  final squaresUsed = (ref.watch(profileProvider).value?.solvedByMode[GameMode.squares.code] ?? 0) > 0;
  if (next != null && features.open.contains(Unlock.squares) && !squaresUsed) {
    return NextStep(key: 'squares', label: 'New for you', title: 'Try Squares', subtitle: 'The same pictures cut into even squares, for a little more reward.', route: '/play/${next.id}', puzzle: next);
  }
  if (next != null && done < 5) {
    return NextStep(key: 'pack', label: 'Next in $packName', title: next.title, subtitle: '$done of ${pack.length} done in your first pack. Free to play.', route: '/play/${next.id}', puzzle: next);
  }
  return const NextStep(key: 'library', label: 'When you are ready', title: 'Find a pack you like', subtitle: 'Free packs to start, and many more that open with coins.', route: '/library');
});
