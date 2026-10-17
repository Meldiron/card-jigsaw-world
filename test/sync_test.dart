// The save sync between a player's devices (an iPhone and the web site, say), against an
// in-memory server that applies Appwrite's operators the way the live backend does.
import 'dart:convert';

import 'package:appwrite/models.dart' as models;
import 'package:carden/data/sync/notice.dart';
import 'package:carden/data/sync/ops.dart';
import 'package:carden/features/sync/sync_host.dart';
import 'package:carden/models/models.dart';
import 'package:carden/state/profile.dart';
import 'package:carden/state/rewards.dart';
import 'package:carden/state/sync.dart';
import 'package:carden/state/unlocks.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_sync.dart';

Goal _quest(String suffix, {int coins = 60}) =>
    Goal(key: 'd:${Goals.dayKey(DateTime.now())}:$suffix', title: 'Quest', progress: 3, target: 3, coins: coins, icon: 'puzzle');

Future<(FakeServer, Device, Device)> _twoDevices() async {
  final server = FakeServer();
  final user = testUser('player1');
  final phone = await Device(server, user).open();
  final laptop = await Device(server, user).open();
  addTearDown(phone.close);
  addTearDown(laptop.close);
  return (server, phone, laptop);
}

void main() {
  test('coins earned and spent on two devices add up instead of overwriting each other', () async {
    final (server, phone, laptop) = await _twoDevices();
    expect(phone.me.coins, 500);
    await phone.profile.addCoins(300, reason: 'test');
    await phone.settle();
    // The laptop still shows 500 and spends from there.
    expect(laptop.me.coins, 500);
    expect(await laptop.profile.spendCoins(75, reason: 'peek'), isTrue);
    await laptop.settle();
    expect(server.profiles['player1']!['coins'], 725, reason: '500 + 300 - 75');
    await phone.resume();
    await laptop.resume();
    expect(phone.me.coins, 725);
    expect(laptop.me.coins, 725);
  });

  test('Peeks and Magic won on one device are in stock on the other and used before coins', () async {
    final (server, phone, laptop) = await _twoDevices();
    await phone.profile.addPeeks(5, reason: 'wheel');
    await phone.profile.addMagics(1, reason: 'wheel');
    await phone.settle();
    expect(server.profiles['player1']!['peeks'], 5);
    expect(server.profiles['player1']!['magics'], 1);
    expect(server.ledger.values.where((l) => l['currency'] == 'peeks' || l['currency'] == 'magics'), isEmpty, reason: 'the ledger records money only');
    // The laptop has not seen them yet: its Peek is paid in coins.
    expect(await laptop.profile.usePeek(), isTrue);
    await laptop.settle();
    expect(server.profiles['player1']!['coins'], 500 - Economy.peekCostCoins);
    await laptop.resume();
    expect(laptop.me.peeks, 5);
    expect(laptop.me.magics, 1);
    // Now the stock goes first and the coins stay.
    expect(await laptop.profile.usePeek(), isTrue);
    expect(await laptop.profile.useMagic(), isTrue);
    expect(laptop.me.peeks, 4);
    expect(laptop.me.magics, 0);
    await laptop.settle();
    final row = server.profiles['player1']!;
    expect(row['peeks'], 4);
    expect(row['magics'], 0);
    expect(row['coins'], 500 - Economy.peekCostCoins);
    // Out of Magic: the next one costs coins again.
    expect(await laptop.profile.useMagic(), isTrue);
    await laptop.settle();
    expect(server.profiles['player1']!['coins'], 500 - Economy.peekCostCoins - Economy.magicLockCostCoins);
    await phone.resume();
    expect(phone.me.peeks, 4);
  });

  test('a pack unlocked on one device is not lost when the other unlocks a different one', () async {
    final (server, phone, laptop) = await _twoDevices();
    final mountains = Pack.fromRow('mountains', {'name': 'Mountains', 'priceCoins': 200});
    final clocks = Pack.fromRow('clocks', {'name': 'Clocks', 'priceCoins': 100});
    expect(await phone.profile.unlockPack(mountains), isTrue);
    expect(await laptop.profile.unlockPack(clocks), isTrue);
    await phone.settle();
    await laptop.settle();
    final row = server.profiles['player1']!;
    expect(row['unlockedPacks'], containsAll(['mountains', 'clocks']));
    expect(row['coins'], 200);
  });

  test('play without a connection is kept on the device and sent later, also after a restart', () async {
    final server = FakeServer();
    final user = testUser('player2');
    final phone = await Device(server, user).open();
    phone.backend.online = false;
    await phone.profile.addCoins(120, reason: 'test');
    phone.progress.complete('pic1', gridSize: 16, mode: 'cards', moves: 30, seconds: 90, hints: 0, stars: 2, session: 's1', resumed: false);
    await phone.profile.recordCompletion(puzzleId: 'pic1', cells: 16, stars: 2, firstTime: true);
    await phone.settle();
    expect(phone.me.coins, greaterThan(620));
    expect(phone.rows['pic1']!.completed, isTrue);
    expect(server.profiles['player2']!['coins'], 500, reason: 'nothing reached the server');
    final shown = phone.me.coins;
    phone.close();

    // The app is closed and opened again, still offline: the queued play is still there.
    final again = Device(server, user, prefs: phone.prefs);
    again.backend.online = false;
    await again.open();
    addTearDown(again.close);
    expect(again.me.coins, shown);
    expect(again.rows['pic1']!.completed, isTrue);

    again.backend.online = true;
    await again.resume();
    expect(server.profiles['player2']!['coins'], shown);
    expect(server.progressOf('player2', 'pic1')!['completed'], isTrue);
    expect(again.sync.debugOps, isEmpty);
    expect(server.ledger.values.where((l) => l['reason'] == 'complete'), hasLength(1));
  });

  test('a quest claimed on both devices pays once and says so', () async {
    final (server, phone, laptop) = await _twoDevices();
    final quest = _quest('solve3');
    laptop.backend.online = false;
    expect(await phone.profile.claimGoal(quest), isTrue);
    expect(await laptop.profile.claimGoal(quest), isTrue, reason: 'the laptop has not heard of it yet');
    await phone.settle();
    laptop.backend.online = true;
    await laptop.resume();
    final row = server.profiles['player1']!;
    expect(row['coins'], 560);
    expect(row['questsCompleted'], 1);
    final notice = laptop.container.read(syncNoticeProvider);
    expect(notice.skipped, [SkipReason.questClaimed]);
    expect(laptop.me.coins, 560);
  });

  test('a lost answer does not apply a change twice', () async {
    final (server, phone, _) = await _twoDevices();
    phone.backend.loseNextAnswer = true;
    await phone.profile.addCoins(100, reason: 'test');
    await phone.settle();
    expect(server.profiles['player1']!['coins'], 600, reason: 'the server applied it');
    expect(phone.sync.debugOps, isNotEmpty, reason: 'the device does not know');
    await phone.resume();
    expect(server.profiles['player1']!['coins'], 600);
    expect(phone.me.coins, 600);
    expect(phone.sync.debugOps, isEmpty);
  });

  test('what another device did shows once, with what changed', () async {
    final (_, phone, laptop) = await _twoDevices();
    phone.container.read(syncNoticeProvider.notifier).take();
    await laptop.profile.claimDaily();
    laptop.progress.complete('pic9', gridSize: 16, mode: 'cards', moves: 20, seconds: 60, hints: 0, stars: 3, session: 'l1', resumed: false);
    await laptop.profile.recordCompletion(puzzleId: 'pic9', cells: 16, stars: 3, firstTime: true);
    await laptop.settle();
    expect(phone.container.read(syncNoticeProvider).isEmpty, isTrue);
    await phone.resume();
    final notice = phone.container.read(syncNoticeProvider);
    expect(notice.coins, greaterThan(50));
    expect(notice.solved, 1);
    expect(notice.dailyStreak, 1);
    final lines = syncNoticeLines(notice).map((l) => l.text).toList();
    expect(lines.first, startsWith('+'));
    expect(lines, contains('1 picture solved'));
    expect(lines, contains('Daily gift claimed · Streak: 1 day'));
    // Its own changes never show.
    expect(laptop.container.read(syncNoticeProvider).isEmpty, isTrue);
  });

  test('records only improve: a worse solve elsewhere never lowers stars, and pays as a replay', () async {
    final (server, phone, laptop) = await _twoDevices();
    laptop.progress.complete('pic3', gridSize: 16, mode: 'cards', moves: 18, seconds: 50, hints: 0, stars: 3, session: 'l1', resumed: false);
    await laptop.profile.recordCompletion(puzzleId: 'pic3', cells: 16, stars: 3, firstTime: true);
    await laptop.settle();
    // The phone has not synced and believes this is a first solve.
    phone.backend.online = false;
    phone.progress.complete('pic3', gridSize: 16, mode: 'cards', moves: 40, seconds: 120, hints: 1, stars: 1, session: 'p1', resumed: false);
    await phone.profile.recordCompletion(puzzleId: 'pic3', cells: 16, stars: 1, firstTime: true);
    await phone.settle();
    phone.backend.online = true;
    await phone.resume();
    final row = server.progressOf('player1', 'pic3')!;
    expect(row['completed'], isTrue);
    expect(row['stars'], 3);
    expect(row['bestMoves'], 18);
    expect(row['bestSeconds'], 50);
    expect(server.profiles['player1']!['puzzlesCompleted'], 1, reason: 'one picture, solved first on the laptop');
    expect(phone.rows['pic3']!.stars, 3);
  });

  test('two different boards of one picture: the player picks, and the choice sticks', () async {
    for (final pick in BoardChoice.values) {
      final (server, phone, laptop) = await _twoDevices();
      phone.backend.online = false;
      phone.progress.saveBoard('pic5', gridSize: 16, mode: 'cards', layout: [1, 0, 2, 3], moves: 4, seconds: 20, hints: 0, session: 'phone', resumed: false);
      laptop.progress.saveBoard('pic5', gridSize: 16, mode: 'squares', layout: [3, 2, 1, 0], moves: 9, seconds: 40, hints: 0, session: 'laptop', resumed: false);
      await laptop.settle();
      BoardConflict? asked;
      phone.sync.resolver = (c) async {
        asked = c;
        return pick;
      };
      phone.backend.online = true;
      await phone.resume();
      expect(asked, isNotNull);
      expect(asked!.device.moves, 4);
      expect(asked!.other.moves, 9);
      final row = server.progressOf('player1', 'pic5')!;
      expect(row['layout'], pick == BoardChoice.device ? '1,0,2,3' : '3,2,1,0');
      expect(phone.rows['pic5']!.layout, pick == BoardChoice.device ? [1, 0, 2, 3] : [3, 2, 1, 0]);
      expect(row['totalMoves'], pick == BoardChoice.device ? 13 : 9, reason: 'both play-throughs count when both boards were played');
    }
  });

  test('the laptop going on with the same board updates an open game without a question', () async {
    final (_, phone, laptop) = await _twoDevices();
    phone.progress.saveBoard('pic6', gridSize: 16, mode: 'cards', layout: [1, 0, 2, 3], moves: 4, seconds: 20, hints: 0, session: 'run1', resumed: false);
    await phone.settle();
    await laptop.resume();
    laptop.progress.saveBoard('pic6', gridSize: 16, mode: 'cards', layout: [0, 1, 3, 2], moves: 7, seconds: 33, hints: 0, session: 'run1', resumed: true);
    await laptop.settle();
    final updates = <BoardUpdate>[];
    final sub = phone.sync.boardUpdates.listen(updates.add);
    addTearDown(sub.cancel);
    var asked = false;
    phone.sync.resolver = (c) async {
      asked = true;
      return BoardChoice.device;
    };
    await phone.resume();
    expect(asked, isFalse);
    expect(updates.single.continued, isTrue);
    expect(phone.rows['pic6']!.moves, 7);
  });

  // A giant board played on the laptop, finished on the phone, then the laptop's tab (still open on
  // the old board) saved it again: the win must stay, and the open game must hear it was solved.
  Future<(FakeServer, Device, Device)> finishedOnPhone() async {
    final (server, phone, laptop) = await _twoDevices();
    laptop.progress.saveBoard('giant', gridSize: 195, mode: 'cards', layout: [1, 0, 2, 3], moves: 344, seconds: 9000, hints: 0, session: 'run', resumed: false);
    await laptop.settle();
    await phone.resume();
    phone.progress.saveBoard('giant', gridSize: 195, mode: 'cards', layout: [0, 1, 3, 2], moves: 400, seconds: 15000, hints: 0, session: 'run', resumed: true);
    phone.progress.complete('giant', gridSize: 195, mode: 'cards', moves: 468, seconds: 20869, hints: 0, stars: 3, session: 'run', resumed: true);
    await phone.settle();
    expect(server.progressOf('player1', 'giant')!['layout'], '');
    return (server, phone, laptop);
  }

  void expectWinKept(FakeServer server, Device laptop) {
    final row = server.progressOf('player1', 'giant')!;
    expect(row['layout'], '', reason: 'the old board must not come back over the win');
    expect(row['completed'], isTrue);
    expect(row['moves'], 468);
    expect(row['elapsedSeconds'], 20869);
    expect(row['totalMoves'], 468);
    expect(row['totalSeconds'], 20869);
    expect(row['bestMoves'], 468);
    expect(laptop.rows['giant']!.inProgress, isFalse, reason: 'Home must not offer Continue on a solved picture');
    expect(laptop.rows['giant']!.completed, isTrue);
  }

  test('a board finished on another device never comes back from a device that has read the save', () async {
    final (server, phone, laptop) = await finishedOnPhone();
    final updates = <BoardUpdate>[];
    final sub = laptop.sync.boardUpdates.listen(updates.add);
    addTearDown(sub.cancel);
    await laptop.resume();
    expect(updates.single.after.completed, isTrue, reason: 'the open game hears its board was solved');
    expect(updates.single.after.session, 'run');
    expect(updates.single.after.inProgress, isFalse);
    // The tab loses the focus: the game would save its old board.
    laptop.progress.saveBoard('giant', gridSize: 195, mode: 'cards', layout: [1, 0, 2, 3], moves: 344, seconds: 25872, hints: 0, session: 'run', resumed: true);
    expect(laptop.rows['giant']!.inProgress, isFalse, reason: 'the unsent save already shows as nothing');
    await laptop.settle();
    expect(laptop.sync.debugOps, isEmpty);
    expectWinKept(server, laptop);
  });

  test('a device that has not heard from the server for a while reads the save before saving a board', () async {
    final (server, phone, laptop) = await finishedOnPhone();
    // Time has passed since the laptop last read or wrote the row (a tab left open, a reconnect).
    SyncController.boardFreshFor = Duration.zero;
    addTearDown(() => SyncController.boardFreshFor = const Duration(seconds: 30));
    final updates = <BoardUpdate>[];
    final sub = laptop.sync.boardUpdates.listen(updates.add);
    addTearDown(sub.cancel);
    laptop.progress.saveBoard('giant', gridSize: 195, mode: 'cards', layout: [1, 0, 2, 3], moves: 344, seconds: 25872, hints: 0, session: 'run', resumed: true);
    await laptop.settle();
    expect(laptop.sync.debugOps, isEmpty);
    expectWinKept(server, laptop);
    expect(updates.single.after.completed, isTrue);
  });

  test('a new play-through of a solved picture still saves its board', () async {
    final (server, _, laptop) = await finishedOnPhone();
    await laptop.resume();
    laptop.progress.saveBoard('giant', gridSize: 195, mode: 'cards', layout: [3, 2, 1, 0], moves: 12, seconds: 60, hints: 0, session: 'replay', resumed: false);
    await laptop.settle();
    final row = server.progressOf('player1', 'giant')!;
    expect(row['layout'], '3,2,1,0');
    expect(row['completed'], isTrue);
    expect(row['bestMoves'], 468);
    expect(row['totalMoves'], 468 + 12, reason: 'a replay adds to the picture totals');
    expect(laptop.rows['giant']!.inProgress, isTrue);
  });

  test("today's daily gift claimed on both devices pays once", () async {
    final (server, phone, laptop) = await _twoDevices();
    laptop.backend.online = false;
    await phone.profile.claimDaily();
    await laptop.profile.claimDaily();
    await phone.settle();
    laptop.backend.online = true;
    await laptop.resume();
    expect(server.profiles['player1']!['coins'], 550);
    expect(server.profiles['player1']!['streak'], 1);
    expect(laptop.container.read(syncNoticeProvider).skipped, contains(SkipReason.dailyClaimed));
  });

  test('a level reached on both devices pays its reward once', () async {
    final server = FakeServer();
    final user = testUser('player3');
    server.profiles['player3'] = server.write(null, {'userId': 'player3', 'coins': 500, 'tickets': 3, 'hints': 3, 'xp': 50, 'level': 1}, 'player3');
    final phone = await Device(server, user).open();
    final laptop = await Device(server, user).open();
    addTearDown(phone.close);
    addTearDown(laptop.close);
    final solveCoins = Economy.completionCoins(16, 3), solveXp = Economy.completionXp(16, 3);
    expect(LevelRewards.levelForXp(50 + solveXp), 2, reason: 'one solve crosses into level 2');
    expect(LevelRewards.levelForXp(50 + 2 * solveXp), 2, reason: 'two solves stay in level 2');
    laptop.backend.online = false;
    var levelUps = 0;
    for (final (d, pid) in [(phone, 'lv1'), (laptop, 'lv2')]) {
      d.progress.complete(pid, gridSize: 16, mode: 'cards', moves: 10, seconds: 10, hints: 0, stars: 3, session: pid, resumed: false);
      final r = await d.profile.recordCompletion(puzzleId: pid, cells: 16, stars: 3, firstTime: true);
      if (r.levelUp) levelUps++;
    }
    expect(levelUps, 2, reason: 'each device saw the level-up on its own');
    await phone.settle();
    laptop.backend.online = true;
    await laptop.resume();
    final row = server.profiles['player3']!;
    expect(row['xp'], 50 + 2 * solveXp);
    expect(row['level'], 2);
    expect(row['coins'], 500 + 2 * solveCoins + LevelRewards.forLevel(2).coins);
    expect(row['hints'], 3 + LevelRewards.forLevel(2).hints);
  });

  test('a device that started offline without an account hands its play to its first guest', () async {
    final server = FakeServer();
    final prefs = FakePrefs();
    final offline = await Device(server, null, prefs: prefs).open();
    await offline.profile.addCoins(40, reason: 'test');
    await offline.settle();
    expect(offline.me.coins, 540);
    offline.close();
    final online = await Device(server, testUser('guest7'), prefs: prefs).open();
    addTearDown(online.close);
    expect(server.profiles['guest7']!['coins'], 540);
    expect(online.me.coins, 540);
  });

  test('duplicates from two devices appending the same key are tidied', () async {
    final (server, phone, _) = await _twoDevices();
    server.profiles['player1'] = {...server.profiles['player1']!, 'unlockedAvatars': ['owl', 'owl', 'cat']};
    await phone.resume();
    expect(server.profiles['player1']!['unlockedAvatars'], ['owl', 'cat']);
    expect(phone.me.unlockedAvatars, ['owl', 'cat']);
  });

  test('a win whose answer was lost still counts as the first solve', () async {
    final (server, phone, _) = await _twoDevices();
    phone.backend.loseNextAnswer = true;
    phone.progress.complete('pic7', gridSize: 16, mode: 'cards', moves: 20, seconds: 60, hints: 0, stars: 3, session: 's7', resumed: false);
    await phone.profile.recordCompletion(puzzleId: 'pic7', cells: 16, stars: 3, firstTime: true);
    await phone.settle();
    await phone.resume();
    final row = server.profiles['player1']!;
    expect(row['puzzlesCompleted'], 1);
    expect(row['coins'], 500 + Economy.completionCoins(16, 3));
  });

  test('a restart after everything was sent shows no notice for this device\'s own play', () async {
    final server = FakeServer();
    final user = testUser('player4');
    final phone = await Device(server, user).open();
    await phone.profile.addCoins(300, reason: 'test');
    phone.progress.complete('pic8', gridSize: 16, mode: 'cards', moves: 20, seconds: 60, hints: 0, stars: 3, session: 's8', resumed: false);
    await phone.settle();
    expect(phone.sync.debugOps, isEmpty);
    phone.close();
    final again = await Device(server, user, prefs: phone.prefs).open();
    addTearDown(again.close);
    await again.resume();
    expect(again.container.read(syncNoticeProvider).isEmpty, isTrue);
  });

  test("this device's own writes never hide another device's rows from the next read", () async {
    final (_, phone, laptop) = await _twoDevices();
    laptop.progress.complete('lx', gridSize: 16, mode: 'cards', moves: 20, seconds: 60, hints: 0, stars: 2, session: 'l', resumed: false);
    await laptop.settle();
    phone.progress.saveBoard('py', gridSize: 16, mode: 'cards', layout: [1, 0, 2, 3], moves: 1, seconds: 5, hints: 0, session: 'p', resumed: false);
    await phone.settle();
    await phone.resume();
    expect(phone.rows['lx']?.completed, isTrue);
  });

  test('two saves of its own board (an answer lost, then offline play) never ask the player', () async {
    final (_, phone, _) = await _twoDevices();
    var asked = false;
    phone.sync.resolver = (c) async {
      asked = true;
      return BoardChoice.device;
    };
    phone.backend.loseNextAnswer = true;
    phone.progress.saveBoard('pz', gridSize: 16, mode: 'cards', layout: [1, 0, 2, 3], moves: 1, seconds: 5, hints: 0, session: 'p', resumed: false);
    await phone.settle();
    phone.backend.online = false;
    phone.progress.saveBoard('pz', gridSize: 16, mode: 'cards', layout: [0, 1, 3, 2], moves: 2, seconds: 9, hints: 0, session: 'p', resumed: false);
    await phone.settle();
    phone.backend.online = true;
    await phone.resume();
    expect(asked, isFalse);
    expect(phone.rows['pz']!.moves, 2);
  });

  test('a quiet read that fails stays quiet when it is retried (a purchase on this device)', () async {
    final (server, phone, _) = await _twoDevices();
    phone.backend.online = false;
    server.profiles['player1'] = {...server.profiles['player1']!, 'coins': 3000};
    await phone.sync.sync(silent: true);
    phone.backend.online = true;
    await phone.sync.flush();
    await phone.settle();
    expect(phone.me.coins, 3000);
    expect(phone.container.read(syncNoticeProvider).isEmpty, isTrue);
  });

  test('an unlock the balance can no longer pay for is undone and explained', () async {
    final (server, phone, laptop) = await _twoDevices();
    final a = Pack.fromRow('pa', {'name': 'A', 'priceCoins': 400});
    final b = Pack.fromRow('pb', {'name': 'B', 'priceCoins': 400});
    phone.backend.online = false;
    expect(await laptop.profile.unlockPack(a), isTrue);
    expect(await phone.profile.unlockPack(b), isTrue);
    await laptop.settle();
    phone.backend.online = true;
    await phone.resume();
    final row = server.profiles['player1']!;
    expect(row['unlockedPacks'], ['pa']);
    expect(row['coins'], 100);
    expect(phone.me.unlockedPacks, ['pa']);
    expect(phone.container.read(syncNoticeProvider).skipped, [SkipReason.notEnough]);
  });

  test('giant boards opened early: one payment for the pack and the wait, open on every device', () async {
    final server = FakeServer();
    final user = testUser('player-giant');
    final houses = Pack.fromRow('houses', {'name': 'Colourful Houses', 'category': 'Giant', 'priceTickets': 12, 'imageCount': 24});
    final phone = await Device(server, user, packs: [houses]).open();
    final laptop = await Device(server, user, packs: [houses]).open();
    addTearDown(phone.close);
    addTearDown(laptop.close);
    await phone.profile.addTickets(30, reason: 'test');
    await phone.settle();
    final before = server.profiles['player-giant']!['tickets'] as int;
    final level = phone.me.level;
    expect(level, lessThan(Unlock.giant.level));
    expect(phone.container.read(openFeaturesProvider).giant, isFalse);
    final price = 12 + Economy.giantEarlyFee(level);
    expect(phone.profile.giantEarlyPrice(houses), price);

    expect(await phone.profile.openGiantEarly(houses), isTrue);
    expect(phone.container.read(openFeaturesProvider).giant, isTrue, reason: 'open on this device at once');
    expect(phone.profile.isUnlocked(houses), isTrue);
    await phone.settle();
    final row = server.profiles['player-giant']!;
    expect(row['tickets'], before - price);
    expect(row['unlockedPacks'], contains('houses'));
    expect(row['unlockedTiers'], contains(Unlocks.earlyKey(Unlock.giant)));
    final spent = server.ledger.values.where((l) => l['currency'] == 'tickets' && (l['amount'] as num) < 0).map((l) => (l['reason'], l['amount'])).toList();
    expect(spent, containsAll([('unlock:houses', -12), (Unlocks.earlyKey(Unlock.giant), -Economy.giantEarlyFee(level))]));

    await laptop.resume();
    expect(laptop.container.read(openFeaturesProvider).giant, isTrue);
    // Paid once: nothing is left to pay for this pack.
    expect(laptop.profile.giantEarlyPrice(houses), 0);
  });

  test('a piggy bank upgrade bought on both devices is paid once, and the size follows the player', () async {
    final (server, phone, laptop) = await _twoDevices();
    await phone.profile.addCoins(12000, reason: 'test');
    await phone.settle();
    await laptop.resume();
    laptop.container.read(syncNoticeProvider.notifier).take();
    laptop.backend.online = false;
    expect(await phone.profile.upgradePiggy(), isTrue);
    expect(phone.me.piggyCapacity, 600, reason: 'bigger on this device at once');
    expect(phone.me.coins, 12500 - Economy.piggyUpgradeCoins);
    expect(await laptop.profile.upgradePiggy(), isTrue, reason: 'the laptop has not heard of it yet');
    await phone.settle();
    laptop.backend.online = true;
    await laptop.resume();
    final row = server.profiles['player1']!;
    expect(row['piggyLevel'], 1);
    expect(row['coins'], 12500 - Economy.piggyUpgradeCoins, reason: 'paid once');
    expect(server.ledger.values.where((l) => l['reason'] == 'piggy-upgrade:1').map((l) => l['amount']), [-Economy.piggyUpgradeCoins]);
    expect(laptop.me.piggyCapacity, 600);
    expect(laptop.me.coins, 12500 - Economy.piggyUpgradeCoins);
    expect(laptop.container.read(syncNoticeProvider).skipped, [SkipReason.piggyUpgraded]);
    // The phone hears of the laptop's next upgrade.
    phone.container.read(syncNoticeProvider.notifier).take();
    expect(await laptop.profile.upgradePiggy(), isTrue);
    await laptop.settle();
    await phone.resume();
    final notice = phone.container.read(syncNoticeProvider);
    expect(notice.piggyCapacity, 700);
    expect(syncNoticeLines(notice).map((l) => l.text), contains('Piggy bank upgraded · holds 700'));
  });

  test('an upgraded piggy bank fills to its new size, and five upgrades are the most', () async {
    final (server, phone, _) = await _twoDevices();
    await phone.profile.addCoins(30000, reason: 'test');
    await phone.settle();
    for (var i = 1; i <= Profile.maxPiggyLevel; i++) {
      expect(await phone.profile.upgradePiggy(), isTrue, reason: 'upgrade $i');
    }
    expect(await phone.profile.upgradePiggy(), isFalse, reason: 'not offered past 1,000');
    await phone.settle();
    expect(server.profiles['player1']!['piggyLevel'], 5);
    expect(phone.me.piggyCapacity, 1000);
    expect(server.profiles['player1']!['coins'], 30500 - 5 * Economy.piggyUpgradeCoins);
    // An op that asks past the largest size raises nothing and charges nothing.
    phone.sync.enqueue(SyncOp.piggyUpgrade(level: 6, price: Economy.piggyUpgradeCoins));
    await phone.settle();
    expect(server.profiles['player1']!['piggyLevel'], 5);
    expect(server.profiles['player1']!['coins'], 30500 - 5 * Economy.piggyUpgradeCoins);

    server.profiles['player1']!['piggyCoins'] = 995;
    await phone.resume();
    for (final pid in ['pg1', 'pg2']) {
      phone.progress.complete(pid, gridSize: 16, mode: 'cards', moves: 10, seconds: 10, hints: 0, stars: 3, session: pid, resumed: false);
      await phone.profile.recordCompletion(puzzleId: pid, cells: 16, stars: 3, firstTime: true);
    }
    await phone.settle();
    expect(server.profiles['player1']!['piggyCoins'], 1000, reason: '995 + 5, then full: past 500 since the upgrades');
    expect(phone.me.piggyFull, isTrue);
  });

  test('an upgrade the coins can no longer pay for is undone', () async {
    final (server, phone, laptop) = await _twoDevices();
    await phone.profile.addCoins(Economy.piggyUpgradeCoins - 500, reason: 'test');
    await phone.settle();
    await laptop.resume();
    phone.backend.online = false;
    expect(await phone.profile.upgradePiggy(), isTrue);
    expect(await laptop.profile.spendCoins(4000, reason: 'test'), isTrue);
    await laptop.settle();
    phone.backend.online = true;
    await phone.resume();
    expect(server.profiles['player1']!['piggyLevel'] ?? 0, 0);
    expect(phone.me.piggyCapacity, Profile.basePiggyCapacity);
    expect(phone.container.read(syncNoticeProvider).skipped, [SkipReason.notEnough]);
  });

  test('an event step whose answer was lost counts once', () async {
    final (server, phone, _) = await _twoDevices();
    phone.backend.loseNextAnswer = true;
    phone.sync.enqueue(SyncOp.event('ev1'));
    await phone.settle();
    await phone.resume();
    expect(server.events.values.single['progress'], 1);
  });

  test('the player this device last saw is remembered for an offline start', () {
    final user = testUser('player9', email: 'a@b.c');
    final back = models.User.fromMap(Map<String, dynamic>.from(jsonDecode(jsonEncode(user.toMap())) as Map));
    expect(back.$id, 'player9');
    expect(back.email, 'a@b.c');
  });

  test('notice lines read calmly and name what changed', () {
    const n = SyncNotice(coins: 1200, tickets: -1, hints: 1, peeks: 5, magics: -1, level: 7, solved: 3, betterStars: 1, boards: ['a', 'b'], packs: ['m'], quests: 2, skipped: [SkipReason.unlocked]);
    expect(syncNoticeLines(n, packNames: {'m': 'Mountains'}).map((l) => l.text), [
      '+1,200 Coins',
      '−1 Ticket',
      '+1 Hint',
      '+5 Peeks',
      '−1 Magic',
      'Level 7',
      '3 pictures solved',
      'More stars on 1 picture',
      'Boards in progress on 2 pictures',
      'Unlocked: Mountains',
      '2 quests claimed',
      'Already unlocked there, nothing charged',
    ]);
  });
}
