/// JSON <-> domain mapping for Community posts (feed + post wiring).
///
/// The wire shape is the backend ``PostOut`` (``posts.py``) — and its
/// byte-identical twin ``FeedPostItem`` (``feed.py``): ``public_id``,
/// ``author_public_id``, ``audience``, ``club_id``, ``body``,
/// ``artifact_type``, ``artifact_schema_version``, ``artifact_payload``,
/// ``moderation_state``, ``created_at``, ``resource_version``,
/// ``deleted_at``. The DTO hides the gap so the repository never has
/// to know about JSON keys — the same seam ``profile_dto.dart`` is.
///
/// **Artifact casing (measured on the backend, not assumed):** the
/// Dart ``ShareArtifact.toJson()`` emits camelCase keys
/// (``schemaVersion``, ``sourceId``) while the backend Pydantic
/// models in ``schemas/artifacts.py`` are snake_case
/// (``schema_version``, ``source_id``) and wrap the artifact in a
/// ``{"artifact": {...}}`` envelope (``ShareArtifactEnvelope`` —
/// ``test_post_service.py::test_artifact_persists_through_round_trip``
/// pins both). [communityArtifactToWire] / [communityArtifactFromWire]
/// are the single place where the two shapes meet; a key that only
/// one side knows fails loudly at parse time on the side that owns it
/// (``extra="forbid"`` server-side, ``ShareArtifact.fromJson`` here).
///
/// **Fields the wire does not carry:** ``counts`` (reaction / comment
/// / bookmark totals) and ``viewerState`` (my bookmark / my reaction)
/// are NOT on ``PostOut`` / ``FeedPostItem`` today. The DTO promotes
/// them as zero / empty — a truthful "unknown" for the card layer, not
/// a fabricated number. A backend round that adds them extends
/// [CommunityPostDto.fromJson] in lockstep.
library;

import '../../domain/entities/community_post.dart';
import '../../domain/entities/moderation_state.dart';
import '../../domain/entities/share_artifact.dart';
import '../../domain/policies/community_audience.dart';
import '../../domain/value_objects/audience.dart';
import '../../domain/value_objects/content_id.dart';
import '../../domain/value_objects/public_user_id.dart';

/// Decoded shape of the backend ``PostOut`` / ``FeedPostItem`` row.
class CommunityPostDto {
  const CommunityPostDto({
    required this.publicId,
    required this.authorPublicId,
    required this.audience,
    required this.clubId,
    required this.body,
    required this.artifactType,
    required this.artifactSchemaVersion,
    required this.artifactPayload,
    required this.moderationState,
    required this.createdAt,
    required this.resourceVersion,
    required this.deletedAt,
  });

  final String publicId;
  final String authorPublicId;
  final String audience;
  final int? clubId;
  final String body;
  final String? artifactType;
  final int? artifactSchemaVersion;
  final Map<String, Object?>? artifactPayload;
  final String moderationState;
  final DateTime createdAt;

  /// The Kör 11 optimistic-concurrency token (``updated_at`` on the
  /// row). Echoed back on ``PATCH`` as ``resource_version``. The
  /// domain [CommunityPost] has no slot for it — the DTO keeps it so
  /// a caller that needs the token can read it off the DTO.
  final DateTime resourceVersion;
  final DateTime? deletedAt;

  /// Parse the wire JSON into the DTO. Every required key is
  /// validated structurally; a malformed row throws [FormatException]
  /// which ``ApiClient`` maps to ``FailureCode.networkBadResponse``.
  factory CommunityPostDto.fromJson(Map<String, Object?> json) {
    final publicId = json['public_id'];
    final authorPublicId = json['author_public_id'];
    final audience = json['audience'];
    final body = json['body'];
    final moderationState = json['moderation_state'];
    final createdAt = json['created_at'];
    final resourceVersion = json['resource_version'];
    if (publicId is! String || publicId.isEmpty) {
      throw const FormatException(
        'community post wire: missing string public_id',
      );
    }
    if (authorPublicId is! String || authorPublicId.isEmpty) {
      throw const FormatException(
        'community post wire: missing string author_public_id',
      );
    }
    if (audience is! String) {
      throw const FormatException(
        'community post wire: missing string audience',
      );
    }
    if (body is! String) {
      throw const FormatException('community post wire: missing string body');
    }
    if (moderationState is! String) {
      throw const FormatException(
        'community post wire: missing string moderation_state',
      );
    }
    final clubIdRaw = json['club_id'];
    final artifactTypeRaw = json['artifact_type'];
    final artifactSchemaVersionRaw = json['artifact_schema_version'];
    final artifactPayloadRaw = json['artifact_payload'];
    return CommunityPostDto(
      publicId: publicId,
      authorPublicId: authorPublicId,
      audience: audience,
      clubId: clubIdRaw is int ? clubIdRaw : null,
      body: body,
      artifactType: artifactTypeRaw is String ? artifactTypeRaw : null,
      artifactSchemaVersion: artifactSchemaVersionRaw is int
          ? artifactSchemaVersionRaw
          : null,
      artifactPayload: artifactPayloadRaw is Map
          ? _stringKeyed(artifactPayloadRaw)
          : null,
      moderationState: moderationState,
      createdAt: _requireIsoDate(createdAt, 'created_at'),
      resourceVersion: _requireIsoDate(resourceVersion, 'resource_version'),
      deletedAt: _optionalIsoDate(json['deleted_at'], 'deleted_at'),
    );
  }

  /// Promote the DTO into a domain [CommunityPost].
  ///
  /// * ``audience`` — an unknown wire value is a contract violation
  ///   (the Kör 4 enums are byte-identical on both sides), so it
  ///   throws [FormatException] rather than silently widening to
  ///   ``public``.
  /// * ``moderation_state`` — the backend literal is
  ///   ``visible | removed``; an unknown value collapses to
  ///   [ModerationState.removed] (the A3 "unknown state is a
  ///   tombstone, never a body" rule). A non-null ``deleted_at``
  ///   is a tombstone too.
  /// * artifact — decoded through [communityArtifactFromWire] +
  ///   ``ShareArtifact.fromJson``; a missing, malformed or
  ///   unknown-typed artifact becomes [UnfilledCommunityShareArtifact]
  ///   so the feed's A5 "unknown type renders the fallback card"
  ///   cell holds at the data boundary as well.
  CommunityPost toDomain() {
    final audienceValue = communityAudienceFromWire(audience);
    if (audienceValue == null) {
      throw FormatException(
        'community post wire: unknown audience "$audience"',
      );
    }
    final moderation = deletedAt != null
        ? ModerationState.removed
        : (moderationStateFromWire(moderationState) ?? ModerationState.removed);
    return CommunityPost(
      id: ContentId(publicId),
      authorId: PublicUserId(authorPublicId),
      audience: audienceValue,
      body: body,
      artifact: _decodeArtifact(artifactPayload),
      createdAt: createdAt,
      editedAt: null,
      moderationState: moderation,
      counts: CommunityPostCounts(
        reactionCount: 0,
        commentCount: 0,
        bookmarkCount: 0,
      ),
      viewerState: const CommunityViewerPostState.empty(),
    );
  }
}

/// Build the ``POST /community/posts`` payload.
///
/// The ``extra="forbid"`` contract on ``CreatePostRequest`` is why
/// the map enumerates its keys explicitly. ``artifact`` is omitted
/// (not sent as ``null``) when the caller has none — the backend
/// treats both the same, but omitting keeps the request minimal.
Map<String, Object?> communityPostCreatePayload({
  required CommunityAudience audience,
  required String? body,
  required Map<String, Object?>? artifactJson,
  required String idempotencyKey,
}) {
  final artifact = artifactJson == null || artifactJson.isEmpty
      ? null
      : communityArtifactToWire(artifactJson);
  return <String, Object?>{
    'audience': audience.wireValue,
    // The backend requires ``body`` (``min_length=1``); the domain
    // allows a null (artifact-only) body. A null is sent as an empty
    // string so the backend's 422 — not a client-side guess — is the
    // verdict on an artifact-only post.
    'body': body ?? '',
    if (artifact != null) 'artifact': artifact,
    'idempotency_key': idempotencyKey,
  };
}

/// Wrap a Dart ``ShareArtifact.toJson()`` map into the backend
/// ``ShareArtifactEnvelope`` shape: ``{"artifact": {snake_case…}}``.
Map<String, Object?> communityArtifactToWire(Map<String, Object?> json) {
  return <String, Object?>{'artifact': _convertKeys(json, _camelToSnake)};
}

/// Reverse of [communityArtifactToWire]: unwrap the backend
/// ``artifact_payload`` envelope and re-key it to the camelCase
/// shape ``ShareArtifact.fromJson`` expects. Returns ``null`` when
/// the payload is absent or not an envelope.
Map<String, Object?>? communityArtifactFromWire(Object? payload) {
  if (payload is! Map) return null;
  final inner = payload['artifact'];
  if (inner is! Map) return null;
  final converted = _convertKeys(_stringKeyed(inner), _snakeToCamel);
  return converted is Map<String, Object?> ? converted : null;
}

CommunityShareArtifact _decodeArtifact(Map<String, Object?>? payload) {
  final json = communityArtifactFromWire(payload);
  if (json == null) return UnfilledCommunityShareArtifact();
  try {
    return ShareArtifact.fromJson(json);
  } on Object {
    return UnfilledCommunityShareArtifact();
  }
}

Object? _convertKeys(Object? value, String Function(String key) rename) {
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries)
        if (entry.key is String)
          rename(entry.key as String): _convertKeys(entry.value, rename),
    };
  }
  if (value is List) {
    return <Object?>[for (final item in value) _convertKeys(item, rename)];
  }
  return value;
}

String _camelToSnake(String key) {
  final buffer = StringBuffer();
  for (var i = 0; i < key.length; i++) {
    final char = key[i];
    final isUpper = char != char.toLowerCase() && char == char.toUpperCase();
    if (isUpper && i > 0) buffer.write('_');
    buffer.write(char.toLowerCase());
  }
  return buffer.toString();
}

String _snakeToCamel(String key) {
  final parts = key.split('_');
  if (parts.length == 1) return key;
  final buffer = StringBuffer(parts.first);
  for (final part in parts.skip(1)) {
    if (part.isEmpty) continue;
    buffer.write(part[0].toUpperCase());
    buffer.write(part.substring(1));
  }
  return buffer.toString();
}

Map<String, Object?> _stringKeyed(Map<Object?, Object?> raw) {
  return <String, Object?>{
    for (final entry in raw.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };
}

DateTime _requireIsoDate(Object? raw, String field) {
  if (raw is! String) {
    throw FormatException('community post wire: missing string $field');
  }
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    throw FormatException('community post wire: unparseable $field "$raw"');
  }
  return parsed;
}

DateTime? _optionalIsoDate(Object? raw, String field) {
  if (raw == null) return null;
  return _requireIsoDate(raw, field);
}
