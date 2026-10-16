import 'package:carden/data/local_store.dart';
import 'package:carden/game/board.dart';
import 'package:carden/models/models.dart';
import 'package:carden/state/first_steps.dart';
import 'package:carden/state/profile.dart';
import 'package:carden/state/settings.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The guided start (owner, 2026-10-16; lib/state/first_steps.dart, docs/first-steps.md).
void main() {
  /// XP that reaches [level] on the level curve.
  int xpFor(int level) {
    var xp = 0;
    for (var l = 1; l < level; l++) {
      xp += Profile.xpForLevel(l);
    }
    return xp;
  }

  Future<ProviderContainer> container({Map<String, Object> prefs = const {}, int solved = 0, int level = 1}) async {
    SharedPreferences.setMockInitialValues(prefs);
    final store = await LocalStore.open();
    final c = ProviderContainer(overrides: [
      localStoreProvider.overrideWithValue(store),
      solvedCountProvider.overrideWith((ref) => solved),
      profileProvider.overrideWith(() => _Profile(xpFor(level))),
    ]);
    addTearDown(c.dispose);
    await c.read(profileProvider.future);
    return c;
  }

  const guided = {'firstSteps': '{"guided":true}'};

  test('players who started before have no record and see everything', () async {
    final c = await container();
    expect(c.read(firstStepsProvider).calm, isFalse);
    expect(c.read(revealsProvider), Reveal.values.toSet());
    expect(c.read(nextStepProvider), isNull);
    expect(c.read(pendingRevealTipProvider), isNull);
  });

  test('onboarding marks a new player once, and a device that already chose keeps its choice', () async {
    SharedPreferences.setMockInitialValues({});
    final store = await LocalStore.open();
    await FirstSteps.markNewPlayer(store);
    expect(FirstSteps.fromJson(store.getJson(FirstSteps.storeKey)).calm, isTrue);
    await store.setJson(FirstSteps.storeKey, const FirstSteps(guided: true, showEverything: true).toJson());
    await FirstSteps.markNewPlayer(store);
    expect(FirstSteps.fromJson(store.getJson(FirstSteps.storeKey)).calm, isFalse, reason: 'Unlock anyway is not undone by signing in later');
    await FirstSteps.skipFor(store);
    final skipped = FirstSteps.fromJson(store.getJson(FirstSteps.storeKey));
    expect((skipped.guided, skipped.firstBoard, store.tutorialSeen), (false, false, true));
  });

  test('the record survives a round trip', () {
    const s = FirstSteps(guided: true, showEverything: false, firstBoard: false, tips: {'stuck', 'reveal:quests'}, early: {'social'});
    final back = FirstSteps.fromJson(s.toJson());
    expect((back.guided, back.showEverything, back.firstBoard), (true, false, false));
    expect(back.tips, {'stuck', 'reveal:quests'});
    expect(back.early, {'social'});
  });

  test('a new player starts with only the basics; Home and the tabs grow with pictures and levels', () async {
    expect((await container(prefs: guided)).read(revealsProvider), isEmpty);
    expect((await container(prefs: guided, solved: 1)).read(revealsProvider), {Reveal.dailyGift});
    expect((await container(prefs: guided, solved: 2, level: 2)).read(revealsProvider), {Reveal.dailyGift, Reveal.packs, Reveal.quests});
    expect((await container(prefs: guided, solved: 3, level: 2)).read(revealsProvider).contains(Reveal.quickPlay), isTrue);
    final l3 = (await container(prefs: guided, solved: 5, level: 3)).read(revealsProvider);
    expect(l3.containsAll({Reveal.wheelPiggy, Reveal.saveProgress}), isTrue);
    expect(l3.contains(Reveal.social), isFalse);
    expect((await container(prefs: guided, solved: 8, level: 4)).read(revealsProvider).contains(Reveal.social), isTrue);
    expect((await container(prefs: guided, solved: 12, level: 5)).read(revealsProvider), Reveal.values.toSet());
  });

  test('Unlock anyway opens one tab, or everything from Home', () async {
    final c = await container(prefs: guided);
    c.read(firstStepsProvider.notifier).openEarly(Reveal.social);
    expect(c.read(revealsProvider), {Reveal.social});
    expect(c.read(newTabsProvider), isEmpty, reason: 'opened by the player: no "new" dot');
    expect(c.read(upcomingRevealsProvider).contains(Reveal.social), isFalse);
    c.read(firstStepsProvider.notifier).showEverything();
    expect(c.read(revealsProvider), Reveal.values.toSet());
    expect(c.read(upcomingRevealsProvider), isEmpty);
    expect(c.read(pendingRevealTipProvider), isNull);
  });

  test('Settings > Guided start back on keeps what the player reached, with nothing announced again', () async {
    final c = await container(prefs: {'firstSteps': '{"guided":true,"showEverything":true}'}, solved: 3, level: 2);
    c.read(firstStepsProvider.notifier).setGuided(true);
    expect(c.read(firstStepsProvider).calm, isTrue);
    expect(c.read(revealsProvider), {Reveal.dailyGift, Reveal.quickPlay, Reveal.packs, Reveal.quests});
    expect(c.read(pendingRevealTipProvider), isNull);
    expect(c.read(newTabsProvider), isEmpty);
  });

  test('what just opened is said once, newest first, and never to a player far past it', () async {
    final c = await container(prefs: guided, solved: 2, level: 2);
    expect(c.read(pendingRevealTipProvider), Reveal.quests);
    expect(c.read(newTabsProvider), {Reveal.quests.tab});
    c.read(firstStepsProvider.notifier).sawReveal(Reveal.quests);
    expect(c.read(pendingRevealTipProvider), isNull, reason: 'closing the newest tip also settles the older ones');
    c.read(firstStepsProvider.notifier).sawTip('tab:quests');
    expect(c.read(newTabsProvider), isEmpty);
    // A returning account at level 12 on a new device: nothing to announce.
    expect((await container(prefs: guided, solved: 40, level: 12)).read(pendingRevealTipProvider), isNull);
  });

  test('alerts and the list say when each thing opens', () {
    expect(Reveal.quests.opensTitle, 'Quests open after 2 pictures');
    expect(Reveal.social.opensTitle, 'Social opens at level 4');
    expect(Reveal.dailyGift.opensTitle, 'Daily gift opens after your first picture');
    expect(Reveal.achievements.short, 'Level 5');
    expect(Reveal.dailyGift.short, 'First picture');
    expect([for (final r in Reveal.values) if (r.listed) r.name], ['dailyGift', 'packs', 'quests', 'wheelPiggy', 'social', 'achievements']);
    for (final r in Reveal.values.where((r) => r.listed)) {
      expect(r.tip, isNotEmpty, reason: '${r.name} is announced when it opens');
      expect(r.tip.contains('!'), isFalse, reason: 'calm copy');
    }
  });

  test('the first board is nine cards on Cards, the smallest board', () {
    expect(firstBoardSpec.cells, 9);
    expect(BoardCode.toPath(firstBoardSpec.fullCode), 'cards-3x3');
    final back = BoardSpec.fromCode(BoardCode.fromPath('cards-3x3'));
    expect((back.mode, back.cols, back.rows), (firstBoardSpec.mode, 3, 3));
  });
}

class _Profile extends ProfileNotifier {
  _Profile(this.xp);
  final int xp;

  @override
  Future<Profile> build() async => Profile.guest('u1').copyWith(xp: xp);
}
