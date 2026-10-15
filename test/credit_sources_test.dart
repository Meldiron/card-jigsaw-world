import 'package:carden/features/profile/settings_screen.dart';
import 'package:carden/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

Puzzle _p(int i, String source) => Puzzle.fromRow('p$i', {'packId': 'x', 'title': 't', 'imageUrl': 'u', 'source': source});

void main() {
  test('Settings > Image credits: sources come from the catalogue, largest first, licences without versions', () {
    final sources = creditSources([
      _p(1, 'Wikimedia Commons, CC BY-SA 4.0'),
      _p(2, 'Wikimedia Commons, CC BY-SA 3.0 de'),
      _p(3, 'Wikimedia Commons, CC0 (AI-generated)'),
      _p(4, 'Wikimedia Commons, Public domain'),
      _p(5, 'flickr via Openverse, Public Domain Mark'),
      _p(6, 'flickr via Openverse, CC BY'),
      _p(7, 'Lorem Picsum / Unsplash'),
      _p(8, 'National Gallery of Art, Washington, CC0'),
      _p(9, 'NASA Image Library'),
      _p(10, 'stocksnap via Openverse, CC CC0'),
    ]);
    expect(sources.first.name, 'Wikimedia Commons');
    expect(sources.first.count, 4);
    expect(sources.first.licences, ['CC0', 'Public domain', 'CC BY-SA']);
    expect(sources.firstWhere((s) => s.name == 'Flickr via Openverse').licences, ['Public domain', 'CC BY']);
    expect(sources.firstWhere((s) => s.name == 'Unsplash via Lorem Picsum').licences, ['Unsplash License']);
    expect(sources.firstWhere((s) => s.name == 'National Gallery of Art, Washington').licences, ['CC0']);
    expect(sources.firstWhere((s) => s.name == 'NASA Image and Video Library').licences, ['Public domain']);
    expect(sources.firstWhere((s) => s.name == 'StockSnap via Openverse').licences, ['CC0']);
  });
}
