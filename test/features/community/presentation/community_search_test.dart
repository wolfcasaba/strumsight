/// E09-R09 — Community profile search screen widget tests.
///
/// Covers the §A5 acceptance cell (local + deletable recent
/// searches) and the Kör 9 search-screen invariants:
///
/// * The recent-search list is read from the injected
///   ``RecentSearchStore`` and rendered when the query is empty.
/// * Each recent row has a working "remove" affordance.
/// * The "Clear all" action wipes the store.
/// * The debounced search path issues a single backend call
///   with the typed query (the §9 query-string seam — the
///   actual outbound ``GET /community/profiles/search?q=...``
///   is captured by the scripted Dio adapter).
/// * The screen renders results without crashing when the
///   backend returns a non-empty page.
/// * An error response surfaces a retry affordance — no spinner
///   stuck on screen.
///
/// The repo is mounted through
/// ``communityProfileRepositoryProvider`` — the same provider
/// the production screen reads. The store is injected via the
/// screen's ``recentSearchStore`` constructor argument so the
/// test stays hermetic (no ``SharedPreferences`` mock).
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/core/network/api_client.dart';
import 'package:strumsight/core/storage/key_value_store.dart';
import 'package:strumsight/features/community/data/local/recent_search_store.dart';
import 'package:strumsight/features/community/data/repositories/profile_repository_impl.dart';
import 'package:strumsight/features/community/domain/entities/community_profile.dart';
import 'package:strumsight/features/community/domain/policies/community_audience.dart';
import 'package:strumsight/features/community/domain/repositories/community_page.dart';
import 'package:strumsight/features/community/domain/repositories/community_profile_repository.dart';
import 'package:strumsight/features/community/domain/value_objects/community_handle.dart';
import 'package:strumsight/features/community/domain/value_objects/cursor_page.dart';
import 'package:strumsight/features/community/domain/value_objects/public_user_id.dart';
import 'package:strumsight/features/community/presentation/screens/community_search_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:dio/dio.dart';
import 'dart:typed_data';

// ---------------------------------------------------------------------------
// In-memory KeyValueStore — the test seam for RecentSearchStore. Stays in this
// file because no other test needs it yet; future rounds that touch the
// recent-search surface should move it to a shared test helper.
// ---------------------------------------------------------------------------

class _MemoryKeyValueStore implements KeyValueStore {
  final Map<String, Object> _values = <String, Object>{};

  @override
  bool contains(String key) => _values.containsKey(key);

  @override
  List<String>? readStringList(String key) {
    final raw = _values[key];
    if (raw is! List) return null;
    return List<String>.from(raw.whereType<String>());
  }

  @override
  String? readString(String key) {
    final raw = _values[key];
    return raw is String ? raw : null;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> writeBool(String key, bool value) async {
    _values[key] = value;
  }

  @override
  Future<void> writeDouble(String key, double value) async {
    _values[key] = value;
  }

  @override
  Future<void> writeInt(String key, int value) async {
    _values[key] = value;
  }

  @override
  Future<void> writeString(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> writeStringList(String key, List<String> value) async {
    _values[key] = List<String>.from(value);
  }

  @override
  int? readInt(String key) => _values[key] is int ? _values[key] as int : null;

  @override
  double? readDouble(String key) =>
      _values[key] is double ? _values[key] as double : null;

  @override
  bool? readBool(String key) =>
      _values[key] is bool ? _values[key] as bool : null;
}

// ---------------------------------------------------------------------------
// Fake repository — the §6 cell's load-bearing seam. The screen calls
// ``searchProfiles`` exactly once per debounced query; the fake records the
// argument list and returns the canned response.
// ---------------------------------------------------------------------------

class _FakeCommunityProfileRepository implements CommunityProfileRepository {
  _FakeCommunityProfileRepository(this._response);

  final Future<CommunityPage<CommunityProfile>> Function(
    String query,
    Object cursor,
  )
  _response;

  final List<MapEntry<String, Object>> calls = <MapEntry<String, Object>>[];

  @override
  Future<CommunityPage<CommunityProfile>> searchProfiles({
    required String query,
    required Object cursor,
  }) {
    calls.add(MapEntry(query, cursor));
    return _response(query, cursor);
  }

  @override
  Future<CommunityProfile?> fetchMyProfile() async => null;

  @override
  Future<CommunityProfile> fetchById(PublicUserId userId) =>
      throw UnsupportedError('not used in this test');

  @override
  Future<CommunityProfile?> fetchByHandle(CommunityHandle handle) =>
      throw UnsupportedError('not used in this test');

  @override
  Future<AppResult<CommunityProfile>> createProfile({
    required CommunityHandle handle,
    required String displayName,
    required ProfileVisibility visibility,
    required CommunityAudience audienceDefault,
  }) => throw UnsupportedError('not used in this test');

  @override
  Future<AppResult<CommunityProfile>> updateProfile({
    required String displayName,
  }) => throw UnsupportedError('not used in this test');
}

CommunityProfile _profile(String suffix) => CommunityProfile(
  userId: PublicUserId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5$suffix'),
  handle: CommunityHandle('alice-$suffix'),
  displayName: 'Alice $suffix',
  visibility: ProfileVisibility.public,
  avatarUrl: null,
  bio: null,
  skillInterests: const <String>[],
  badges: const <String>[],
  relationship: CommunityRelationshipToViewer.notRelated,
  createdAt: DateTime.utc(2026),
);

Widget _harness({
  required CommunityProfileRepository repo,
  RecentSearchStore? store,
}) {
  return ProviderScope(
    overrides: [communityProfileRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: CommunitySearchScreen(recentSearchStore: store),
    ),
  );
}

void main() {
  testWidgets(
    'A5 — recent searches are local and deletable (remove single entry)',
    (tester) async {
      final store = RecentSearchStore.open(_MemoryKeyValueStore());
      await store.push('alice');
      await store.push('bob');
      await store.push('carla');

      final repo = _FakeCommunityProfileRepository(
        (query, _) async => const CommunityPage<CommunityProfile>(
          items: <CommunityProfile>[],
          cursor: CursorPage.haltedAfterRequest(),
        ),
      );

      await tester.pumpWidget(_harness(repo: repo, store: store));
      await tester.pumpAndSettle();

      // The recent list is rendered most-recent-first.
      expect(find.text('carla'), findsOneWidget);
      expect(find.text('bob'), findsOneWidget);
      expect(find.text('alice'), findsOneWidget);

      // Tap the "remove" affordance on the first row (carla).
      final removeButtons = find.byTooltip('Remove');
      expect(removeButtons, findsNWidgets(3));
      await tester.tap(removeButtons.first);
      await tester.pumpAndSettle();

      // carla is gone; the others remain.
      expect(find.text('carla'), findsNothing);
      expect(find.text('bob'), findsOneWidget);
      expect(find.text('alice'), findsOneWidget);

      // The store reflects the removal.
      expect(store.read(), <String>['bob', 'alice']);
    },
  );

  testWidgets(
    'A5 — "Clear all" wipes the recent-search list (no server call)',
    (tester) async {
      final store = RecentSearchStore.open(_MemoryKeyValueStore());
      await store.push('alice');
      await store.push('bob');

      final repo = _FakeCommunityProfileRepository(
        (query, _) async => const CommunityPage<CommunityProfile>(
          items: <CommunityProfile>[],
          cursor: CursorPage.haltedAfterRequest(),
        ),
      );

      await tester.pumpWidget(_harness(repo: repo, store: store));
      await tester.pumpAndSettle();

      expect(find.text('Clear all'), findsOneWidget);

      await tester.tap(find.text('Clear all'));
      await tester.pumpAndSettle();

      // Empty-state copy shows up; recent list rows are gone.
      expect(
        find.text('Type a handle prefix to discover players.'),
        findsOneWidget,
      );
      expect(find.text('alice'), findsNothing);
      expect(find.text('bob'), findsNothing);

      // No search backend call ever happened.
      expect(repo.calls, isEmpty);

      expect(store.read(), isEmpty);
    },
  );

  testWidgets('recent-search list starts empty when the store has no entries', (
    tester,
  ) async {
    final store = RecentSearchStore.open(_MemoryKeyValueStore());
    final repo = _FakeCommunityProfileRepository(
      (query, _) async => const CommunityPage<CommunityProfile>(
        items: <CommunityProfile>[],
        cursor: CursorPage.haltedAfterRequest(),
      ),
    );

    await tester.pumpWidget(_harness(repo: repo, store: store));
    await tester.pumpAndSettle();

    expect(
      find.text('Type a handle prefix to discover players.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'Submitting a query issues exactly one searchProfiles call with the typed value',
    (tester) async {
      final store = RecentSearchStore.open(_MemoryKeyValueStore());
      final repo = _FakeCommunityProfileRepository(
        (query, _) async => CommunityPage<CommunityProfile>(
          items: <CommunityProfile>[_profile('01')],
          cursor: const CursorPage.initial(),
        ),
      );

      await tester.pumpWidget(_harness(repo: repo, store: store));
      await tester.pumpAndSettle();

      // Type the query and press the keyboard "search" action.
      await tester.enterText(find.byType(TextField), 'alice');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(
        repo.calls,
        hasLength(1),
        reason: 'submit should fire exactly one search call',
      );
      expect(repo.calls.first.key, 'alice');
      expect(repo.calls.first.value, const CursorPage.initial());

      // The result row appears.
      expect(find.text('Alice 01'), findsOneWidget);

      // The recent-search list picked up the new query.
      expect(store.read(), <String>['alice']);
    },
  );

  testWidgets('Debounced typing fires ONE call after the user stops typing', (
    tester,
  ) async {
    final store = RecentSearchStore.open(_MemoryKeyValueStore());
    final repo = _FakeCommunityProfileRepository(
      (query, _) async => const CommunityPage<CommunityProfile>(
        items: <CommunityProfile>[],
        cursor: CursorPage.haltedAfterRequest(),
      ),
    );

    await tester.pumpWidget(_harness(repo: repo, store: store));
    await tester.pumpAndSettle();

    // Simulate rapid keystrokes. Each ``pump`` advances the
    // debounce window — only the last keystroke should land a
    // call.
    await tester.enterText(find.byType(TextField), 'a');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextField), 'al');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextField), 'ali');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextField), 'alic');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.enterText(find.byType(TextField), 'alice');
    // Now wait past the debounce window.
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();

    expect(
      repo.calls,
      hasLength(1),
      reason: 'debounced typing should collapse to a single call',
    );
    expect(repo.calls.first.key, 'alice');
  });

  testWidgets(
    'An empty result set renders the empty-state copy without an error',
    (tester) async {
      final store = RecentSearchStore.open(_MemoryKeyValueStore());
      final repo = _FakeCommunityProfileRepository(
        (query, _) async => const CommunityPage<CommunityProfile>(
          items: <CommunityProfile>[],
          cursor: CursorPage.haltedAfterRequest(),
        ),
      );

      await tester.pumpWidget(_harness(repo: repo, store: store));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'zzzz');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pumpAndSettle();

      expect(find.text('No matches.'), findsOneWidget);
    },
  );

  testWidgets('A network failure renders the retry affordance', (tester) async {
    final store = RecentSearchStore.open(_MemoryKeyValueStore());
    final repo = _FakeCommunityProfileRepository(
      (query, _) async =>
          throw const NetworkFailure(code: FailureCode.networkUnavailable),
    );

    await tester.pumpWidget(_harness(repo: repo, store: store));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'alice');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pumpAndSettle();

    expect(find.text('Network error'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  // F1 regression — the real wire-decode path produces DISTINCT
  // displayName/handle rows. The pre-fix path used a single
  // fixed-string placeholder factory; the tests below would fail
  // on that regression.
  _f1();
}

// ---------------------------------------------------------------------------
// F1 regression — the Kör 9 wire decode must turn the backend
// ``hits`` array into DISTINCT ``CommunityProfile`` rows. The
// pre-fix path used a single fixed-string placeholder factory
// for every hit, so the result list rendered an N-row wall of
// identical "placeholder" / "@placeholder-x1" entries. The test
// drives the real ``HttpCommunityProfileRepository`` through a
// scripted Dio adapter (the same harness the Kör 7 / Kör 8
// relationship-repository test uses), so the assertion rides
// through the actual JSON-decode + DTO/domain conversion path.
// ---------------------------------------------------------------------------

class _CannedResponse {
  const _CannedResponse({required this.body, required this.status});
  final String body;
  final int status;
}

class _ScriptedAdapter implements HttpClientAdapter {
  _ScriptedAdapter({required this.onFetch});

  final _CannedResponse Function(RequestOptions options) onFetch;
  final List<RequestOptions> captured = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    captured.add(options);
    final canned = onFetch(options);
    return ResponseBody.fromString(
      canned.body,
      canned.status,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

HttpCommunityProfileRepository _buildHttpRepo(_ScriptedAdapter adapter) {
  final dio = Dio()..httpClientAdapter = adapter;
  return HttpCommunityProfileRepository(ApiClient(dio));
}

class _F1Group {
  static void run() {
    test('F1 — searchProfiles() decodes two distinct hits into two distinct '
        'displayName/handle pairs (no fixed placeholder)', () async {
      const alicePublicId = '01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5a01';
      const bobPublicId = '01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5a02';
      const body =
          '''
{
  "public_ids": ["$alicePublicId", "$bobPublicId"],
  "hits": [
    {
      "public_id": "$alicePublicId",
      "handle": "alice-001",
      "display_name": "Alice the First",
      "created_at": "2026-01-01T00:00:00.000Z"
    },
    {
      "public_id": "$bobPublicId",
      "handle": "bob-002",
      "display_name": "Bob the Second",
      "created_at": "2026-02-02T00:00:00.000Z"
    }
  ],
  "next_cursor": "opaque-token-must-not-be-decoded-by-client"
}''';
      final adapter = _ScriptedAdapter(
        onFetch: (_) => const _CannedResponse(body: body, status: 200),
      );
      final repo = _buildHttpRepo(adapter);

      final CommunityPage<CommunityProfile> page = await repo.searchProfiles(
        query: 'ali',
        cursor: const CursorPage.initial(),
      );

      expect(page.items, hasLength(2));
      expect(page.items[0].userId.value, alicePublicId);
      expect(page.items[0].handle.value, 'alice-001');
      expect(page.items[0].displayName, 'Alice the First');
      expect(page.items[1].userId.value, bobPublicId);
      expect(page.items[1].handle.value, 'bob-002');
      expect(page.items[1].displayName, 'Bob the Second');

      for (final item in page.items) {
        expect(item.displayName, isNot('placeholder'));
        expect(item.handle.value, isNot('placeholder-x1'));
      }

      expect(adapter.captured, hasLength(1));
      final options = adapter.captured.single;
      expect(options.method, 'GET');
      expect(options.uri.path, '/community/profiles/search');
      expect(options.uri.queryParameters['q'], 'ali');
      expect(options.uri.queryParameters['limit'], '50');
      expect(
        options.uri.queryParameters.containsKey('cursor'),
        isFalse,
        reason: 'initial cursor must not be forwarded as a query param',
      );

      expect(page.cursor, isA<CursorPage>());
      final cursorPage = page.cursor;
      expect(cursorPage.cursor, 'opaque-token-must-not-be-decoded-by-client');
    });

    test(
      'F1 — searchProfiles() forwards a non-initial opaque cursor verbatim',
      () async {
        const token = 'opaque.next.page.token';
        const body = '''
{
  "public_ids": ["01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5a09"],
  "hits": [
    {
      "public_id": "01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5a09",
      "handle": "alice-009",
      "display_name": "Alice Nine",
      "created_at": "2026-03-03T00:00:00.000Z"
    }
  ],
  "next_cursor": null
}''';
        final adapter = _ScriptedAdapter(
          onFetch: (_) => const _CannedResponse(body: body, status: 200),
        );
        final repo = _buildHttpRepo(adapter);

        await repo.searchProfiles(
          query: 'ali',
          cursor: CursorPage.continued(token),
        );

        final options = adapter.captured.single;
        expect(options.uri.queryParameters['cursor'], token);
        expect(options.uri.queryParameters['q'], 'ali');
      },
    );

    test(
      'F1 — searchProfiles() throws on a malformed hit (empty display_name)',
      () async {
        const body = '''
{
  "public_ids": ["01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5a10"],
  "hits": [
    {
      "public_id": "01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5a10",
      "handle": "alice-010",
      "display_name": "",
      "created_at": "2026-04-04T00:00:00.000Z"
    }
  ],
  "next_cursor": null
}''';
        final adapter = _ScriptedAdapter(
          onFetch: (_) => const _CannedResponse(body: body, status: 200),
        );
        final repo = _buildHttpRepo(adapter);

        await expectLater(
          () => repo.searchProfiles(
            query: 'ali',
            cursor: const CursorPage.initial(),
          ),
          throwsA(isA<NetworkFailure>()),
        );
      },
    );
  }
}

void _f1() => _F1Group.run();
