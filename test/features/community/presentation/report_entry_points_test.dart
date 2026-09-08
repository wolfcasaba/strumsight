/// A tartalom-bejelentés ÉLES belépési pontjai (R33, M10).
///
/// A `showReportContentSheet` E09-R26 óta kész volt, és `lib/**`-ban
/// nulla hívója volt: a lap létezett, de a felhasználó nem tudott
/// eljutni hozzá. Ez a fájl a most bekötött két hívóhelyet méri:
///
///   E1 — a hírfolyam-kártya hosszú nyomása megnyitja a lapot,
///   E2 — a beküldés a MÉRT poszt-azonosítót viszi ki a hálózatra,
///   E3 — a „Hide from feed" leveszi a kártyát a listáról,
///   E4 — a komment-sor hosszú nyomása `comment` cél-típussal nyit,
///   E5 — a kártya `onReport` NÉLKÜL nem kap gesztust (a golden-fixture
///        renderelése bájtra változatlan marad).
///
/// A poszt-repository itt a VALÓDI `HttpCommunityPostRepository`, egy
/// felvevő Dio-adapter fölött — a bejelentés kimenő kérése így nem
/// fake-en, hanem a tényleges soron mérhető.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/core/network/api_client.dart';
import 'package:strumsight/features/community/application/controllers/feed_controller.dart';
import 'package:strumsight/features/community/data/local/feed_cache.dart';
import 'package:strumsight/features/community/data/repositories/feed_repository_impl.dart';
import 'package:strumsight/features/community/data/repositories/post_repository_impl.dart';
import 'package:strumsight/features/community/domain/entities/community_post.dart';
import 'package:strumsight/features/community/domain/entities/moderation_state.dart';
import 'package:strumsight/features/community/domain/entities/share_artifact.dart';
import 'package:strumsight/features/community/domain/policies/community_audience.dart';
import 'package:strumsight/features/community/domain/repositories/community_page.dart';
import 'package:strumsight/features/community/domain/repositories/feed_repository.dart';
import 'package:strumsight/features/community/domain/value_objects/content_id.dart';
import 'package:strumsight/features/community/domain/value_objects/cursor_page.dart';
import 'package:strumsight/features/community/domain/value_objects/public_user_id.dart';
import 'package:strumsight/features/community/presentation/screens/comments_screen.dart';
import 'package:strumsight/features/community/presentation/screens/following_feed_screen.dart';
import 'package:strumsight/features/community/presentation/widgets/feed_card_registry.dart';
import 'package:strumsight/l10n/app_localizations.dart';

import '../../../core/storage/in_memory_key_value_store.dart';

const String _postId = '11111111-1111-4111-8111-111111111111';
const String _commentId = '22222222-2222-4222-8222-222222222222';
const String _authorId = '01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5a01';

// ---------------------------------------------------------------------------
// Dio adapter — the outgoing report request is measured, not faked.
// ---------------------------------------------------------------------------

class _RecordingAdapter implements HttpClientAdapter {
  /// Every request the screen actually issued, in order.
  final List<RequestOptions> requests = <RequestOptions>[];

  /// Just the report submissions — the thing these tests measure.
  Iterable<RequestOptions> get reports =>
      requests.where((request) => request.path == '/community/reports');

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return ResponseBody.fromString(
      jsonEncode(_responseFor(options.path)),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  Map<String, Object?> _responseFor(String path) {
    if (path.endsWith('/comments')) {
      return <String, Object?>{
        'items': <Object?>[
          <String, Object?>{
            'public_id': _commentId,
            'post_public_id': _postId,
            'author_public_id': _authorId,
            'body': 'Fixture comment body.',
            'created_at': '2026-08-23T12:00:00Z',
          },
        ],
        'next_cursor': null,
      };
    }
    return <String, Object?>{
      'report_public_id': '01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5b02',
      'deduplicated': false,
    };
  }

  @override
  void close({bool force = false}) {}
}

CommunityPost _post() => CommunityPost(
  id: ContentId(_postId),
  authorId: PublicUserId(_authorId),
  audience: CommunityAudience.public,
  body: 'Fixture body text.',
  artifact: PracticeSummaryArtifact(
    schemaVersion: shareArtifactSchemaVersion,
    sourceId: 'sess-fixture-1',
    createdAt: DateTime.utc(2026, 8, 23, 12),
    activeSeconds: 60,
    pausedSeconds: 5,
    attemptCount: 1,
    finishReasonCode: 'userFinished',
    bestScore: 0.85,
    coachingCodes: const <String>['strongDownBeats'],
  ),
  createdAt: DateTime.utc(2026, 8, 23, 12),
  moderationState: ModerationState.visible,
  counts: CommunityPostCounts(
    reactionCount: 0,
    commentCount: 0,
    bookmarkCount: 0,
  ),
  viewerState: const CommunityViewerPostState.empty(),
);

class _OnePageFeedRepository implements CommunityFeedRepository {
  @override
  Future<CommunityPage<CommunityPost>> followingFeed({
    required Object cursor,
    required int limit,
  }) async => CommunityPage<CommunityPost>(
    items: <CommunityPost>[_post()],
    cursor: const CursorPage.haltedAfterRequest(),
  );

  @override
  Future<CommunityPage<CommunityPost>> profilePosts({
    required PublicUserId userId,
    required Object cursor,
    required int limit,
  }) => throw UnsupportedError('not used');

  @override
  Future<CommunityPage<CommunityPost>> clubPinned({
    required ContentId clubId,
    required Object cursor,
    required int limit,
  }) => throw UnsupportedError('not used');
}

Widget _app({
  required Widget home,
  required List<Override> extraOverrides,
  required _RecordingAdapter adapter,
}) {
  final dio = Dio(BaseOptions(baseUrl: 'https://example.test'))
    ..httpClientAdapter = adapter;
  return ProviderScope(
    overrides: <Override>[
      communityPostRepositoryProvider.overrideWithValue(
        HttpCommunityPostRepository(ApiClient(dio)),
      ),
      ...extraOverrides,
    ],
    child: MaterialApp(
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: home,
    ),
  );
}

List<Override> _feedOverrides() => <Override>[
  communityFeedRepositoryProvider.overrideWithValue(_OnePageFeedRepository()),
  feedCacheProvider.overrideWithValue(
    FeedCache.open(
      store: InMemoryKeyValueStore(),
      logger: const NoopAppLogger(),
      userId: 4242,
    ),
  ),
];

void main() {
  testWidgets('E1/E2 — long-pressing a feed card reports THAT post', (
    tester,
  ) async {
    final adapter = _RecordingAdapter();
    await tester.pumpWidget(
      _app(
        home: const FollowingFeedScreen(),
        extraOverrides: _feedOverrides(),
        adapter: adapter,
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byType(FeedCard));
    await tester.pumpAndSettle();
    expect(find.text('Report this content'), findsOneWidget);

    await tester.tap(find.byKey(const Key('report-category-spam')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('report-submit')));
    await tester.pumpAndSettle();

    expect(adapter.reports, hasLength(1));
    final body = adapter.reports.single.data! as Map<String, Object?>;
    expect(body['target_type'], 'post');
    expect(body['target_id'], _postId);
    expect(body['category'], 'spam');
  });

  testWidgets('E3 — "Hide from feed" drops the reported card', (tester) async {
    final adapter = _RecordingAdapter();
    await tester.pumpWidget(
      _app(
        home: const FollowingFeedScreen(),
        extraOverrides: _feedOverrides(),
        adapter: adapter,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(FeedCard), findsOneWidget);

    await tester.longPress(find.byType(FeedCard));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('report-category-spam')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('report-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('report-action-hide')));
    await tester.pumpAndSettle();

    expect(find.byType(FeedCard), findsNothing);
  });

  testWidgets('E4 — long-pressing a comment reports it as a comment', (
    tester,
  ) async {
    final adapter = _RecordingAdapter();
    await tester.pumpWidget(
      _app(
        home: CommentsScreen(postId: ContentId(_postId)),
        extraOverrides: const <Override>[],
        adapter: adapter,
      ),
    );
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(Key('comment-report-$_commentId')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('report-category-harassment')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('report-submit')));
    await tester.pumpAndSettle();

    final body = adapter.reports.single.data! as Map<String, Object?>;
    expect(body['target_type'], 'comment');
    expect(body['target_id'], _commentId);
  });

  testWidgets('E5 — a card without onReport carries no long-press gesture', (
    tester,
  ) async {
    // The pixel-pinned goldens and every existing card test build the
    // card WITHOUT the callback; the gesture must not appear there.
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(body: FeedCard(post: _post())),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(Key('feed-card-report-$_postId')), findsNothing);
  });
}
