import 'package:carden/core/appwrite.dart';
import 'package:carden/core/image_files.dart';
import 'package:carden/data/pack_codes.dart';
import 'package:carden/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

/// Hidden packs and pack codes (function `redeem-code`, docs/pack-codes.md).
void main() {
  Pack pack(Map<String, dynamic> extra) => Pack.fromRow('pack-x', {'name': 'X', 'category': 'Giant', ...extra});
  final now = DateTime.utc(2026, 10, 14, 12);

  group('hidden packs', () {
    test('a hidden pack shows only to players who own it', () {
      final p = pack({'hidden': true});
      expect(p.hidden, isTrue);
      expect(p.visibleTo(const {}, now), isFalse);
      expect(p.visibleTo(const {'pack-y'}, now), isFalse);
      expect(p.visibleTo(const {'pack-x'}, now), isTrue);
    });

    test('a normal pack shows to everyone once released', () {
      expect(pack({}).visibleTo(const {}, now), isTrue);
      expect(pack({'hidden': false}).visibleTo(const {}, now), isTrue);
    });

    test('the far-future start that keeps older apps from listing a hidden pack is ignored here', () {
      const far = '2100-01-01T00:00:00.000+00:00';
      final hidden = pack({'hidden': true, 'startAt': far});
      expect(hidden.startAt, isNull, reason: 'no event window on a hidden pack');
      expect(hidden.hasWindow, isFalse);
      expect(hidden.visibleTo(const {'pack-x'}, now), isTrue);
      // What an older app sees: an event pack that opens in 2100, so it lists nothing.
      final older = pack({'startAt': far});
      expect(older.isReleasedAt(now), isFalse);
    });
  });

  group('codes', () {
    test('typed in any case, with or without dashes and spaces', () {
      expect(PackCodes.normalise('abcd-efgh jkmn-pqrs'), 'ABCDEFGHJKMNPQRS');
      expect(PackCodes.format('abcdefghjkmnpqrs'), 'ABCD-EFGH-JKMN-PQRS');
      expect(PackCodes.normalise('ABCD-EFGH-JKMN-PQRS').length, PackCodes.length);
    });

    test('every error has a calm message', () {
      for (final e in ['invalid', 'used', 'expired', 'signin', 'network', 'server', null]) {
        final m = PackCodeResult(ok: false, error: e).message;
        expect(m, isNotEmpty);
        expect(m.endsWith('.'), isTrue);
        expect(m.contains('!'), isFalse);
      }
    });
  });

  group('private pack pictures', () {
    test('view and preview URLs in private-packs load through the signed-in client', () {
      final view = AppwriteConfig.fileViewUrl(AppwriteConfig.privatePacksBucket, 'hoa-01');
      final f = ImageFiles.privateFile(view)!;
      expect(f.bucket, AppwriteConfig.privatePacksBucket);
      expect(f.fileId, 'hoa-01');
      expect(f.width, isNull);
      final preview = '${AppwriteConfig.endpoint}/storage/buckets/private-packs/files/hoa-01/preview?project=${AppwriteConfig.projectId}&width=600&quality=80';
      expect(ImageFiles.privateFile(preview)!.width, 600);
      expect(ImageFiles.privateFileId(preview), 'hoa-01');
    });

    test('public catalogue pictures stay plain URL loads', () {
      expect(ImageFiles.privateFile(AppwriteConfig.fileViewUrl(AppwriteConfig.puzzleImagesBucket, 'p1')), isNull);
      expect(ImageFiles.privateFile('https://example.com/a.jpg'), isNull);
    });
  });
}
