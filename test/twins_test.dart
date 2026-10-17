import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:carden/core/theme/app_theme.dart';
import 'package:carden/features/game/board_widget.dart';
import 'package:carden/game/board.dart';
import 'package:carden/game/game_controller.dart';
import 'package:carden/game/gather.dart';
import 'package:carden/game/twins.dart';
import 'package:carden/state/settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Twin cards (docs/twins.md): the measure on synthetic pictures, the identity swap on place and
/// on join and its limits, the deal, Shuffle and Gather around twins, determinism and speed.
void main() {
  /// A picture of [w] x [h] pixels painted by [colour].
  TwinPicture paint(int w, int h, (int, int, int) Function(int x, int y) colour) {
    final px = Uint8List(w * h * 4);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final (r, g, b) = colour(x, y);
        final i = (y * w + x) * 4;
        px[i] = r.clamp(0, 255);
        px[i + 1] = g.clamp(0, 255);
        px[i + 2] = b.clamp(0, 255);
        px[i + 3] = 255;
      }
    }
    return TwinPicture(w, h, px);
  }

  const sky = (96, 148, 222);
  const cards4 = GridSpec(4, 4, 'Relaxed');
  // A 4x4 Cards board on a 500 x 700 picture: cards of 125 x 175 pixels.
  const w4 = 500, h4 = 700;
  ({int x, int y, int w, int h}) cell(int card) => (x: card % 4 * 125, y: card ~/ 4 * 175, w: 125, h: 175);

  group('the measure', () {
    test('identical plain patches are twins', () {
      final twins = TwinFinder(paint(w4, h4, (_, _) => sky), cards4).find();
      expect(twins.classes, [List.generate(16, (i) => i)]);
    });

    test('a faint cloud, a thin line or a speck keeps a card apart', () {
      // Card 5: a soft cloud, a little lighter at its heart (about 3 just-noticeable differences).
      // Card 6: a faint one-pixel wire across it. Card 9: a bird of two by two pixels.
      final c5 = cell(5), c6 = cell(6), c9 = cell(9);
      final picture = paint(w4, h4, (x, y) {
        var (r, g, b) = sky;
        final dx = x - (c5.x + 60), dy = y - (c5.y + 80);
        final cloud = (9 * exp(-(dx * dx + dy * dy) / (2 * 22.0 * 22.0))).round();
        r += cloud;
        g += cloud;
        b += cloud;
        if (x >= c6.x && x < c6.x + c6.w && y == c6.y + 30 + (x - c6.x) ~/ 2) {
          r -= 14;
          g -= 14;
          b -= 14;
        }
        if (x >= c9.x + 70 && x < c9.x + 72 && y >= c9.y + 90 && y < c9.y + 92) {
          r -= 60;
          g -= 60;
          b -= 60;
        }
        return (r, g, b);
      });
      final twins = TwinFinder(picture, cards4).find();
      for (final apart in [5, 6, 9]) {
        for (var c = 0; c < 16; c++) {
          if (c != apart) expect(twins.same(apart, c), isFalse, reason: 'card $apart is not a twin of card $c');
        }
      }
      // The other cards are still one class.
      final rest = [for (var c = 0; c < 16; c++) if (c != 5 && c != 6 && c != 9) c];
      expect(twins.classes, [rest]);
    });

    test('the grain of a photo does not keep alike cards apart', () {
      final rng = Random(3);
      final picture = paint(w4, h4, (_, _) {
        final n = rng.nextInt(7) - 3;
        return (sky.$1 + n, sky.$2 + n, sky.$3 + n);
      });
      final twins = TwinFinder(picture, cards4).find();
      expect(twins.cards, greaterThanOrEqualTo(14), reason: 'grain alone leaves the plain cards twins');
    });

    test('a gradient: cards of one row are twins, cards of different rows are not', () {
      final twins = TwinFinder(paint(w4, h4, (_, y) => (60 + y ~/ 6, 110 + y ~/ 6, 200 + y ~/ 12)), cards4).find();
      expect(twins.classes, [
        for (var r = 0; r < 4; r++) [for (var c = 0; c < 4; c++) r * 4 + c],
      ]);
    });

    test('only cards of the same shape can be twins', () {
      for (final spec in [BoardSpec.squareTiers(GameMode.triangles)[1], BoardSpec.squareTiers(GameMode.hexagons).first]) {
        final tiling = spec.tiling;
        final twins = TwinFinder(paint(700, 600, (_, _) => sky), spec).find();
        expect(twins.isEmpty, isFalse);
        for (final k in twins.classes) {
          expect(k.map(tiling.classOf).toSet(), hasLength(1), reason: '${spec.fullCode}: a class holds one shape');
        }
        // Every shape that occurs twice on a plain picture is a class of its own.
        final shapes = <int, int>{};
        for (var s = 0; s < spec.cells; s++) {
          shapes[tiling.classOf(s)] = (shapes[tiling.classOf(s)] ?? 0) + 1;
        }
        expect(twins.classCount, shapes.values.where((n) => n >= 2).length, reason: spec.fullCode);
      }
    });

    // A night sky as a phone photo has it (owner, TestFlight build 124: "Top right corner is all
    // black, as the picture is"): near black, a reddish cast, sensor noise and JPEG blocks of
    // chroma, a few faint single-pixel stars.
    (int, int, int) night(int x, int y, Random rng) {
      final n = rng.nextInt(5) - 2;
      // 8 x 8 blocks of slightly different chroma, as JPEG leaves them in the dark.
      final block = ((x ~/ 8) * 7 + (y ~/ 8) * 13) % 5 - 2;
      final star = (x * 31 + y * 17) % 997 == 0 ? 30 : 0;
      return (7 + n + block + star, 4 + n + star, 3 + n - block ~/ 2 + star);
    }

    test('near-black cards with noise, chroma blocks and faint stars are twins', () {
      final rng = Random(11);
      final twins = TwinFinder(paint(w4, h4, (x, y) => night(x, y, rng)), cards4).find();
      expect(twins.cards, 16, reason: 'every card of a plain night sky');
    });

    test('in the dark, a star, a lamp, a light trail or a faint structure still keeps a card apart', () {
      final rng = Random(12);
      final c1 = cell(1), c6 = cell(6), c9 = cell(9), c14 = cell(14);
      final picture = paint(w4, h4, (x, y) {
        var (r, g, b) = night(x, y, rng);
        // Card 1: a star that shows (2 x 2 pixels).
        if (x >= c1.x + 40 && x < c1.x + 42 && y >= c1.y + 50 && y < c1.y + 52) (r, g, b) = (150, 150, 140);
        // Card 6: a thin red light trail across it.
        if (x >= c6.x && x < c6.x + c6.w && y == c6.y + 60 + (x - c6.x) ~/ 3) (r, g, b) = (110, 25, 15);
        // Card 9: a small lit window.
        if (x >= c9.x + 60 && x < c9.x + 66 && y >= c9.y + 80 && y < c9.y + 88) (r, g, b) = (200, 160, 60);
        // Card 14: a faint lattice, dark grey bars on the black.
        if (x >= c14.x && x < c14.x + c14.w && y >= c14.y && y < c14.y + c14.h && ((x - c14.x) % 24 < 3 || (y - c14.y) % 24 < 3)) {
          (r, g, b) = (r + 14, g + 13, b + 12);
        }
        return (r, g, b);
      });
      final twins = TwinFinder(picture, cards4).find();
      for (final apart in [1, 6, 9, 14]) {
        for (var c = 0; c < 16; c++) {
          if (c != apart) expect(twins.same(apart, c), isFalse, reason: 'card $apart is not a twin of card $c');
        }
      }
      expect(twins.cards, 12, reason: 'the other twelve stay twins');
    });

    test('near white, pale cards a hair apart in tone are twins; a speck on white is not', () {
      final c5 = cell(5);
      // A frosty sky: near white with a faint blue cast, a slow gradient and JPEG banding.
      final picture = paint(w4, h4, (x, y) {
        final band = (y ~/ 6) % 3 - 1;
        var (r, g, b) = (236 + band - y ~/ 260, 238 + band - y ~/ 260, 247 + band);
        if (x >= c5.x + 50 && x < c5.x + 52 && y >= c5.y + 70 && y < c5.y + 72) (r, g, b) = (120, 120, 125);
        return (r, g, b);
      });
      final twins = TwinFinder(picture, cards4).find();
      for (var c = 0; c < 16; c++) {
        if (c != 5) expect(twins.same(5, c), isFalse, reason: 'card 5 has a speck');
      }
      expect(twins.cards, greaterThanOrEqualTo(12), reason: 'the pale cards are twins');
    });

    test('the same picture gives the same twins every time', () {
      final rng = Random(8);
      final noise = List.generate(w4 * h4, (_) => rng.nextInt(5) - 2);
      TwinPicture picture() => paint(w4, h4, (x, y) => (sky.$1 + noise[y * w4 + x], sky.$2 + noise[y * w4 + x], sky.$3 + y ~/ 70));
      final a = TwinFinder(picture(), cards4).find(), b = TwinFinder(picture(), cards4).find();
      expect(a.classes, b.classes);
    });
  });

  group('the identity swap', () {
    // A 4x4 board dealt back to front: no card in place, no pair joined.
    List<int> reversed() => List.generate(16, (s) => 15 - s);

    test('a card dropped on its twin\'s place counts as placed', () {
      final twins = Twins.fromClasses(16, [
        [0, 1],
      ]);
      final before = Board(cards4, reversed());
      expect(before.lockedCount, 0);
      expect(before.joinCount, 0);
      // Card 1 (slot 14) goes to card 0's place.
      final moved = before.moveTo(14, 0)!;
      expect(moved.isLocked(0), isFalse);
      final settled = twins.settle(before, moved);
      expect(settled.board.isLocked(0), isTrue, reason: 'slot 0 holds card 0 now');
      expect(settled.swaps, [(0, 1)]);
      // Card 0 was at slot 15: card 1 takes its place there, and nothing else changes.
      expect(settled.board.slots[15], 1);
      for (var s = 1; s < 15; s++) {
        expect(settled.board.slots[s], moved.slots[s]);
      }
      expect(settled.board.lockedCount, 1);
    });

    test('a card put where its twin would join a neighbour joins', () {
      final twins = Twins.fromClasses(16, [
        [5, 6],
      ]);
      final layout = reversed();
      // Card 2 to slot 3 (card 12 to slot 13).
      layout[3] = 2;
      layout[13] = 12;
      final before = Board(cards4, layout);
      expect(before.lockedCount, 0);
      expect(before.joinCount, 0);
      // Card 5 (slot 10) goes under card 2: card 6 belongs there.
      final moved = before.moveTo(10, 7)!;
      expect(moved.joined(3, 7), isFalse);
      final settled = twins.settle(before, moved);
      expect(settled.swaps, [(6, 5)]);
      expect(settled.board.slots[7], 6);
      expect(settled.board.joined(3, 7), isTrue, reason: 'card 6 under card 2 joins');
      expect(settled.board.slots[9], 5, reason: 'card 5 is where card 6 was');
      expect(settled.board.lockedCount, 0);
    });

    test('the neighbour can be the one that takes its twin\'s identity', () {
      final twins = Twins.fromClasses(16, [
        [1, 2],
      ]);
      final layout = reversed();
      // Card 1 to slot 3 (card 12 to slot 14).
      layout[3] = 1;
      layout[14] = 12;
      final before = Board(cards4, layout);
      expect(before.lockedCount, 0);
      expect(before.joinCount, 0);
      // Card 6 (slot 9) goes under card 1: card 6 has no twin, but card 1's twin 2 belongs above it.
      final moved = before.moveTo(9, 7)!;
      final settled = twins.settle(before, moved);
      expect(settled.swaps, [(2, 1)]);
      expect(settled.board.slots[3], 2, reason: 'the neighbour took its twin\'s identity');
      expect(settled.board.joined(3, 7), isTrue);
      expect(settled.board.slots[13], 1, reason: 'card 1 is where card 2 was');
    });

    test('never a card in place or in a joined group', () {
      final twins = Twins.fromClasses(16, [
        [5, 6],
      ]);
      final layout = reversed();
      layout[3] = 2;
      layout[13] = 12;
      // Card 6 (slot 9) joined to card 7 on its right (slot 10); card 5 to slot 12, card 3 to slot 8.
      layout[10] = 7;
      layout[12] = 5;
      layout[8] = 3;
      final before = Board(cards4, layout);
      expect(before.joined(9, 10), isTrue);
      expect(before.joinCount, 1);
      expect(before.lockedCount, 0);
      // Card 5 goes under card 2: its twin 6 would join there, but 6 is in a group.
      final moved = before.moveTo(12, 7)!;
      final settled = twins.settle(before, moved);
      expect(settled.swaps, isEmpty);
      expect(settled.board.slots, moved.slots);

      // A card that arrives in a group keeps its identity: card 1 above card 5 (joined) on slots
      // 0 and 4, card 1 on card 0's place.
      final placed = Twins.fromClasses(16, [
        [0, 1],
      ]);
      final l2 = reversed();
      l2[0] = 1;
      l2[4] = 5;
      l2[14] = 11;
      l2[10] = 15;
      final b2 = Board(cards4, l2);
      expect(b2.joined(0, 4), isTrue);
      expect(b2.joinCount, 1);
      final s2 = placed.settle(Board(cards4, reversed()), b2);
      expect(s2.swaps, isEmpty);
      expect(s2.board.isLocked(0), isFalse, reason: 'card 1 is in a group');

      // A card in place never trades: card 0 locked, card 1 dropped next to card 2's left... on
      // slot 1 it would lock itself; on slot 4 (under card 0) its twin would not join (0 is above 4).
      final l3 = reversed();
      l3[0] = 0;
      l3[15] = 15;
      final b3 = Board(cards4, l3);
      expect(b3.isLocked(0) && b3.isLocked(15), isTrue);
      final m3 = b3.moveTo(b3.slotOfCard(1), 1)!;
      final s3 = placed.settle(b3, m3);
      expect(s3.board.slots[0], 0);
      expect(s3.board.isLocked(1), isTrue, reason: 'card 1 on its own place, nothing to trade');
      expect(s3.swaps, isEmpty);
    });

    test('a twin already looking in place where it waits counts as placed too', () {
      final twins = Twins.fromClasses(16, [
        [0, 1],
      ]);
      final layout = reversed();
      // Card 0 waits on slot 1 (card 1's place, so it looks in place there); card 14 to slot 15.
      layout[1] = 0;
      layout[15] = 14;
      final before = Board(cards4, layout);
      expect(before.lockedCount, 0);
      expect(before.joinCount, 0);
      // Card 1 goes to card 0's place: the two trade identities and both are in place.
      final moved = before.moveTo(before.slotOfCard(1), 0)!;
      final settled = twins.settle(before, moved);
      expect(settled.board.isLocked(0) && settled.board.isLocked(1), isTrue);
      expect(settled.swaps, [(0, 1)]);
    });

    test('a board on which every card looks in place is finished', () {
      final twins = Twins.fromClasses(16, [
        [0, 1],
        [4, 5],
      ]);
      // Cards 1 above 5 and 0 above 4, each pair joined: two groups, both on their twins' places.
      final layout = List.generate(16, (i) => i);
      layout[0] = 1;
      layout[1] = 0;
      layout[4] = 5;
      layout[5] = 4;
      final after = Board(cards4, layout);
      expect(after.isSolved, isFalse);
      final settled = twins.settle(Board(cards4, reversed()), after);
      expect(settled.board.isSolved, isTrue);
    });

    test('settling is deterministic', () {
      final rng = Random(4);
      final spec = BoardSpec.squareTiers(GameMode.triangles)[2];
      final classes = <List<int>>[];
      final tiling = spec.tiling;
      final byShape = <int, List<int>>{};
      for (var s = 0; s < spec.cells; s++) {
        (byShape[tiling.classOf(s)] ??= []).add(s);
      }
      for (final shape in byShape.values.where((v) => v.length >= 8)) {
        classes.add((shape.toList()..shuffle(rng)).take(shape.length ~/ 3).toList());
      }
      final twins = Twins.fromClasses(spec.cells, classes);
      var b = Board.shuffled(spec, seed: 6, twins: twins);
      for (var i = 0; i < 40; i++) {
        final from = rng.nextInt(b.cells), to = rng.nextInt(b.cells);
        final moved = b.moveTo(from, to);
        if (moved == null) continue;
        final one = twins.settle(b, moved), two = twins.settle(b, moved);
        expect(one.board.slots, two.board.slots);
        expect(one.swaps, two.swaps);
        expect(Board.isValidLayout(spec, one.board.slots), isTrue);
        // Nothing the player built changes: every card in place stays in place.
        for (var s = 0; s < b.cells; s++) {
          if (moved.isLocked(s)) expect(one.board.isLocked(s), isTrue);
        }
        b = one.board;
      }
    });
  });

  /// Twin classes over about a third of every shape, none over half of it.
  Twins someTwins(BoardSpec spec, int seed) {
    final rng = Random(seed);
    final tiling = spec.tiling;
    final byShape = <int, List<int>>{};
    for (var s = 0; s < spec.cells; s++) {
      (byShape[tiling.classOf(s)] ??= []).add(s);
    }
    final classes = <List<int>>[];
    for (final shape in byShape.values) {
      final pool = shape.toList()..shuffle(rng);
      var left = shape.length ~/ 3;
      while (left >= 2) {
        final n = min(left, 2 + rng.nextInt(4));
        classes.add(pool.sublist(0, n));
        pool.removeRange(0, n);
        left -= n;
      }
    }
    return Twins.fromClasses(spec.cells, classes);
  }

  int looksPlaced(Board b, Twins twins) => [for (var s = 0; s < b.cells; s++) if (twins.looksPlaced(b.slots[s], s)) s].length;
  int looksJoined(Board b, Twins twins) {
    var n = 0;
    for (var s = 0; s < b.cells; s++) {
      for (final t in b.tiling.neighbours(s)) {
        if (t > s && twins.looksJoined(b.tiling, s, b.slots[s], t, b.slots[t])) n++;
      }
    }
    return n;
  }

  group('the deal, Shuffle and Gather', () {
    final specs = [
      for (final m in GameMode.values) ...BoardSpec.squareTiers(m),
      for (final m in GameMode.values) BoardSpec.squareGiantTiers(m).first,
    ];

    test('the deal puts no card on a twin\'s place and no pair where a twin would join', () {
      for (final spec in specs) {
        for (var seed = 0; seed < 3; seed++) {
          final twins = someTwins(spec, seed);
          final b = Board.shuffled(spec, seed: seed, twins: twins);
          expect(Board.isValidLayout(spec, b.slots), isTrue);
          expect(looksPlaced(b, twins), 0, reason: '${spec.fullCode} seed $seed');
          expect(looksJoined(b, twins), lessThanOrEqualTo(spec.tiling.unavoidableJoins), reason: '${spec.fullCode} seed $seed');
        }
      }
    });

    test('a twin class over half of its shape: the card it forces onto a twin\'s place starts in place', () {
      final spec = BoardSpec.squareTiers(GameMode.cards).first; // 3x3
      final twins = Twins.fromClasses(9, [
        [0, 1, 2, 3, 4, 5],
      ]);
      final b = Board.shuffled(spec, seed: 2, twins: twins);
      expect(Board.isValidLayout(spec, b.slots), isTrue);
      for (var s = 0; s < 9; s++) {
        if (twins.looksPlaced(b.slots[s], s)) expect(b.isLocked(s), isTrue, reason: 'slot $s looks in place, so it is');
      }
      expect(b.lockedCount, greaterThan(0));
    });

    test('Shuffle moves no card onto a twin\'s place or next to a twin\'s join', () {
      for (final spec in specs) {
        final twins = someTwins(spec, 1);
        final b = Board.shuffled(spec, seed: 5, twins: twins);
        final after = shuffleLoose(b, random: Random(7), twins: twins);
        expect(after, isNotNull, reason: spec.fullCode);
        for (var s = 0; s < b.cells; s++) {
          if (after!.slots[s] == b.slots[s]) continue;
          expect(twins.looksPlaced(after.slots[s], s), isFalse, reason: '${spec.fullCode} slot $s');
        }
        // Like Shuffle without twins: no pair joins where another order allows it. The small
        // classes of edge halves on triangle and honeycomb boards leave some orders forced (Shuffle
        // without twins keeps up to three pairs there too), so those boards are checked for places.
        final edgeHalves = spec.mode == GameMode.triangles || (spec.mode == GameMode.hexagons && !spec.isGiant);
        if (!edgeHalves) expect(looksJoined(after!, twins), 0, reason: spec.fullCode);
      }
    });

    test('Gather never puts a card on a twin\'s place', () {
      const size = Size(360, 480);
      for (final m in GameMode.values) {
        final spec = BoardSpec.squareGiantTiers(m).last;
        final twins = someTwins(spec, 2);
        final b = Board.shuffled(spec, seed: 3, twins: twins);
        final view = Rect.fromLTWH(90, 120, size.width / 3, size.height / 3);
        final after = gatherInto(b, view, size, twins: twins);
        expect(after, isNotNull);
        expect(canGather(b, view, size, twins: twins), isTrue);
        for (var s = 0; s < b.cells; s++) {
          if (after!.slots[s] != b.slots[s]) expect(twins.looksPlaced(after.slots[s], s), isFalse, reason: '${spec.fullCode} slot $s');
        }
      }
    });
  });

  group('in the game', () {
    test('a fresh board is dealt again with its twins; a drop on a twin\'s place locks and trades widgets', () {
      final spec = BoardSpec.squareTiers(GameMode.cards)[1]; // 4x4
      final twins = Twins.fromClasses(16, [
        [0, 1, 2, 3],
      ]);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      const args = GameArgs(puzzleId: 'p', spec: GridSpec(4, 4, 'Relaxed', tier: 2));
      expect(args.spec, spec);
      final ctrl = container.read(gameControllerProvider(args).notifier);
      container.listen(gameControllerProvider(args), (_, _) {});
      expect(ctrl.awaitsTwins, isTrue);
      ctrl.useTwins(twins);
      expect(ctrl.awaitsTwins, isFalse);
      var s = container.read(gameControllerProvider(args));
      expect(s.twins, same(twins));
      expect(looksPlaced(s.board, twins), 0);
      // Drop a top-row card on another top-row card's place (one where it does not join a true
      // neighbour on the way, which would make it part of a group).
      final b = s.board;
      late int from, target;
      search:
      for (from = 0; from < 16; from++) {
        if (b.slots[from] > 3) continue;
        for (target = 0; target < 4; target++) {
          final moved = target == b.slots[from] ? null : b.moveTo(from, target);
          if (moved != null && twins.settle(b, moved).board.isLocked(target)) break search;
        }
      }
      expect(from, lessThan(16), reason: 'some top-row card can go to another one\'s place');
      final dropped = b.slots[from];
      ctrl.drop(from, target);
      s = container.read(gameControllerProvider(args));
      expect(s.board.isLocked(target), isTrue);
      expect(s.justLocked, contains(target));
      expect(s.moves, 1);
      // The card that was dropped keeps its widget where it landed.
      expect(s.cardKeys, isNotNull);
      expect(s.cardKeys![target], dropped);
    });

    test('a resumed board keeps its cards where they are', () {
      final spec = BoardSpec.squareTiers(GameMode.cards)[1];
      final layout = List.generate(16, (s) => 15 - s);
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final args = GameArgs(puzzleId: 'p', spec: spec, layout: layout, moves: 4);
      final ctrl = container.read(gameControllerProvider(args).notifier);
      container.listen(gameControllerProvider(args), (_, _) {});
      expect(ctrl.awaitsTwins, isFalse);
      ctrl.useTwins(Twins.fromClasses(16, [
        [0, 1],
      ]));
      expect(container.read(gameControllerProvider(args)).board.slots, layout);
    });

    testWidgets('the dropped card stays where it landed on screen', (tester) async {
      final spec = BoardSpec.squareTiers(GameMode.cards)[1];
      final before = Board(spec, List.generate(16, (s) => 15 - s));
      final twins = Twins.fromClasses(16, [
        [0, 1],
      ]);
      final settled = twins.settle(before, before.moveTo(14, 0)!);
      final keys = List.generate(16, (i) => i);
      for (final (a, b) in settled.swaps) {
        final t = keys[a];
        keys[a] = keys[b];
        keys[b] = t;
      }
      final rec = ui.PictureRecorder();
      Canvas(rec).drawRect(const Rect.fromLTWH(0, 0, 250, 350), Paint()..color = const Color(0xFF6094DE));
      final image = rec.endRecording().toImageSync(250, 350);
      GameState state(Board b, List<int>? k) => GameState(
            board: b,
            par: 1,
            moves: 0,
            elapsed: 0,
            status: GameStatus.playing,
            selected: null,
            hintsUsed: 0,
            history: const [],
            justLocked: const {},
            justJoined: const {},
            hintSlot: null,
            hintTarget: null,
            peeking: false,
            chain: 0,
            tick: 0,
            cardKeys: k,
          );
      Widget board(GameState s) => MaterialApp(
            theme: AppTheme.light(),
            home: Center(
              child: BoardWidget(image: image, state: s, width: 250, height: 350, cardStyle: CardStyle.classic, onTap: (_) {}, onDrop: (_, _) {}),
            ),
          );
      await tester.pumpWidget(board(state(before, null)));
      final origin = tester.getTopLeft(find.byType(BoardWidget));
      expect(tester.getTopLeft(find.byKey(const ValueKey('card-1'))) - origin, spec.tiling.cellBounds(14, const Size(250, 350)).topLeft);
      await tester.pumpWidget(board(state(settled.board, keys)));
      await tester.pumpAndSettle();
      // Card 1's widget (the one dropped) is on slot 0, now showing card 0; card 0's widget stayed on slot 15.
      expect(tester.getTopLeft(find.byKey(const ValueKey('card-1'))) - origin, Offset.zero);
      expect(tester.getTopLeft(find.byKey(const ValueKey('card-0'))) - origin, spec.tiling.cellBounds(15, const Size(250, 350)).topLeft);
    });
  });

  group('speed', () {
    test('a 666-piece board is measured and dealt in time', () {
      final spec = BoardSpec.squareGiantTiers(GameMode.triangles).last;
      expect(spec.cells, 666);
      // A 2048 x 1900 picture: a plain sky with grain over the top third (more than a giant
      // picture may have, docs/content-rules.md), a busy pattern below.
      final rng = Random(1);
      final picture = paint(2048, 1900, (x, y) {
        final n = rng.nextInt(5) - 2;
        if (y < 650) return (sky.$1 + n, sky.$2 + n + y ~/ 200, sky.$3 + n);
        return ((x * 7 + y * 3) % 255, (x * 13 ^ y * 5) % 255, (x * y) % 251);
      });
      final watch = Stopwatch()..start();
      final finder = TwinFinder(picture, spec);
      final sampled = watch.elapsedMilliseconds;
      final twins = finder.find();
      final measured = watch.elapsedMilliseconds;
      // ignore: avoid_print
      print('sampled in ${sampled}ms, ${finder.candidates().length} candidate pairs');
      watch.reset();
      final b = Board.shuffled(spec, seed: 1, twins: twins);
      final dealt = watch.elapsedMilliseconds;
      // ignore: avoid_print
      print('666 pieces: ${twins.cards} twin cards in ${twins.classCount} classes, measured in ${measured}ms, dealt in ${dealt}ms');
      expect(twins.cards, greaterThan(100));
      expect(looksPlaced(b, twins), 0);
      // Debug-mode test run; the app's release build in an isolate is several times faster.
      expect(measured, lessThan(6000));
      expect(dealt, lessThan(3000));
    });
  });
}
