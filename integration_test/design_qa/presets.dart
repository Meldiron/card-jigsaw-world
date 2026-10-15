// Design QA harness: players, saves and other people for the scenes. Not part of the app.
import 'dart:convert';
import 'dart:math';

import 'package:card_jigsaw_world/models/models.dart';
import 'package:card_jigsaw_world/state/rewards.dart';

/// Scene time: every scene runs "now", but rows are written relative to it.
DateTime get now => DateTime.now();
String iso(DateTime d) => d.toUtc().toIso8601String();
DateTime daysAgo(num d) => now.subtract(Duration(minutes: (d * 24 * 60).round()));

/// Profile row columns of a preset player (the save sync's profile row).
Map<String, dynamic> playerPreset(String name, String userId) {
  final base = <String, dynamic>{
    'userId': userId,
    'displayName': 'Player',
    'avatar': 'fox',
    'coins': 500,
    'tickets': 3,
    'hints': 3,
    'peeks': 0,
    'magics': 0,
    'xp': 0,
    'piggyCoins': 0,
    'streak': 0,
    'longestStreak': 0,
    'puzzlesCompleted': 0,
    'totalStars': 0,
    'isVip': false,
    'claimedGoals': <String>[],
    'claimedAchievements': <String>[],
    'unlockedPacks': <String>[],
    'unlockedTiers': <String>[],
    'unlockedAvatars': <String>[],
    'totalMoves': 0,
    'totalSeconds': 0,
    'questsCompleted': 0,
    'picturesSolved': 0,
    'picturesPerfect': 0,
    'packsCompleted': 0,
    'packsPerfect': 0,
  };
  switch (name) {
    case 'new':
      return base;
    case 'casual':
      return {
        ...base,
        'displayName': 'Mia',
        'avatar': 'leaf',
        'coins': 1240,
        'tickets': 4,
        'hints': 2,
        'peeks': 1,
        'xp': LevelRewards.xpToReach(5) + 120,
        'piggyCoins': 85,
        'streak': 3,
        'longestStreak': 6,
        'lastDailyClaim': iso(daysAgo(1)),
        'puzzlesCompleted': 17,
        'totalStars': 41,
        'totalMoves': 1830,
        'totalSeconds': 3 * 3600 + 1200,
        'solvedByMode': jsonEncode({'cards': 12, 'squares': 5}),
        'questsCompleted': 9,
        'picturesSolved': 17,
        'picturesPerfect': 8,
        'packsCompleted': 1,
        'packsPerfect': 0,
        'claimedAchievements': <String>[],
      };
    case 'veteran':
      return {
        ...base,
        'displayName': 'Eleanor',
        'avatar': 'star',
        'coins': 18450,
        'tickets': 27,
        'hints': 12,
        'peeks': 6,
        'magics': 4,
        'xp': LevelRewards.xpToReach(24) + 900,
        'piggyCoins': 500,
        'streak': 46,
        'longestStreak': 60,
        'lastDailyClaim': iso(daysAgo(1)),
        'isVip': true,
        'vipExpiresAt': iso(now.add(const Duration(days: 220))),
        'puzzlesCompleted': 412,
        'totalStars': 1170,
        'totalMoves': 61230,
        'totalSeconds': 141 * 3600,
        'solvedByMode': jsonEncode({'cards': 190, 'squares': 102, 'triangles': 64, 'hexagons': 56}),
        'questsCompleted': 214,
        'picturesSolved': 412,
        'picturesPerfect': 288,
        'packsCompleted': 23,
        'packsPerfect': 14,
      };
    case 'broke':
      return {
        ...playerPreset('casual', userId),
        'displayName': 'Sam',
        'coins': 0,
        'tickets': 0,
        'hints': 0,
        'peeks': 0,
        'piggyCoins': 500,
      };
    case 'longname':
      return {
        ...playerPreset('veteran', userId),
        'displayName': 'Maximilian Alexander von Habsburg',
        'coins': 1234567,
        'tickets': 999,
        'hints': 999,
        'streak': 365,
        'longestStreak': 365,
      };
  }
  throw ArgumentError('unknown player preset $name');
}

/// Other players for the league, around the viewer.
List<Profile> leaguePlayers(Profile? me, {int count = 60}) {
  const names = [
    'Ana', 'Ben', 'Chloé', 'Dmitri', 'Elif', 'Farah', 'Gabriel', 'Hana', 'Ivo', 'Jules', 'Kofi', 'Lena', 'Mateo', 'Noor', 'Oskar',
    'Priya', 'Quinn', 'Rosa', 'Sven', 'Tamsin', 'Umar', 'Vera', 'Wen', 'Xavier', 'Yara', 'Zofia', 'PuzzleQueen1987', 'Marguerite-Hélène',
    'Bartholomew Featherstonehaugh', 'Li', 'Oluwaseun', 'Ngozi', 'Søren', 'Agnieszka', 'Tomasz', 'Kenji', 'Aiko', 'Rafael', 'Inês', 'Matej',
  ];
  const avatars = ['fox', 'leaf', 'drop', 'star'];
  final rnd = Random(7);
  final out = <Profile>[];
  for (var i = 0; i < count; i++) {
    final xp = (60000 * pow(0.93, i)).round() + rnd.nextInt(40);
    out.add(Profile.fromRow('player-$i', {
      'userId': 'player-$i',
      'displayName': names[i % names.length],
      'avatar': avatars[i % avatars.length],
      'xp': xp,
      'puzzlesCompleted': max(1, xp ~/ 140),
      'totalStars': max(1, xp ~/ 60),
      'streak': rnd.nextInt(40),
      'longestStreak': 40 + rnd.nextInt(80),
      'totalMoves': xp * 3,
      'totalSeconds': xp * 9,
      'questsCompleted': xp ~/ 400,
      'claimedAchievements': [
        if (xp > 2000) ...['solver:1', 'solver:2', 'perfect:1', 'level:1'],
        if (xp > 20000) ...['solver:3', 'streak:1', 'cards:1', 'collector:1', 'level:2'],
        if (xp > 40000) ...['solver:4', 'level:3', 'starhoarder:1', 'squares:1'],
      ],
      'picturesSolved': max(1, xp ~/ 140),
      'picturesPerfect': max(0, xp ~/ 260),
      'packsCompleted': xp ~/ 4000,
      'isVip': i % 5 == 1,
      'solvedByMode': jsonEncode({'cards': xp ~/ 300, 'squares': xp ~/ 900}),
    }));
  }
  if (me != null) out.add(me);
  return out;
}

/// Progress rows for a preset, picked from the catalogue's puzzles (ordered as the app orders them).
/// [puzzles] are the puzzle rows, [packs] the pack rows.
Map<String, Map<String, dynamic>> progressPreset(String name, List<Map<String, dynamic>> packs, List<Map<String, dynamic>> puzzles) {
  if (name == 'none') return {};
  final libraryPacks = [
    for (final p in packs)
      if ((p['category'] ?? '') != 'Daily' && p['startAt'] == null && p['hidden'] != true && (p['isFree'] == true)) p,
  ]..sort((a, b) => ((a['sortOrder'] ?? 0) as num).compareTo((b['sortOrder'] ?? 0) as num));
  List<Map<String, dynamic>> of(Map<String, dynamic> pack) => [
        for (final z in puzzles)
          if (z['packId'] == pack[r'$id']) z,
      ]..sort((a, b) => ((a['sortOrder'] ?? 0) as num).compareTo((b['sortOrder'] ?? 0) as num));
  final out = <String, Map<String, dynamic>>{};
  void done(Map<String, dynamic> z, int stars, {String mode = 'cards', int grid = 4, int ago = 3}) => out['${z[r'$id']}'] = {
        'puzzleId': z[r'$id'],
        'completed': true,
        'stars': stars,
        'gridSize': grid,
        'mode': mode,
        'moves': 30 + stars * 3,
        'elapsedSeconds': 140 + stars * 20,
        'bestMoves': 28,
        'bestSeconds': 120,
        'completedAt': iso(daysAgo(ago)),
        'totalMoves': 40,
        'totalSeconds': 200,
      };
  void playing(Map<String, dynamic> z, double placed, {int cells = 16, String mode = 'cards'}) {
    final rnd = Random(z[r'$id'].hashCode);
    final layout = List<int>.generate(cells, (i) => i);
    final loose = [for (var i = 0; i < cells; i++) if (rnd.nextDouble() > placed) i];
    final shuffled = [...loose]..shuffle(rnd);
    for (var i = 0; i < loose.length; i++) {
      layout[loose[i]] = shuffled[i];
    }
    out['${z[r'$id']}'] = {
      'puzzleId': z[r'$id'],
      'completed': false,
      'gridSize': 4,
      'mode': mode,
      'layout': layout.join(','),
      'moves': 14,
      'elapsedSeconds': 95,
      'session': 's-${z[r'$id']}',
    };
  }

  if (libraryPacks.isEmpty) return out;
  final first = of(libraryPacks[0]);
  switch (name) {
    case 'some':
      for (var i = 0; i < min(3, first.length); i++) {
        done(first[i], 3 - i);
      }
      if (first.length > 3) playing(first[3], 0.4);
      if (libraryPacks.length > 1 && of(libraryPacks[1]).isNotEmpty) playing(of(libraryPacks[1]).first, 0.7);
      return out;
    case 'lots':
      for (var k = 0; k < min(6, libraryPacks.length); k++) {
        final pz = of(libraryPacks[k]);
        final n = k == 0 || k == 1 ? pz.length : (pz.length * (0.2 + 0.15 * k)).round();
        for (var i = 0; i < min(n, pz.length); i++) {
          done(pz[i], k == 0 ? 3 : (i % 3) + 1, mode: const ['cards', 'squares', 'triangles', 'hexagons'][i % 4], ago: i + k);
        }
        if (k >= 2 && n < pz.length) playing(pz[n], 0.3 + 0.1 * k);
      }
      return out;
  }
  throw ArgumentError('unknown progress preset $name');
}
