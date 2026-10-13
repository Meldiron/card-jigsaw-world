import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// One page of a cursor-paginated list: the rows and the id to continue after.
typedef PageResult<T> = ({List<T> items, String? lastId});

/// A list that grows one page at a time (Appwrite cursor pagination), for screens that scroll
/// through data of unbounded size. The first page loads with the provider; [PagedNotifier.loadMore]
/// appends the next one as the list nears its end.
@immutable
class Paged<T> {
  const Paged({required this.items, required this.hasMore, this.cursor, this.loadingMore = false});
  final List<T> items;
  final bool hasMore;
  final String? cursor;
  final bool loadingMore;
}

abstract class PagedNotifier<T> extends AsyncNotifier<Paged<T>> {
  int get pageSize;

  /// Reads up to [pageSize] rows after the row id [after] (from the start when null).
  Future<PageResult<T>> fetchPage(String? after);

  @override
  Future<Paged<T>> build() async {
    final page = await fetchPage(null);
    return Paged(items: page.items, hasMore: page.items.length >= pageSize, cursor: page.lastId);
  }

  /// Appends the next page. Safe to call repeatedly: it returns while a page is loading or when
  /// the list is complete.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || current.loadingMore || state.isLoading) {
      return;
    }
    state = AsyncData(Paged(items: current.items, hasMore: true, cursor: current.cursor, loadingMore: true));
    try {
      final page = await fetchPage(current.cursor);
      state = AsyncData(Paged(items: [...current.items, ...page.items], hasMore: page.items.length >= pageSize, cursor: page.lastId ?? current.cursor));
    } catch (e) {
      debugPrint('$runtimeType: next page failed: $e');
      state = AsyncData(Paged(items: current.items, hasMore: true, cursor: current.cursor));
    }
  }
}
