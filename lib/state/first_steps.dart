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

  /// One-time tips already shown (`reveal:<name>`, `tab:<name>`, `stuck`, `library`, ...).
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

  /// "Unlock anyway" on a locked tab or section: [r] opens now (its tip is not needed).
  void openEarly(Reveal r) => _save(state.copyWith(early: {...state.early, r.name}, tips: {...state.tips, r.tipKey, if (r.tab != null) 'tab:${r.name}'}));

  /// Settings > Guided start. Turning it on keeps what the player has reached open and says
  /// nothing about it again.
  void setGuided(bool on) {
    final solved = ref.read(solvedCountProvider);
    final level = ref.read(profileProvider).value?.level ?? 1;
    final reached = [for (final r in Reveal.values) if (solved >= r.solves && level >= r.level) r];
    _save(state.copyWith(
      guided: on || state.guided,
      showEverything: !on,
      early: on ? const {} : state.early,
      tips: on ? {...state.tips, for (final r in reached) r.tipKey, for (final r in reached) 'tab:${r.name}'} : state.tips,
    ));
  }

  void sawTip(String key) {
    if (state.tips.contains(key)) return;
    _save(state.copyWith(tips: {...state.tips, key}));
  }

  /// A Home tip was closed: it and every earlier one are done (a player who jumps ahead hears
  /// only the newest).
  void sawReveal(Reveal r) => _save(state.copyWith(tips: {...state.tips, for (final o in Reveal.values) if (o.index <= r.index) o.tipKey}));
}

final firstStepsProvider = NotifierProvider<FirstStepsNotifier, FirstSteps>(FirstStepsNotifier.new);

/// What the guided start keeps back until the player is ready for it, in the order it opens.
/// Pictures solved and the level both count; a 3x3 Cards board gives about 50 XP, so level 3 comes
/// after about 5 pictures, level 4 after 8 and level 5 after 12 (fewer on bigger boards).
enum Reveal {
  dailyGift(solves: 1, label: 'Daily gift', blurb: 'A gift every day you play, bigger with your streak.', tip: 'New on Home: a daily gift. Open it each day you play; it grows with your streak.'),
  quickPlay(solves: 3, label: 'Quick play'),
  packs(solves: 2, label: 'Packs on Home', plural: true, blurb: 'Your packs, new packs and the daily months.', tip: 'Home now shows your packs, new packs and the daily months.'),
  quests(solves: 2, label: 'Quests', plural: true, tab: 2, blurb: 'Small daily and weekly goals that pay coins.', tip: 'Quests are open: small daily and weekly goals that pay coins.', action: 'Open Quests', route: '/events'),
  wheelPiggy(level: 3, label: 'Lucky Wheel and piggy bank', blurb: 'Spin for coins, and save a few with every picture.', tip: 'New on Home: the Lucky Wheel, and a piggy bank that fills a little with every picture.'),
  saveProgress(level: 3, label: 'Save your progress'),
  social(level: 4, label: 'Social', tab: 3, blurb: 'A weekly league, friends and messages from Carden.', tip: 'Social is open: a weekly league, friends and messages from Carden.', action: 'Open Social', route: '/social'),
  achievements(level: 5, label: 'Achievements', plural: true, blurb: 'Goals across all your play, each with a reward.', tip: 'Achievements are open on your Profile, each with a reward to claim.', action: 'Open Profile', route: '/profile'),
  promos(level: 5, label: 'Store offers', plural: true);

  const Reveal({this.solves = 0, this.level = 1, required this.label, this.plural = false, this.blurb = '', this.tip = '', this.tab, this.action, this.route});

  /// Pictures solved, and level, it waits for.
  final int solves;
  final int level;
  final String label;
  final bool plural;

  /// What it is, in one line (the Home list of what is to come, the locked tab's alert).
  final String blurb;

  /// Said once on Home when it opens ('' for nothing to say).
  final String tip;

  /// Its tab in the tab bar (Quests 2, Social 3), when it is one.
  final int? tab;

  /// The tip's button and where it goes.
  final String? action;
  final String? route;

  /// Listed under "More opens as you play".
  bool get listed => blurb.isNotEmpty;

  /// When it opens, as the alerts and the list say it.
  String get when => solves > 0 ? (solves == 1 ? 'after your first picture' : 'after $solves pictures') : 'at level $level';

  /// "Quests open after 2 pictures", "Social opens at level 4".
  String get opensTitle => '$label ${plural ? 'open' : 'opens'} $when';

  /// The chip in the list of what is to come.
  String get short => solves > 0 ? (solves == 1 ? 'First picture' : '$solves pictures') : 'Level $level';

  String get tipKey => 'reveal:$name';
}

/// Pictures the player has finished (local progress, so a first solve counts at once).
final solvedCountProvider = Provider<int>((ref) {
  final rows = ref.watch(progressProvider).value ?? const <String, PuzzleProgress>{};
  return rows.values.where((p) => p.completed).length;
});

/// Is [r] open? Always, unless the guided start applies and the player has not reached it.
bool revealOpen(Reveal r, {required FirstSteps steps, required int solved, required int level}) =>
    !steps.calm || steps.early.contains(r.name) || solved >= r.solves && level >= r.level;

final revealsProvider = Provider<Set<Reveal>>((ref) {
  final steps = ref.watch(firstStepsProvider);
  final solved = ref.watch(solvedCountProvider);
  final level = ref.watch(profileProvider.select((p) => p.value?.level ?? 1));
  return {for (final r in Reveal.values) if (revealOpen(r, steps: steps, solved: solved, level: level)) r};
});

/// What is still to come, in the order it opens ("More opens as you play" on Home).
final upcomingRevealsProvider = Provider<List<Reveal>>((ref) {
  final open = ref.watch(revealsProvider);
  return [for (final r in Reveal.values) if (!open.contains(r) && r.listed) r];
});

/// The newest thing that opened by playing and has not been announced. A player far past it
/// (a returning account) is not told about it.
final pendingRevealTipProvider = Provider<Reveal?>((ref) {
  final steps = ref.watch(firstStepsProvider);
  if (!steps.calm) return null;
  final open = ref.watch(revealsProvider);
  final solved = ref.watch(solvedCountProvider);
  final level = ref.watch(profileProvider.select((p) => p.value?.level ?? 1));
  for (final r in Reveal.values.reversed) {
    if (!open.contains(r) || r.tip.isEmpty || steps.early.contains(r.name)) continue;
    if (steps.tips.contains(r.tipKey)) return null;
    final stale = r.solves > 0 ? solved > r.solves + 3 : level > r.level + 1;
    return stale ? null : r;
  }
  return null;
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
