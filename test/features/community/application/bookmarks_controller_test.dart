// Javító sáv 2026-09-06 (R5) — the Bookmarks screen's controller, which
// until now was a no-op (`docs/ui/apk-functionality-audit-2026-09-06.md`
// §1.3): `load()` did nothing and the state stream never emitted.
//
// B1 — load asks for the FIRST page (initial cursor) and publishes it.
// B2 — loadMore sends the server cursor back and appends without
//      duplicating a row that both pages carry.
// B3 — loadMore is a no-op at the end of the list (halted cursor) — the
//      first page is never re-issued.
// B4 — remove is optimistic and idempotent: the row disappears at once,
//      one DELETE goes out, a second call for the same id sends nothing.
// B5 — a failed remove restores the row in place and rethrows.
// B6 — a failed load lands as a stream ERROR (the screen's retry card),
//      never as an empty "no saved posts" list.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/features/community/application/controllers/bookmarks_controller.dart';
import 'package:strumsight/features/community/domain/entities/community_bookmark.dart';
import 'package:strumsight/features/community/domain/repositories/community_page.dart';
import 'package:strumsight/features/community/domain/value_objects/content_id.dart';
import 'package:strumsight/features/community/domain/value_objects/cursor_page.dart';

CommunityBookmark _row(int id, {bool tombstone = false}) {
  return CommunityBookmark(
    id: id,
    postId: ContentId('post-$id'),
    createdAt: DateTime.utc(2026, 9, 6, 10, id),
    isTombstone: tombstone,
  );
}

final class _Script {
  final List<({Object cursor, int limit})> reads = [];
  final List<({ContentId postId, String idempotencyKey})> removes = [];
  final Map<String?, CommunityPage<CommunityBookmark>> pages = {};
  Object? readError;
  Object? removeError;

  Future<CommunityPage<CommunityBookmark>> read({
    required Object cursor,
    required int limit,
  }) async {
    reads.add((cursor: cursor, limit: limit));
    final error = readError;
    if (error != null) throw error;
    final page = pages[(cursor as CursorPage).cursor];
    if (page != null) return page;
    return const CommunityPage<CommunityBookmark>(
      items: <CommunityBookmark>[],
      cursor: CursorPage.haltedAfterRequest(),
    );
  }

  Future<void> remove({
    required ContentId postId,
    required String idempotencyKey,
  }) async {
    removes.add((postId: postId, idempotencyKey: idempotencyKey));
    final error = removeError;
    if (error != null) throw error;
  }
}

void main() {
  late _Script script;
  late RepositoryBookmarksController controller;
  late List<BookmarksState> states;
  late List<Object> errors;
  late StreamSubscription<BookmarksState> subscription;

  setUp(() {
    script = _Script();
    controller = RepositoryBookmarksController(
      readPage: script.read,
      removeBookmark: script.remove,
      pageSize: 2,
      idempotencyKey: () => 'key-fixed',
    );
    states = <BookmarksState>[];
    errors = <Object>[];
    subscription = controller.stream.listen(states.add, onError: errors.add);
  });

  tearDown(() async {
    await subscription.cancel();
    controller.dispose();
  });

  test('B1 — load publishes the first page (initial cursor)', () async {
    script.pages[null] = CommunityPage<CommunityBookmark>(
      items: <CommunityBookmark>[_row(1), _row(2, tombstone: true)],
      cursor: const CursorPage.continued('c2'),
    );

    await controller.load();

    expect(script.reads.single.cursor, const CursorPage.initial());
    expect(script.reads.single.limit, 2);
    expect(controller.state.rows.map((r) => r.id), <int>[1, 2]);
    expect(controller.state.rows[1].isTombstone, isTrue);
    expect(controller.state.nextCursor, const CursorPage.continued('c2'));
    expect(states, hasLength(1));
  });

  test('B2 — loadMore sends the cursor back and appends without '
      'duplicates', () async {
    script.pages[null] = CommunityPage<CommunityBookmark>(
      items: <CommunityBookmark>[_row(1), _row(2)],
      cursor: const CursorPage.continued('c2'),
    );
    script.pages['c2'] = CommunityPage<CommunityBookmark>(
      items: <CommunityBookmark>[_row(2), _row(3)],
      cursor: const CursorPage.haltedAfterRequest(),
    );
    await controller.load();

    await controller.loadMore();

    expect(script.reads[1].cursor, const CursorPage.continued('c2'));
    expect(controller.state.rows.map((r) => r.id), <int>[1, 2, 3]);
    expect(controller.state.isLoadingMore, isFalse);
    expect(controller.state.nextCursor.cursor, isNull);
    expect(controller.state.nextCursor.isInitial, isFalse);
  });

  test('B3 — loadMore at the end of the list sends nothing', () async {
    script.pages[null] = CommunityPage<CommunityBookmark>(
      items: <CommunityBookmark>[_row(1)],
      cursor: const CursorPage.haltedAfterRequest(),
    );
    await controller.load();

    await controller.loadMore();

    expect(script.reads, hasLength(1));
    expect(controller.state.rows.map((r) => r.id), <int>[1]);
  });

  test('B4 — remove is optimistic and idempotent', () async {
    script.pages[null] = CommunityPage<CommunityBookmark>(
      items: <CommunityBookmark>[_row(1), _row(2)],
      cursor: const CursorPage.haltedAfterRequest(),
    );
    await controller.load();

    final first = controller.remove(bookmarkId: 2);
    expect(controller.state.rows.map((r) => r.id), <int>[1]);
    expect(controller.state.isRemoving, isTrue);
    await first;
    await controller.remove(bookmarkId: 2);

    expect(script.removes, hasLength(1));
    expect(script.removes.single.postId, ContentId('post-2'));
    expect(script.removes.single.idempotencyKey, 'key-fixed');
    expect(controller.state.isRemoving, isFalse);
    expect(controller.state.rows.map((r) => r.id), <int>[1]);
  });

  test('B5 — a failed remove restores the row in place and rethrows', () async {
    script.pages[null] = CommunityPage<CommunityBookmark>(
      items: <CommunityBookmark>[_row(1), _row(2), _row(3)],
      cursor: const CursorPage.haltedAfterRequest(),
    );
    await controller.load();
    script.removeError = const NetworkFailure();

    await expectLater(
      controller.remove(bookmarkId: 2),
      throwsA(isA<NetworkFailure>()),
    );

    expect(controller.state.rows.map((r) => r.id), <int>[1, 2, 3]);
    expect(controller.state.isRemoving, isFalse);
    // The row is removable again after the failure — not stuck as pending.
    script.removeError = null;
    await controller.remove(bookmarkId: 2);
    expect(script.removes, hasLength(2));
    expect(controller.state.rows.map((r) => r.id), <int>[1, 3]);
  });

  test('B6 — a failed load is a stream error, not an empty list', () async {
    script.readError = const ConfigurationFailure();

    await controller.load();
    await Future<void>.delayed(Duration.zero);

    expect(errors.single, isA<ConfigurationFailure>());
    expect(states, isEmpty);
    expect(controller.state.rows, isEmpty);
  });
}
