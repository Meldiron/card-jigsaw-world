import 'dart:io';

import 'package:card_jigsaw_world/core/appwrite.dart';
import 'package:card_jigsaw_world/core/image_files.dart';
import 'package:card_jigsaw_world/data/repositories.dart';
import 'package:card_jigsaw_world/models/models.dart';
import 'package:card_jigsaw_world/state/social.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('player photos are private', () {
    test('upload URLs are recognised, catalogue URLs are not', () {
      expect(ImageFiles.privateFileId(UploadRepository.imageUrl('abc123')), 'abc123');
      expect(ImageFiles.privateFileId(AppwriteConfig.fileViewUrl(AppwriteConfig.puzzleImagesBucket, 'p1')), isNull);
      expect(ImageFiles.privateFileId('https://example.com/a.jpg'), isNull);
    });

    test('uploads are readable only by their owner', () {
      final src = File('lib/data/repositories.dart').readAsStringSync();
      final upload = src.substring(src.indexOf('Future<MyPuzzle> upload('), src.indexOf('Future<void> delete(MyPuzzle'));
      expect(upload, isNot(contains('Role.any()')), reason: 'Anyone could list and read every player photo.');
      expect(upload, contains('Permission.read(Role.user(userId))'));
    });
  });

  group('league places', () {
    Profile p(String id, int xp) => Profile.guest(id).copyWith(xp: xp);

    test('equal XP shares a place, like the header rank', () {
      final rows = [p('a', 900), p('b', 500), p('c', 500), p('d', 500), p('e', 100)];
      expect([for (var i = 0; i < rows.length; i++) leaguePlace(rows, i)], [1, 2, 2, 2, 5]);
    });
  });
}
