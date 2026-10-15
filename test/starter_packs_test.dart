// Six starter packs are free since 2026-10-14; the library packs that were free before are priced,
// but a player who had played one keeps it open (lib/state/starter_packs.dart).
import 'package:carden/models/models.dart';
import 'package:carden/state/starter_packs.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/fake_sync.dart';

Pack _pack(String id, {bool free = false, int coins = 2400}) =>
    Pack.fromRow(id, {'name': id, 'category': 'Nature', 'imageCount': 2, 'isFree': free, 'priceCoins': free ? 0 : coins});

Puzzle _puzzle(String id, String packId) => Puzzle.fromRow(id, {'packId': packId, 'title': id, 'imageUrl': 'https://example.invalid/$id.jpg'});

void main() {
  test('the formerly free list never names a starter pack', () {
    const starters = {'wild-nature', 'pack-butterflies', 'pack-paris', 'pack-fruit-markets', 'pack-impressionists', 'pack-tropical-beaches'};
    expect(formerlyFreePacks.intersection(starters), isEmpty);
    expect(formerlyFreePacks, hasLength(45));
    expect(keptFreePack('pack-owls', () => {'pack-owls'}), isTrue);
    expect(keptFreePack('pack-owls', () => const {}), isFalse);
    expect(keptFreePack('pack-new-paid', () => {'pack-new-paid'}), isFalse, reason: 'only packs that were free before');
    expect(keptFreePack('pack-new-paid', () => throw StateError('read')), isFalse, reason: 'other packs never read the progress');
  });

  test('a formerly free pack stays open for a player who played it, and only for them', () async {
    final starter = _pack('wild-nature', free: true);
    final owls = _pack('pack-owls'); // free until 2026-10-14
    final deer = _pack('pack-deer'); // free until 2026-10-14, never played here
    final paid = _pack('pack-clocks'); // always paid
    final packs = [starter, owls, deer, paid];
    final puzzles = [_puzzle('owl1', 'pack-owls'), _puzzle('deer1', 'pack-deer'), _puzzle('clock1', 'pack-clocks'), _puzzle('wn1', 'wild-nature')];
    final server = FakeServer();
    final phone = await Device(server, testUser('player1'), packs: packs, puzzles: puzzles).open();
    addTearDown(phone.close);

    expect(phone.profile.isUnlocked(starter), isTrue);
    expect(phone.profile.isUnlocked(owls), isFalse);
    expect(phone.profile.isUnlocked(paid), isFalse);

    // Played before the change: the saved board makes the pack stay open.
    phone.progress.complete('owl1', gridSize: 16, mode: 'cards', moves: 20, seconds: 60, hints: 0, stars: 3, session: 's1', resumed: false);
    phone.progress.complete('clock1', gridSize: 16, mode: 'cards', moves: 20, seconds: 60, hints: 0, stars: 3, session: 's2', resumed: false);
    await phone.settle();
    expect(phone.container.read(playedPacksProvider), containsAll(['pack-owls', 'pack-clocks']));
    expect(phone.profile.isUnlocked(owls), isTrue);
    expect(phone.profile.isUnlocked(deer), isFalse, reason: 'never played');
    expect(phone.profile.isUnlocked(paid), isFalse, reason: 'progress alone never opens a pack that was always paid');
  });
}
