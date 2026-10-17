// Play together's screens without the game screen (lib/features/coop/): the player colours and their
// contrast, the players chip, the player list as host and guest, the guest's finish and the copy,
// at the SE size in both themes, with Increase contrast and at the Largest text size.
import 'dart:math' as math;

import 'package:carden/core/a11y.dart';
import 'package:carden/core/theme/app_theme.dart';
import 'package:carden/core/theme/tokens.dart';
import 'package:carden/features/coop/coop_alerts.dart';
import 'package:carden/features/coop/coop_players.dart';
import 'package:carden/features/coop/guest_finish.dart';
import 'package:carden/features/coop/players_sheet.dart';
import 'package:carden/features/coop/share_invite.dart';
import 'package:carden/models/models.dart';
import 'package:carden/state/coop/coop_controller.dart';
import 'package:carden/state/coop/coop_models.dart';
import 'package:carden/state/settings.dart';
import 'package:carden/state/social.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

double _luminance(Color c) {
  double f(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
}

double _ratio(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  return ((la > lb ? la : lb) + 0.05) / ((la > lb ? lb : la) + 0.05);
}

const _game = CoopGame(
  id: 'g1',
  code: 'K7QH2MXP',
  hostId: 'amy',
  players: ['amy', 'bob', '', 'cat', ''],
  removed: [],
  ended: false,
  board: 1,
  puzzleId: 'p1',
  grid: 'cards-4x5t3',
  painting: false,
  layout: [1, 0, 3, 2],
);

class _Fixed extends CoopController {
  _Fixed(this.fixed);
  final CoopState fixed;
  @override
  CoopState build() => fixed;
}

CoopState _state(String me) => CoopState(
      phase: CoopPhase.playing,
      game: _game,
      me: me,
      layout: _game.layout,
      presences: {
        for (final p in ['amy', 'bob']) p: CoopPresence(userId: p, gameId: 'g1', board: 1),
      },
    );

Profile _profile(String id, String name) => Profile.guest(id).copyWith(displayName: name);

const _names = {'amy': 'Amy Juniper-Wildflower', 'bob': 'Bob', 'cat': 'Catherine of the Long Name'};

Future<List<String>> _pump(WidgetTester tester, Widget child, {required String me, bool dark = false, Accessibility a11y = const Accessibility(), double scale = 1, Size size = const Size(375, 667)}) async {
  final errors = <String>[];
  final previous = FlutterError.onError;
  FlutterError.onError = (d) => errors.add(d.exceptionAsString().split('\n').first);
  addTearDown(() => FlutterError.onError = previous);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      coopProvider.overrideWith(() => _Fixed(_state(me))),
      playerProfileProvider.overrideWith((ref, id) async => _profile(id, _names[id] ?? 'Player')),
    ],
    child: MediaQuery(
      data: MediaQueryData(size: size, textScaler: TextScaler.linear(scale)),
      child: MaterialApp(
        theme: dark ? AppTheme.dark(highContrast: a11y.increaseContrast) : AppTheme.light(highContrast: a11y.increaseContrast),
        home: A11y(prefs: a11y, child: Scaffold(body: SafeArea(child: SingleChildScrollView(child: child)))),
      ),
    ),
  ));
  // The guest's finish has a spinner: pump for a while instead of waiting to settle.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  return errors;
}

void main() {
  group('player colours', () {
    test('four colours, never red or cobalt, readable in every theme', () {
      const boardsLight = [Color(0xFFFFFFFF), Color(0xFFF6F6F8), Color(0xFFECECF1)];
      const boardsDark = [Color(0xFF0D0D11), Color(0xFF15151A), Color(0xFF2A2A33), Color(0xFF1C1C22), Color(0xFF28282F)];
      for (final (palette, on, boards, text, outline) in [
        (PlayerColors.light, PlayerColors.onLight, boardsLight, 4.5, 3.0),
        (PlayerColors.dark, PlayerColors.onDark, boardsDark, 4.5, 3.0),
        (PlayerColors.lightContrast, PlayerColors.onLight, boardsLight, 6.0, 6.0),
        (PlayerColors.darkContrast, PlayerColors.onDark, boardsDark, 6.0, 6.0),
      ]) {
        expect(palette.length, PlayerColors.count);
        for (final c in palette) {
          expect(_ratio(c, on), greaterThanOrEqualTo(text), reason: 'the initial on $c');
          for (final b in boards) {
            expect(_ratio(c, b), greaterThanOrEqualTo(outline), reason: 'the outline $c on $b');
          }
          expect(c, isNot(Brand.accent));
          expect(c, isNot(Brand.danger));
        }
      }
    });

    test('every other player keeps one colour; four others, four colours', () {
      for (var mine = 0; mine < 5; mine++) {
        final others = [for (var s = 0; s < 5; s++) if (s != mine) coopColourIndex(s, mine)];
        expect(others.toSet(), {0, 1, 2, 3}, reason: 'seat $mine');
      }
      // Someone leaving does not move anyone else's colour: the index depends on seats only.
      expect(coopColourIndex(3, 0), coopColourIndex(3, 0));
    });

    test('seats in order, the host first, this player without a colour (cobalt)', () {
      final seats = coopSeats(_state('bob'));
      expect(seats.map((s) => s.userId), ['amy', 'bob', 'cat']);
      expect(seats.first.isHost, isTrue);
      expect(seats[1].isMe, isTrue);
      expect(seats[1].colour, isNull);
      expect(seats.last.here, isFalse, reason: 'no presence: away');
      expect(coopInitial('  bob'), 'B');
      expect(coopInitial(''), '?');
    });
  });

  group('copy', () {
    test('invite and alerts', () {
      expect(inviteText('Barn owl'), 'Play Barn owl with me in Carden');
      expect(inviteText(null), 'Play a picture with me in Carden');
      expect(_game.joinUrl.toString(), 'https://join.carden.page/K7QH2MXP');
      expect(endedMessage('host', 'Amy'), 'Amy ended the game for everyone.');
      expect(endedMessage('idle', 'Amy'), 'The game ended after a day without play.');
      for (final r in CoopRefusalReason.values) {
        final t = refusalText(CoopRefusal(r));
        expect(t.title, isNotEmpty);
        expect('${t.title} ${t.message}'.contains('!'), isFalse, reason: 'calm copy');
        expect('${t.title} ${t.message}'.toLowerCase().contains('lobby'), isFalse, reason: 'it is a game');
      }
    });
  });

  for (final dark in [false, true]) {
    for (final contrast in [false, true]) {
      for (final scale in [1.0, 2.0]) {
        final what = '${dark ? 'dark' : 'light'}${contrast ? ' contrast' : ''} text ${scale}x';
        final a11y = Accessibility(increaseContrast: contrast, differentiateWithoutColour: contrast);

        testWidgets('the host\'s player list: $what', (tester) async {
          final errors = await _pump(tester, const CoopPlayersPanel(), me: 'amy', dark: dark, a11y: a11y, scale: scale);
          expect(errors, isEmpty);
          expect(find.text('Players'), findsOneWidget);
          expect(find.text('3 of 5 playing this board'), findsOneWidget);
          expect(find.text('Remove'), findsNWidgets(2), reason: 'on each other player');
          expect(find.text('Invite'), findsOneWidget);
          expect(find.text('2 more players can join.'), findsOneWidget);
          expect(find.text('End game for everyone'), findsOneWidget);
          final label = tester.getRect(find.text('End game for everyone'));
          final row = tester.getRect(find.byKey(const ValueKey('coop-end')));
          expect(row.top <= label.top && label.bottom <= row.bottom, isTrue, reason: 'the label wraps inside its row, never cut');
          expect(find.text('Leave game'), findsNothing);
          expect(find.text('Host · You'), findsOneWidget);
          expect(find.text('Here'), findsOneWidget);
          expect(find.text('Away'), findsOneWidget);
        });

        testWidgets('a guest\'s player list and finish: $what', (tester) async {
          var errors = await _pump(tester, const CoopPlayersPanel(), me: 'bob', dark: dark, a11y: a11y, scale: scale);
          expect(errors, isEmpty);
          expect(find.text('Remove'), findsNothing);
          expect(find.text('Invite'), findsNothing);
          expect(find.text('Leave game'), findsOneWidget);
          expect(find.text('Host · Here'), findsOneWidget);
          errors = await _pump(tester, const Padding(padding: EdgeInsets.all(20), child: CoopGuestFinish()), me: 'bob', dark: dark, a11y: a11y, scale: scale);
          expect(errors, isEmpty);
          expect(find.text('Waiting for Amy Juniper-Wildflower to pick the next board'), findsOneWidget);
          expect(find.text('Leave game'), findsOneWidget);
        });
      }
    }
  }

  testWidgets('the players chip: people and a count, a button', (tester) async {
    final errors = await _pump(tester, const Center(child: CoopPlayersChip()), me: 'bob');
    expect(errors, isEmpty);
    expect(find.text('3'), findsOneWidget);
    expect(find.bySemanticsLabel('3 players. Show players'), findsOneWidget);
  });

  testWidgets('the player list asks before removing', (tester) async {
    await _pump(tester, Builder(builder: (context) => const CoopPlayersPanel()), me: 'amy');
    await tester.tap(find.byKey(const ValueKey('coop-remove-bob')));
    await tester.pumpAndSettle();
    expect(find.text('Remove Bob?'), findsOneWidget);
    expect(find.text('They leave the game and cannot join it again.'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('coop-end')));
    await tester.pumpAndSettle();
    expect(find.text('End game for everyone?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
  });

  testWidgets('a player card mark: the initial in the player\'s colour', (tester) async {
    final errors = await _pump(tester, const Center(child: PlayerInitialBadge(initial: 'B', color: Color(0xFFC2410C), onColor: Colors.white)), me: 'amy', scale: 2);
    expect(errors, isEmpty);
    final text = tester.widget<Text>(find.text('B'));
    expect(text.textScaler, TextScaler.noScaling, reason: 'a mark on a card keeps its size');
  });
}
