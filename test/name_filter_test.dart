import 'package:carden/core/guest_names.dart';
import 'package:carden/core/name_filter.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:unique_names_generator/unique_names_generator.dart';

/// Offensive player names (lib/core/name_filter.dart, guideline 1.2).
void main() {
  // A word list cannot catch every spelling: that is what Report is for.
  test('offensive names are caught, however they are written', () {
    for (final name in [
      'fuck', 'Fuck Otter', 'FUUUCK', 'f u c k', 'f.u.c.k', 'fück', 'Big F4ck', 'f*ck you', 'fvck', 'phuck', 'f-u-c-k', 'sh1t', r'$hit happens', 'b1tch', 'Big Ass', 'asses', 'Dick',
      'Peacock Cock', 'nazis', 'Heil', 'kurva', 'Kurva Mat', 'kokot', 'piča', 'hovno', 'Hurensohn', 'puta', 'Vaffanculo', 'p0rn star', '1488', 'xXx',
      'n1gga', 'NIGGER', 'faggot', 'motherfucker', 'Cunt', 'whore', 'rapist',
    ]) {
      expect(NameFilter.isOffensive(name), isTrue, reason: name);
      expect(NameFilter.shown(name), 'Player', reason: name);
    }
  });

  test('ordinary names pass, including words that contain a rude one', () {
    for (final name in [
      'Brave Otter', 'Picasso', 'Therapist', 'Tropical Peacock', 'Raccoon', 'Swanky Swan', 'Sussex', 'Essex Class', 'Canal Grape', 'Scrape',
      'Torpedo', 'Cockatoo', 'Woodcock', 'Blue Booby', 'Blue Tit', 'Great Tit', 'Monica', 'Dickens', 'Nazir', 'Semen', 'Sexton', 'Assassin', 'Bassist',
      'Analyst', 'Hancock', 'Matej', 'Anna 1988', 'Gato Negro', 'Hokey Pokey', 'Pikachu', 'Kurt', 'Puttin', 'Cumbria', 'Mr. Bean', 'St. Ives', 'Hi-Tech Fox', "O'Brien", 'Ann_Marie 77', 'Flick 4 Luck',
    ]) {
      expect(NameFilter.isOffensive(name), isFalse, reason: name);
      expect(NameFilter.shown(name), name);
    }
  });

  test('every word of the generated guest names passes', () {
    final flagged = [...adjectives, ...animals].where(NameFilter.isOffensive).toList();
    expect(flagged, isEmpty);
  });

  test('generated guest names are never offensive', () {
    for (var i = 0; i < 2000; i++) {
      expect(NameFilter.isOffensive(GuestNames.next()), isFalse);
    }
  });

  test('generated guest names are whole words that fit in 20 characters', () {
    // Cutting a long pair once left "Straightforward Cock": long pairs are drawn again instead.
    final words = {for (final w in [...adjectives, ...animals]) w.toLowerCase()};
    for (var i = 0; i < 2000; i++) {
      final name = GuestNames.next();
      expect(name.length, lessThanOrEqualTo(20), reason: name);
      expect(words.contains(name.substring(name.indexOf(' ') + 1).toLowerCase()), isTrue, reason: name);
    }
  });
}
