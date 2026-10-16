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
    expect(c.read(upcomingRevealsProvider), isEmpty);
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
    const s = FirstSteps(guided: true, showEverything: false, firstBoard: false, tips: {'stuck', 'tab:quests'}, early: {'social'});
    final back = FirstSteps.fromJson(s.toJson());
    expect((back.guided, back.showEverything, back.firstBoard), (true, false, false));
    expect(back.tips, {'stuck', 'tab:quests'});
    expect(back.early, {'social'});
  });

  test('the owner\'s schedule: each thing opens after a number of pictures solved', () {
    expect({for (final r in Reveal.values) r.name: r.solves}, {
      'packs': 2,
      'quickPlay': 3,
      'daily': 5,
      'saveProgress': 5,
      'streak': 10,
      'wheel': 15,
      'quests': 20,
      'promos': 20,
      'achievements': 25,
      'piggy': 30,
      'liveEvents': 35,
      'social': 50,
    });
  });

  test('a new player starts with only the basics; Home and the tabs grow with pictures solved', () async {
    Future<Set<Reveal>> at(int solved) async => (await container(prefs: guided, solved: solved)).read(revealsProvider);
    expect(await at(0), isEmpty);
    expect(await at(1), isEmpty);
    expect(await at(2), {Reveal.packs});
    expect(await at(5), {Reveal.packs, Reveal.quickPlay, Reveal.daily, Reveal.saveProgress});
    expect((await at(10)).contains(Reveal.streak), isTrue);
    expect((await at(19)).containsAll({Reveal.wheel}) && !(await at(19)).contains(Reveal.quests), isTrue);
    expect((await at(49)).contains(Reveal.social), isFalse);
    expect(await at(50), Reveal.values.toSet());
    // The level does not count: a level-12 player with 3 pictures still waits for the daily puzzle.
    expect((await container(prefs: guided, solved: 3, level: 12)).read(revealsProvider).contains(Reveal.daily), isFalse);
  });

  test('Unlock anyway opens one tab or section, or everything from Home', () async {
    final c = await container(prefs: guided);
    c.read(firstStepsProvider.notifier).openEarly(Reveal.social);
    expect(c.read(revealsProvider), {Reveal.social});
    expect(c.read(newTabsProvider), isEmpty, reason: 'opened by the player: no "new" dot');
    expect(c.read(upcomingRevealsProvider).contains(Reveal.social), isFalse);
    c.read(firstStepsProvider.notifier).showEverything();
    expect(c.read(revealsProvider), Reveal.values.toSet());
    expect(c.read(upcomingRevealsProvider), isEmpty);
  });

  test('Settings > Guided start back on keeps what the player reached, with no "new" dots', () async {
    final c = await container(prefs: {'firstSteps': '{"guided":true,"showEverything":true}'}, solved: 22);
    c.read(firstStepsProvider.notifier).setGuided(true);
    expect(c.read(firstStepsProvider).calm, isTrue);
    expect(c.read(revealsProvider).containsAll({Reveal.daily, Reveal.streak, Reveal.wheel, Reveal.quests}), isTrue);
    expect(c.read(revealsProvider).contains(Reveal.achievements), isFalse);
    expect(c.read(newTabsProvider), isEmpty);
  });

  test('a tab that opens by playing keeps a dot until it is visited', () async {
    final c = await container(prefs: guided, solved: 20);
    expect(c.read(newTabsProvider), {Reveal.quests.tab});
    c.read(firstStepsProvider.notifier).sawTip('tab:quests');
    expect(c.read(newTabsProvider), isEmpty);
  });

  test('the list of what is to come shows the nearest first', () async {
    final c = await container(prefs: guided, solved: 1);
    expect(c.read(upcomingRevealsProvider).take(4), [Reveal.packs, Reveal.daily, Reveal.streak, Reveal.wheel]);
  });

  test('alerts and the list say when each thing opens', () {
    expect(Reveal.quests.opensTitle, 'Quests open after 20 pictures');
    expect(Reveal.social.opensTitle, 'Social opens after 50 pictures');
    expect(Reveal.daily.opensTitle, 'Daily puzzle opens after 5 pictures');
    expect(Reveal.liveEvents.short, '35 pictures');
    expect([for (final r in Reveal.values) if (r.listed) r.name], ['packs', 'daily', 'streak', 'wheel', 'quests', 'achievements', 'piggy', 'liveEvents', 'social']);
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
