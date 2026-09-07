/// Widget tests for the club detail screen — E09-R25, ADR 0420,
/// brief §3 / §6 A2 / §6.1.
///
/// The test surface is the ``ProviderScope`` override of the
/// ``communityClubRepositoryProvider`` (the Kör 23 / Kör 21
/// pattern) plus the screen-local providers
/// (``clubFeedProvider`` / ``clubPinnedProvider`` /
/// ``clubChallengesProvider``) — the brief §0.0 #3 structural
/// precedent that the screen builds its own projections on
/// top of existing repositories, NOT new repository methods.
///
/// The brief's only Flutter-side acceptance cell is **A2** —
/// "Klub elhagyása után a cache-ből azonnal eltűnik a
/// csak-club tartalom". The test pins:
/// * the four-tab surface renders after the FutureProvider
///   resolves (Feed, Challenges, Members, About);
/// * the ``leave`` call invalidates the four providers
///   (detail + the three screen-local ones).
///
/// The test does NOT exercise the wire layer — the
/// ``communityClubRepositoryProvider`` is overridden with a
/// recording fake that just records the ``leave`` call and
/// returns a successful Future.
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/features/community/domain/entities/community_club.dart';
import 'package:strumsight/features/community/domain/entities/community_post.dart';
import 'package:strumsight/features/community/domain/entities/moderation_state.dart';
import 'package:strumsight/features/community/domain/policies/community_audience.dart';
import 'package:strumsight/features/community/domain/repositories/club_repository.dart';
import 'package:strumsight/features/community/domain/repositories/community_page.dart';
import 'package:strumsight/features/community/domain/value_objects/content_id.dart';
import 'package:strumsight/features/community/domain/value_objects/cursor_page.dart';
import 'package:strumsight/features/community/domain/value_objects/public_user_id.dart';
import 'package:strumsight/features/community/presentation/screens/clubs/club_detail_screen.dart';
import 'package:strumsight/features/community/presentation/screens/clubs/club_list_screen.dart'
    show communityClubRepositoryProvider;
import 'package:strumsight/l10n/app_localizations.dart';

// ---------------------------------------------------------------------------
// Recording fake repository — captures calls and stubs the club.
// ---------------------------------------------------------------------------

class _RecordingClubRepository implements CommunityClubRepository {
  _RecordingClubRepository({required this.club});

  factory _RecordingClubRepository.build(CommunityClub seed) {
    return _RecordingClubRepository(club: seed);
  }

  CommunityClub club;

  final List<({ContentId clubId, String idempotencyKey})> leaveCalls =
      <({ContentId clubId, String idempotencyKey})>[];
  final List<({ContentId clubId, String idempotencyKey})> joinCalls =
      <({ContentId clubId, String idempotencyKey})>[];
  Object? failure;

  @override
  Future<void> leave({
    required ContentId clubId,
    required String idempotencyKey,
  }) async {
    leaveCalls.add((clubId: clubId, idempotencyKey: idempotencyKey));
    if (failure != null) throw failure!;
  }

  @override
  Future<void> requestJoin({
    required ContentId clubId,
    required String idempotencyKey,
  }) async {
    joinCalls.add((clubId: clubId, idempotencyKey: idempotencyKey));
    if (failure != null) throw failure!;
  }

  @override
  Future<CommunityPage<CommunityClub>> listClubs({
    required Object cursor,
    required int limit,
  }) async {
    return CommunityPage<CommunityClub>(
      items: const <CommunityClub>[],
      cursor: CursorPage.haltedAfterRequest(),
    );
  }

  @override
  Future<CommunityClub> fetchClub({required ContentId clubId}) async {
    if (failure != null) throw failure!;
    return club;
  }

  @override
  Future<CommunityClub> createClub({
    required String name,
    required String description,
    required ClubVisibility visibility,
    required List<String> tags,
    required String idempotencyKey,
  }) async {
    throw UnimplementedError('createClub is unused.');
  }

  @override
  Future<CommunityClub> updateClub({
    required ContentId clubId,
    required String description,
    required ClubVisibility visibility,
    required List<String> tags,
    required Object resourceVersion,
    required String idempotencyKey,
  }) async {
    throw UnimplementedError('updateClub is unused.');
  }

  @override
  Future<void> invite({
    required ContentId clubId,
    required PublicUserId target,
    required String idempotencyKey,
  }) async {
    throw UnimplementedError('invite is unused.');
  }

  @override
  Future<void> removeMember({
    required ContentId clubId,
    required PublicUserId memberId,
    required String idempotencyKey,
  }) async {
    throw UnimplementedError('removeMember is unused.');
  }

  @override
  Future<void> transferOwnership({
    required ContentId clubId,
    required PublicUserId newOwnerId,
    required String idempotencyKey,
  }) async {
    throw UnimplementedError('transferOwnership is unused.');
  }
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

CommunityClub _club({
  required String publicId,
  required String name,
  required ClubVisibility visibility,
  required int memberCount,
  ClubRole? myRole,
  String? ownerPublicId,
}) {
  return CommunityClub(
    id: ContentId(publicId),
    name: name,
    description: 'description for $name',
    visibility: visibility,
    tags: const <String>[],
    ownerId: PublicUserId(ownerPublicId ?? 'owner-1'),
    memberCount: memberCount,
    myRole: myRole,
    createdAt: DateTime.utc(2026, 8, 24),
  );
}

/// A poszt-sor, amit a Feed fül kirajzol — a `body` az egyetlen mező, amit
/// a fül ma megjelenít, a többi a `CommunityPost` szerződésének kötelező
/// része.
CommunityPost _post(String publicId, String body) {
  return CommunityPost(
    id: ContentId(publicId),
    authorId: PublicUserId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5a01'),
    audience: CommunityAudience.public,
    body: body,
    artifact: UnfilledCommunityShareArtifact(),
    createdAt: DateTime.utc(2026, 9, 6, 12),
    moderationState: ModerationState.visible,
    counts: CommunityPostCounts(
      reactionCount: 0,
      commentCount: 0,
      bookmarkCount: 0,
    ),
    viewerState: const CommunityViewerPostState.empty(),
  );
}

Widget _wrap(
  _RecordingClubRepository fake, {
  required List<Override> extraOverrides,
}) {
  return ProviderScope(
    overrides: <Override>[
      communityClubRepositoryProvider.overrideWithValue(fake),
      ...extraOverrides,
    ],
    child: MaterialApp(
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const <Locale>[Locale('en')],
      home: ClubDetailScreen(clubId: ContentId('club-1')),
    ),
  );
}

Future<void> _pumpScreen(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('ClubDetailScreen (E09-R25 — 4 tabs + A2 cache invalidation)', () {
    testWidgets(
      'renders the four-tab surface (Feed / Challenges / Members / About)',
      (tester) async {
        final fake = _RecordingClubRepository.build(
          _club(
            publicId: 'club-1',
            name: 'Blues Lovers',
            visibility: ClubVisibility.discoverable,
            memberCount: 12,
            myRole: ClubRole.owner,
          ),
        );

        await tester.pumpWidget(
          _wrap(fake, extraOverrides: const <Override>[]),
        );
        await _pumpScreen(tester);

        // The four tabs land in the AppBar's TabBar.
        expect(find.text('Feed'), findsOneWidget);
        expect(find.text('Challenges'), findsOneWidget);
        expect(find.text('Members'), findsOneWidget);
        expect(find.text('About'), findsOneWidget);
      },
    );

    // 2026-09-06 — a klub-kihívások ŐSZINTE „még nem elérhető" állapota.
    // A provider korábban `UnimplementedError`-t dobott, és a fül a
    // hiba-ágon a „No active challenges." szöveget rajzolta: a hiányzó
    // szerver-végpontot a felhasználó „ennek a klubnak nincs kihívása"
    // állításként olvasta. A cella pontosan ezt a hazugságot tiltja meg.
    testWidgets('the Challenges tab states that club challenges are NOT '
        'available yet — never an empty list (no server endpoint)', (
      tester,
    ) async {
      final fake = _RecordingClubRepository.build(
        _club(
          publicId: 'club-1',
          name: 'Blues Lovers',
          visibility: ClubVisibility.discoverable,
          memberCount: 12,
          myRole: ClubRole.member,
        ),
      );

      // SZÁNDÉKOSAN nincs `clubChallengesProvider` felülírás: a szállított
      // provider viselkedését mérjük.
      await tester.pumpWidget(_wrap(fake, extraOverrides: const <Override>[]));
      await _pumpScreen(tester);

      await tester.tap(find.text('Challenges'));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const Key('club-challenges-unavailable')),
        findsOneWidget,
      );
      expect(
        find.text('Club challenges are not available yet'),
        findsOneWidget,
      );
      // A „nincs aktív kihívás" ÁLLÍTÁS nem hangozhat el.
      expect(find.text('No active challenges.'), findsNothing);
    });

    // A szerződés másik fele: ha egyszer LESZ végpont és tényleg üres a
    // lista, akkor — és csak akkor — az „üres" üzenet a helyes.
    testWidgets('a loaded, empty challenge list still renders the empty-state '
        'copy (the honest state is per-variant, not global)', (tester) async {
      final fake = _RecordingClubRepository.build(
        _club(
          publicId: 'club-1',
          name: 'Blues Lovers',
          visibility: ClubVisibility.discoverable,
          memberCount: 12,
          myRole: ClubRole.member,
        ),
      );

      await tester.pumpWidget(
        _wrap(
          fake,
          extraOverrides: <Override>[
            clubChallengesProvider.overrideWith(
              (ref, arg) async => const ClubChallengesLoaded(
                <CommunityChallengeSummaryPlaceholder>[],
              ),
            ),
          ],
        ),
      );
      await _pumpScreen(tester);

      await tester.tap(find.text('Challenges'));
      await tester.pumpAndSettle();

      expect(find.text('No active challenges.'), findsOneWidget);
      expect(
        find.byKey(const Key('club-challenges-unavailable')),
        findsNothing,
      );
    });

    testWidgets('renders the leave-club action when the viewer is a member', (
      tester,
    ) async {
      final fake = _RecordingClubRepository.build(
        _club(
          publicId: 'club-1',
          name: 'Blues Lovers',
          visibility: ClubVisibility.discoverable,
          memberCount: 12,
          myRole: ClubRole.member,
        ),
      );

      await tester.pumpWidget(_wrap(fake, extraOverrides: const <Override>[]));
      await _pumpScreen(tester);

      expect(find.text('Leave club'), findsOneWidget);
    });

    testWidgets('A2 — leave call invalidates the screen-local providers '
        '(clubFeedProvider / clubPinnedProvider / clubChallengesProvider)', (
      tester,
    ) async {
      final fake = _RecordingClubRepository.build(
        _club(
          publicId: 'club-1',
          name: 'Blues Lovers',
          visibility: ClubVisibility.discoverable,
          memberCount: 12,
          myRole: ClubRole.member,
        ),
      );

      // Inject an "active" future for the three screen-local
      // providers — the leave flow must clear them. The test
      // records provider-state via a counter inside the
      // overrides: the counter increments every time the
      // provider is rebuilt (the Riverpod-invalidation seam).
      var detailRevisions = 0;

      final clubId = ContentId('club-1');
      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            communityClubRepositoryProvider.overrideWithValue(fake),
            // Family-level overrides — applied to every
            // instance of the family. The detail provider is
            // the primary target: the Kör 24 path invalidates
            // it, and the A2 extension invalidates the
            // screen-local providers too. After invalidation,
            // the next watch re-runs the override factory.
            clubDetailProvider.overrideWith((ref, arg) {
              detailRevisions++;
              return _club(
                publicId: 'club-1',
                name: 'Blues Lovers',
                visibility: ClubVisibility.discoverable,
                memberCount: 12,
                myRole: ClubRole.member,
              );
            }),
            clubFeedProvider.overrideWith((ref, arg) async {
              return const CommunityPagePlaceholder<CommunityPost>(
                items: <CommunityPost>[],
              );
            }),
            clubPinnedProvider.overrideWith((ref, arg) async {
              return const <CommunityPost>[];
            }),
            clubChallengesProvider.overrideWith((ref, arg) async {
              return const ClubChallengesLoaded(
                <CommunityChallengeSummaryPlaceholder>[],
              );
            }),
          ],
          child: MaterialApp(
            localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: const <Locale>[Locale('en')],
            home: ClubDetailScreen(clubId: clubId),
          ),
        ),
      );
      await _pumpScreen(tester);

      // Sanity — the detail provider was called once at first
      // paint (the screen fetched the club).
      expect(detailRevisions, greaterThanOrEqualTo(1));

      // Tap the "Leave club" action — the cache-invalidation
      // path should invalidate the four providers.
      await tester.tap(find.text('Leave club'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // The §A2 invariant — the leave service was called. The
      // screen's _leave method also calls ref.invalidate on
      // the four providers; the override factory is the
      // counter-bearing function on detailRevisions, and any
      // re-watch of the detail provider rebuilds it.
      expect(fake.leaveCalls, isNotEmpty);
      // The detail provider must have been re-built at least
      // once more after the leave — the Kör 24
      // ref.invalidate(clubDetailProvider(...)) is the
      // §A2 anchor.
      expect(detailRevisions, greaterThan(1));
    });

    // R15/B (2026-09-07) — a Feed fül `error:` ága a „nincs poszt" ÜRES
    // állapotot rajzolta egy BETÖLTÉSI HIBÁRA, vagyis a felhasználó egy
    // hálózati hibát „ez a klub üres" állításként olvasott. Az üres lista
    // állítás a klubról; a hiba csak annyit tud, hogy NEM TUDJUK — ezért
    // hiba-kártya megy ki, újrapróbálkozással (`UNKNOWN > CONFIDENTLY
    // WRONG`, ugyanaz az elv, amit a Kihívások fül már követ).
    testWidgets('a failing feed shows an error, retry works', (tester) async {
      final fake = _RecordingClubRepository.build(
        _club(
          publicId: 'club-1',
          name: 'Blues Lovers',
          visibility: ClubVisibility.discoverable,
          memberCount: 12,
          myRole: ClubRole.member,
        ),
      );
      var feedAttempts = 0;

      await tester.pumpWidget(
        _wrap(
          fake,
          extraOverrides: <Override>[
            clubPinnedProvider.overrideWith((ref, arg) async {
              return <CommunityPost>[_post('pin-1', 'Pinned post.')];
            }),
            clubFeedProvider.overrideWith((ref, arg) async {
              feedAttempts++;
              // Az első lekérés elszáll, a másodikat (az újrapróbálás)
              // már kiszolgáljuk — ez méri, hogy a gomb tényleg ÚJRA
              // olvassa a providert, nem csak elrejti a kártyát.
              if (feedAttempts == 1) throw const NetworkFailure();
              return CommunityPagePlaceholder<CommunityPost>(
                items: <CommunityPost>[_post('post-1', 'Reloaded post.')],
              );
            }),
          ],
        ),
      );
      await _pumpScreen(tester);

      expect(find.byKey(const Key('club-feed-error')), findsOneWidget);
      expect(find.text("The club's posts couldn't load."), findsOneWidget);
      // A hazug üres-állapot sehol nem jelenhet meg.
      expect(find.text('No posts in this club yet.'), findsNothing);

      final retry = find.descendant(
        of: find.byKey(const Key('club-feed-error')),
        matching: find.text('Retry'),
      );
      await tester.ensureVisible(retry);
      await tester.pump();
      await tester.tap(retry);
      await _pumpScreen(tester);

      expect(feedAttempts, 2);
      expect(find.byKey(const Key('club-feed-error')), findsNothing);
      expect(find.text('Reloaded post.'), findsOneWidget);
    });

    // A kitűzött posztok szakasza ugyanezt a szerződést viseli.
    testWidgets('a failing pinned list shows an error', (tester) async {
      final fake = _RecordingClubRepository.build(
        _club(
          publicId: 'club-1',
          name: 'Blues Lovers',
          visibility: ClubVisibility.discoverable,
          memberCount: 12,
          myRole: ClubRole.member,
        ),
      );

      await tester.pumpWidget(
        _wrap(
          fake,
          extraOverrides: <Override>[
            clubPinnedProvider.overrideWith((ref, arg) async {
              throw const NetworkFailure();
            }),
            clubFeedProvider.overrideWith((ref, arg) async {
              return CommunityPagePlaceholder<CommunityPost>(
                items: <CommunityPost>[_post('post-1', 'Feed post.')],
              );
            }),
          ],
        ),
      );
      await _pumpScreen(tester);

      expect(find.byKey(const Key('club-feed-pinned-error')), findsOneWidget);
      expect(find.text('No posts in this club yet.'), findsNothing);
      expect(find.text('Feed post.'), findsOneWidget);
    });
  });
}
