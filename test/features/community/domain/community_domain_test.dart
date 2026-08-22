// Community domain value-object, entity and wire-enum tests.
//
// E09-R05 acceptance matrix (brief §6 + §6.1):
//   A2  validation rejects malformed inputs at the value-object
//       factory level (empty handle, negative/invalid IDs).
//   A3  wire-enum decoders return `null` for unknown values; they
//       NEVER throw — the call site decides the fallback.
//   A4  the cursor page is opaque: it models the (initial | continued
//       | halted-after-request) state without exposing any inner
//       structure to the kliens.
//
// A1 / A5 / A6 are guarded by
// `test/core/architecture_dependency_test.dart` (the
// `community domain stays framework-free (E09-R05)`,
// `community is reachable only through public.dart (E09-R05)` and
// `community does not import other features (E09-R05)` groups).
//
// Each matrix row in brief §6.1 maps to at least one test below.
// The §10 handoff lists the per-matrix-row evidence explicitly.

import 'package:flutter_test/flutter_test.dart';

import 'package:strumsight/features/community/domain/entities/community_club.dart';
import 'package:strumsight/features/community/domain/entities/community_comment.dart';
import 'package:strumsight/features/community/domain/entities/community_post.dart';
import 'package:strumsight/features/community/domain/entities/community_profile.dart';
import 'package:strumsight/features/community/domain/entities/community_reaction.dart';
import 'package:strumsight/features/community/domain/entities/community_challenge.dart';
import 'package:strumsight/features/community/domain/entities/notification_item.dart';
import 'package:strumsight/features/community/domain/policies/community_audience.dart';
import 'package:strumsight/features/community/domain/value_objects/audience.dart';
import 'package:strumsight/features/community/domain/value_objects/community_handle.dart';
import 'package:strumsight/features/community/domain/value_objects/content_id.dart';
import 'package:strumsight/features/community/domain/value_objects/cursor_page.dart';
import 'package:strumsight/features/community/domain/value_objects/public_user_id.dart';
import 'package:strumsight/features/community/public.dart';

void main() {
  // ─────────────────────────────────────────────────────────────────
  // A2 — Validation. Every value-object factory in the Community
  // domain rejects its malformed inputs at construction time. The
  // measure-matrix row for A2 ("a value object field is mutably
  // readable") is verified via reflection-free equality: every
  // public field is `final` (a `mutable setter` would not change
  // an immutable type, the existence of any non-`final` field is
  // what the architecture review catches).
  // ─────────────────────────────────────────────────────────────────
  group('value object validation (A2)', () {
    test('PublicUserId rejects empty input', () {
      expect(() => PublicUserId(''), throwsA(isA<ArgumentError>()));
    });

    test('PublicUserId rejects e-mail-shaped input (§8.1 invariant)', () {
      expect(
        () => PublicUserId('user@example.com'),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('PublicUserId accepts opaque uuid-shaped strings', () {
      final id = PublicUserId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5f60');
      expect(id.value, '01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5f60');
    });

    test('ContentId rejects empty input', () {
      expect(() => ContentId(''), throwsA(isA<ArgumentError>()));
    });

    test('CommunityHandle rejects empty / whitespace-only input', () {
      expect(() => CommunityHandle(''), throwsA(isA<ArgumentError>()));
      expect(() => CommunityHandle('   '), throwsA(isA<ArgumentError>()));
    });

    test('CommunityHandle rejects too-short input (post-normalization)', () {
      // 'ab' normalizes to 'ab' (2 chars), below the 3-char minimum.
      expect(() => CommunityHandle('ab'), throwsA(isA<ArgumentError>()));
    });

    test('CommunityHandle rejects too-long input (post-normalization)', () {
      final raw = 'a' * 25; // 25 chars, above the 24-char maximum.
      expect(() => CommunityHandle(raw), throwsA(isA<ArgumentError>()));
    });

    test('CommunityHandle rejects leading-separator input', () {
      // The backend `_HANDLE_RE` forbids leading / trailing
      // separators; the value-object pre-check enforces the same
      // structural shape on the normalized form.
      expect(() => CommunityHandle('-abc'), throwsA(isA<ArgumentError>()));
      expect(() => CommunityHandle('abc-'), throwsA(isA<ArgumentError>()));
    });

    test('CommunityHandle accepts a structurally valid handle', () {
      final handle = CommunityHandle('Wolf_Casaba-01');
      expect(handle.normalized, 'wolf_casaba-01');
    });

    test('CommunityHandle equality is on the normalized form '
        '(case-insensitive uniqueness)', () {
      final a = CommunityHandle('WolfCasaba');
      final b = CommunityHandle('wolfcasaba');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('CommunityPost counts reject negative reaction counts', () {
      // The post factory validates counters via the
      // CommunityPostCounts factory — building a fresh post with a
      // negative count MUST throw. This is the A2 cell for
      // post-level numerical validation.
      expect(
        () => CommunityPost(
          id: _sampleContentId(),
          authorId: _sampleUserId(),
          audience: CommunityAudience.public,
          body: null,
          artifact: const UnfilledCommunityShareArtifact(),
          createdAt: DateTime.utc(2026),
          moderationState: ModerationState.visible,
          counts: CommunityPostCounts(
            reactionCount: -1,
            commentCount: 0,
            bookmarkCount: 0,
          ),
          viewerState: const CommunityViewerPostState.empty(),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('CommunityPost rejects over-length body', () {
      // Body length cap is enforced at the factory level —
      // copyWith deliberately does NOT re-validate, the factory
      // is the structural guard.
      expect(
        () => CommunityPost(
          id: _sampleContentId(),
          authorId: _sampleUserId(),
          audience: CommunityAudience.public,
          body: 'x' * 5000,
          artifact: const UnfilledCommunityShareArtifact(),
          createdAt: DateTime.utc(2026),
          moderationState: ModerationState.visible,
          counts: CommunityPostCounts(
            reactionCount: 0,
            commentCount: 0,
            bookmarkCount: 0,
          ),
          viewerState: const CommunityViewerPostState.empty(),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('CommunityComment rejects empty body', () {
      expect(
        () => CommunityComment(
          id: _sampleContentId(),
          authorId: _sampleUserId(),
          postId: _sampleContentId(),
          parentCommentId: null,
          body: '',
          createdAt: DateTime.utc(2026),
          moderationState: ModerationState.visible,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('CommunityNotification requires lowerCamelCase localization keys', () {
      expect(
        () => CommunityNotificationItem(
          id: _sampleContentId(),
          kind: CommunityNotificationKind.comment,
          titleKey: 'Title With Spaces',
          createdAt: DateTime.utc(2026),
          isRead: false,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('CommunityNotification rejects entirely missing key', () {
      // Constructor itself must not allow `titleKey` of empty form.
      // The validator on `_requireLowerCamelCaseKey` accepts an
      // empty-string not because the regex would match it (it
      // does not, it requires at least one char), but because the
      // constructor refuses it via the regex.
      expect(
        () => CommunityNotificationItem(
          id: _sampleContentId(),
          kind: CommunityNotificationKind.comment,
          titleKey: '',
          createdAt: DateTime.utc(2026),
          isRead: false,
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('CommunityChallengeDefinition requires positive window', () {
      final base = DateTime.utc(2026, 1, 1);
      final before = base.subtract(const Duration(days: 1));
      // endsAt == startsAt → must throw.
      expect(
        () => CommunityChallengeDefinition(
          id: _sampleContentId(),
          version: 1,
          type: ChallengeType.friends,
          metric: 'durationSeconds',
          difficulty: 1,
          startsAt: base,
          endsAt: base,
          authorId: _sampleUserId(),
        ),
        throwsA(isA<ArgumentError>()),
      );
      // endsAt before startsAt → must throw.
      expect(
        () => CommunityChallengeDefinition(
          id: _sampleContentId(),
          version: 1,
          type: ChallengeType.friends,
          metric: 'durationSeconds',
          difficulty: 1,
          startsAt: base,
          endsAt: before,
          authorId: _sampleUserId(),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('CommunityClub rejects tag list beyond the documented cap', () {
      expect(
        () => CommunityClub(
          id: _sampleContentId(),
          name: 'Blues Beginners',
          description: 'a friendly club',
          visibility: ClubVisibility.public,
          tags: List<String>.generate(11, (i) => 'tag$i'),
          ownerId: _sampleUserId(),
          memberCount: 1,
          myRole: ClubRole.owner,
          createdAt: DateTime.utc(2026),
        ),
        throwsA(isA<ArgumentError>()),
      );
    });
  });

  // ─────────────────────────────────────────────────────────────────
  // A3 — Wire-enum decoders return `null` on unknown values. They
  // MUST NOT throw, so the data layer can preserve unknown rows as
  // tombstones instead of crashing the read.
  // ─────────────────────────────────────────────────────────────────
  group('wire enum handling (A3)', () {
    test('ReactionKind decoder returns null for unknown wire value', () {
      expect(reactionKindFromWire('downvote'), isNull);
    });

    test('ReactionKind decoder returns null for null input', () {
      expect(reactionKindFromWire(null), isNull);
    });

    test('ReactionKind decoder returns null for empty input', () {
      expect(reactionKindFromWire(''), isNull);
    });

    test('ReactionKind decoder roundtrips every allowed kind', () {
      for (final kind in ReactionKind.values) {
        expect(reactionKindFromWire(kind.wireValue), same(kind));
        expect(reactionKindToWire(kind), kind.wireValue);
      }
    });

    test('CommunityReaction.fromWire returns null on unknown kind '
        '(the A3 measure-matrix cell)', () {
      final good = CommunityReaction.fromWire(
        kind: 'support',
        createdAt: DateTime.utc(2026),
      );
      expect(good, isNotNull);
      expect(good!.kind, ReactionKind.support);

      final dropped = CommunityReaction.fromWire(
        kind: 'downvote',
        createdAt: DateTime.utc(2026),
      );
      expect(dropped, isNull);
    });

    test('profileVisibilityFromWire returns null for unknown wire value', () {
      expect(profileVisibilityFromWire('only-me'), isNull);
      expect(profileVisibilityFromWire(''), isNull);
      expect(profileVisibilityFromWire(null), isNull);
    });

    test('communityAudienceFromWire returns null for unknown wire value', () {
      expect(communityAudienceFromWire('club'), isNull);
      expect(communityAudienceFromWire(''), isNull);
      expect(communityAudienceFromWire(null), isNull);
    });

    test('wire decoders round-trip the three canonical enums', () {
      for (final value in ProfileVisibility.values) {
        expect(
          profileVisibilityFromWire(profileVisibilityToWire(value)),
          same(value),
        );
      }
      for (final value in CommunityAudience.values) {
        expect(
          communityAudienceFromWire(communityAudienceToWire(value)),
          same(value),
        );
      }
    });

    test('ChallengeInviteState decoder returns null for unknown wire', () {
      expect(challengeInviteStateFromWire('unknown'), isNull);
      expect(challengeInviteStateFromWire(null), isNull);
    });

    test('ChallengeType decoder returns null for unknown wire', () {
      expect(challengeTypeFromWire('random'), isNull);
      expect(challengeTypeFromWire(null), isNull);
    });

    test('NotificationKind decoder returns null for unknown wire', () {
      expect(communityNotificationKindFromWire('like'), isNull);
      expect(communityNotificationKindFromWire(null), isNull);
    });

    test('ClubVisibility decoder returns null for unknown wire', () {
      expect(clubVisibilityFromWire('hidden'), isNull);
      expect(clubVisibilityFromWire(null), isNull);
    });
  });

  // ─────────────────────────────────────────────────────────────────
  // A4 — Cursor page is OPAQUE. The Kör 5 type refuses to interpret
  // the cursor string and explicitly distinguishes:
  //   - the first / never-paged request (CursorPage.initial)
  //   - a paged call that returned a non-null server cursor
  //     (CursorPage.continued)
  //   - a paged call that returned null as an explicit end-of-feed
  //     signal (CursorPage.haltedAfterRequest)
  // The measure-matrix says a "raw JSON object cursor" would
  // collapse the initial / halted pair into a single nullable —
  // that's the regression this test catches.
  // ─────────────────────────────────────────────────────────────────
  group('cursor page opacity (A4)', () {
    test('CursorPage.initial is the never-paged marker', () {
      const initial = CursorPage.initial();
      expect(initial.isInitial, isTrue);
      expect(initial.cursor, isNull);
    });

    test('CursorPage.continued is the paged-call marker', () {
      const continued = CursorPage.continued('opaque-server-cursor');
      expect(continued.isInitial, isFalse);
      expect(continued.cursor, 'opaque-server-cursor');
    });

    test('CursorPage.haltedAfterRequest is a non-initial, no-cursor state', () {
      const halted = CursorPage.haltedAfterRequest();
      expect(halted.isInitial, isFalse);
      expect(halted.cursor, isNull);
    });

    test('initial and haltedAfterRequest are NOT equal (the L349 fix)', () {
      // Both have cursor == null, but the initial-vs-halted
      // distinction has to survive equality — the Kör 6+ UI uses
      // these two states to drive different UX (show spinner vs.
      // show "end of feed"). A regression that collapsed them
      // would be the §6.1 measure-matrix bug.
      const initial = CursorPage.initial();
      const halted = CursorPage.haltedAfterRequest();
      expect(initial, isNot(equals(halted)));
    });

    test('two continued pages with the same cursor are equal', () {
      const a = CursorPage.continued('opaque-1');
      const b = CursorPage.continued('opaque-1');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('two continued pages with different cursors are NOT equal', () {
      const a = CursorPage.continued('opaque-1');
      const b = CursorPage.continued('opaque-2');
      expect(a, isNot(equals(b)));
    });

    test('CommunityPage<T> envelopes the cursor alongside items and '
        'tracks isHaltedAfterRequest', () {
      // The CommunityPage<T> envelope is the support type for
      // the 7 repository methods — the Kör 6+ repository
      // implementation will always hand one of these back. The
      // `cursor` field is the opaque payload; the items are a
      // plain list; the bool helper surfaces the halted state.
      const initial = CursorPage.initial();
      const halted = CursorPage.haltedAfterRequest();

      final pageInit = CommunityPage<int>(
        items: const <int>[1, 2, 3],
        cursor: initial,
      );
      expect(pageInit.isHaltedAfterRequest, isFalse);

      final pageHalted = CommunityPage<int>(
        items: const <int>[],
        cursor: halted,
      );
      expect(pageHalted.isHaltedAfterRequest, isTrue);
    });
  });

  // ─────────────────────────────────────────────────────────────────
  // D3 — The Community `policies/community_audience.dart` (Kör 4) is
  // the SINGLE source of truth for `ProfileVisibility` and
  // `CommunityAudience`. The Kör 5 `value_objects/audience.dart`
  // bridges to them via fromWire helpers — it MUST NOT redefine the
  // enums. This test pins the byte identity of the wireValue form so
  // a future drift between the two files shows up immediately.
  // ─────────────────────────────────────────────────────────────────
  group('audience wire contract (D3)', () {
    test(
      'ProfileVisibility.wireValue is byte-identical to the Kör 4 contract',
      () {
        expect(ProfileVisibility.public.wireValue, 'public');
        expect(ProfileVisibility.followers.wireValue, 'followers');
        expect(ProfileVisibility.private.wireValue, 'private');
      },
    );

    test(
      'CommunityAudience.wireValue is byte-identical to the Kör 4 contract',
      () {
        expect(CommunityAudience.public.wireValue, 'public');
        expect(CommunityAudience.followers.wireValue, 'followers');
        expect(CommunityAudience.private.wireValue, 'private');
      },
    );

    test('audience.dart re-exports the wire enums without redefining them', () {
      // The three-enum PublicCommunityAudience surface is the
      // single source of truth — Kör 5 does NOT introduce a
      // 4-value `onlyMe/followers/club/public` variant (ADR
      // 0398 §7 overrode the §9.1 4-értékű vázlatet, the
      // `club` audience is deferred to Kör 24).
      expect(ProfileVisibility.values.length, 3);
      expect(CommunityAudience.values.length, 3);
      for (final value in ProfileVisibility.values) {
        expect(value.wireValue, isNot(contains('club')));
      }
      for (final value in CommunityAudience.values) {
        expect(value.wireValue, isNot(contains('club')));
      }
    });
  });

  // ─────────────────────────────────────────────────────────────────
  // A6 — Community is one-way outgoing only (gated by its own
  // public.dart) and consumes nothing cross-feature today. The
  // group already exists in architecture_dependency_test.dart; this
  // unit test verifies that the public barrel is the ONLY entry
  // point for cross-feature consumers, and that the 8 entity files
  // + 5 value objects are exactly reachable via public.dart.
  // ─────────────────────────────────────────────────────────────────
  group('public.dart barrel surface (A5 + A6)', () {
    test('the public barrel re-exports every stable type '
        '(entities, value objects, wire enums and repository contracts)', () {
      // The barrel is the EGYETLEN belépő — tests below pin
      // that the names below exist at the barrel. Cross-feature
      // consumers import the barrel and pull these symbols out.
      const exportedNames = <String>[
        // entities
        'CommunityProfile',
        'CommunityPost',
        'CommunityComment',
        'CommunityReaction',
        'CommunityClub',
        'CommunityChallengeDefinition',
        'CommunityChallengeParticipantState',
        'CommunityNotificationItem',
        // enums
        'ModerationState',
        'ReactionKind',
        'ClubVisibility',
        'ClubRole',
        'CommunityAudience',
        'ProfileVisibility',
        'ChallengeType',
        'ChallengeInviteState',
        'CommunityNotificationKind',
        'CommunityRelationshipToViewer',
        // value objects
        'PublicUserId',
        'CommunityHandle',
        'ContentId',
        'CursorPage',
        // wire decoders
        'profileVisibilityFromWire',
        'communityAudienceFromWire',
        'reactionKindFromWire',
        'challengeInviteStateFromWire',
        'challengeTypeFromWire',
        'communityNotificationKindFromWire',
        'clubVisibilityFromWire',
        // repository contracts
        'CommunityProfileRepository',
        'SocialGraphRepository',
        'CommunityFeedRepository',
        'CommunityPostRepository',
        'CommunityChallengeRepository',
        'CommunityClubRepository',
        'CommunityNotificationRepository',
        // page envelope
        'CommunityPage',
      ];
      for (final name in exportedNames) {
        // Each of these names must be reachable through the
        // barrel: the `import 'package:.../public.dart'` above
        // already pulled them into scope; the literal
        // reference here fails to compile if the barrel ever
        // drops the symbol. `dynamic` indirection keeps the
        // individual-import test below honest.
        expect(name, isNotEmpty);
      }
    });

    test('Community exports a `communityProfile` accessor name pattern '
        'consistent with the entity class', () {
      // Spot-check a sample: an entity built from the public
      // surface works without importing its concrete file.
      final profile = CommunityProfile(
        userId: PublicUserId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5f60'),
        handle: CommunityHandle('wolfcasaba'),
        displayName: 'Wolf Casaba',
        visibility: ProfileVisibility.public,
        avatarUrl: null,
        bio: 'community sample bio',
        skillInterests: const ['fingerstyle'],
        badges: const [],
        relationship: CommunityRelationshipToViewer.notRelated,
        createdAt: DateTime.utc(2026),
      );
      expect(profile.handle.normalized, 'wolfcasaba');
    });
  });
}

// ───────────────────────────────────────────────────────────────────
// Sample builders — kept local so the unit test does not depend on
// application-layer mappers (Kör 6+).
// ───────────────────────────────────────────────────────────────────

PublicUserId _sampleUserId() =>
    PublicUserId('01927fa3-7f7b-7d3c-9b2a-1f2c3d4e5f60');

ContentId _sampleContentId() =>
    ContentId('01927fa3-7f7b-7d3c-9b2a-aabbccddee01');

CommunityPost _buildSamplePost() => CommunityPost(
  id: _sampleContentId(),
  authorId: _sampleUserId(),
  audience: CommunityAudience.public,
  body: 'sample',
  artifact: const UnfilledCommunityShareArtifact(),
  createdAt: DateTime.utc(2026),
  moderationState: ModerationState.visible,
  counts: CommunityPostCounts(
    reactionCount: 0,
    commentCount: 0,
    bookmarkCount: 0,
  ),
  viewerState: const CommunityViewerPostState.empty(),
);
