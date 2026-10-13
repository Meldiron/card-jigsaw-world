import 'dart:io';

import 'package:card_jigsaw_world/state/paged.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// 23 rows served 10 at a time, like Appwrite cursor pagination.
class _Numbers extends PagedNotifier<int> {
  static final rows = List.generate(23, (i) => i);
  static int calls = 0;

  @override
  int get pageSize => 10;

  @override
  Future<PageResult<int>> fetchPage(String? after) async {
    calls++;
    final start = after == null ? 0 : int.parse(after) + 1;
    final items = rows.skip(start).take(pageSize).toList();
    return (items: items, lastId: items.isEmpty ? null : '${items.last}');
  }
}

final _numbers = AsyncNotifierProvider<_Numbers, Paged<int>>(_Numbers.new);

void main() {
  test('pages load one after another until the list is complete', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    _Numbers.calls = 0;
    var p = await c.read(_numbers.future);
    expect(p.items, List.generate(10, (i) => i));
    expect(p.hasMore, isTrue);

    await c.read(_numbers.notifier).loadMore();
    p = c.read(_numbers).value!;
    expect(p.items.length, 20);

    await c.read(_numbers.notifier).loadMore();
    p = c.read(_numbers).value!;
    expect(p.items, _Numbers.rows, reason: 'every row arrives, none twice');
    expect(p.hasMore, isFalse);

    await c.read(_numbers.notifier).loadMore();
    expect(_Numbers.calls, 3, reason: 'a complete list does not ask again');
  });

  test('parallel loadMore calls fetch one page', () async {
    final c = ProviderContainer();
    addTearDown(c.dispose);
    _Numbers.calls = 0;
    await c.read(_numbers.future);
    await Future.wait([c.read(_numbers.notifier).loadMore(), c.read(_numbers.notifier).loadMore(), c.read(_numbers.notifier).loadMore()]);
    expect(c.read(_numbers).value!.items.length, 20);
    expect(_Numbers.calls, 2);
  });

  test('no hard-coded single-page reads: every list query goes through the paging helpers', () {
    // Query.limit appears only in listAllRows / listRowsPage / countRows (repositories.dart).
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>().where((f) => f.path.endsWith('.dart'))) {
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].contains('Query.limit(')) continue;
        final allowed = f.path.endsWith('data/repositories.dart') && (lines[i].contains('Query.limit(pageSize)') || lines[i].contains('Query.limit(limit)') || lines[i].contains('Query.limit(1), Query.select'));
        expect(allowed, isTrue, reason: '${f.path}:${i + 1} reads a fixed single page: ${lines[i].trim()}');
      }
      final text = lines.join('\n');
      expect(text.contains('listRows(') && !f.path.endsWith('data/repositories.dart'), isFalse, reason: '${f.path} lists rows outside the repository helpers');
    }
  });
}
