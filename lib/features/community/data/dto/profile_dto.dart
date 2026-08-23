/// JSON <-> domain mapping for the Community profile (E09-R06, ADR 0400
/// §2, §3, §4).
///
/// The boundary value object the rest of the app reads is
/// ``CommunityProfile`` (Kör 5, ADR 0399 §1). The wire shape is the
/// backend ``CommunityProfileOut`` (E09-R02 + E09-R06): public UUID,
/// display name, created-at, handle. The DTO hides the gap so the
/// repository / controller never have to know about JSON keys.
///
/// **Why this lives in its own file:** the domain layer is forbidden
/// from importing ``dart:convert`` / Dio — architecture-dependency
/// guard, Kör 5 group). The data layer is the only place JSON
/// parsing may happen, and the DTO is the seam — the entity factory
/// in the domain layer receives already-decoded values.
///
/// **Why the form sends a NARROW payload:** the backend ``extra="forbid"``
/// contract (ADR 0400 §5.4 / A8) rejects any field the body does not
/// whitelist. ``toCreatePayload`` and ``toUpdatePayload`` enumerate
/// the allowed fields explicitly — bio / skillInterests / avatarUrl
/// are UI-only this round (ADR 0400 §4), so they DO NOT cross the
/// wire even when the user has filled them in.
library;

import '../../domain/entities/community_profile.dart';
import '../../domain/policies/community_audience.dart';
import '../../domain/value_objects/community_handle.dart';
import '../../domain/value_objects/public_user_id.dart';

/// Decoded shape of the backend ``CommunityProfileOut`` response.
///
/// The fields are non-nullable ONLY where the backend always
/// returns a value (``public_id``, ``created_at``). ``display_name``
/// and ``handle`` are nullable in the wire shape (the DB columns
/// are nullable) and we model them as ``String?`` here so the
/// decode can survive a pre-handle / pre-display row without
/// throwing.
class CommunityProfileDto {
  const CommunityProfileDto({
    required this.publicId,
    required this.displayName,
    required this.createdAt,
    required this.handle,
  });

  final String publicId;
  final String? displayName;
  final DateTime createdAt;
  final String? handle;

  /// Parse the wire JSON into the DTO. The wire shape is the
  /// Pydantic ``CommunityProfileOut`` (whitelist-only).
  ///
  /// ``public_id`` is parsed as a string (the backend returns a
  /// UUID literal); the value object factory validates the
  /// structure downstream.
  factory CommunityProfileDto.fromJson(Map<String, Object?> json) {
    final publicId = json['public_id'];
    final createdAt = json['created_at'];
    if (publicId is! String) {
      throw const FormatException(
        'community profile wire: missing string public_id',
      );
    }
    if (createdAt is! String) {
      throw const FormatException(
        'community profile wire: missing string created_at',
      );
    }
    final parsed = DateTime.tryParse(createdAt);
    if (parsed == null) {
      throw FormatException(
        'community profile wire: unparseable created_at "$createdAt"',
      );
    }
    return CommunityProfileDto(
      publicId: publicId,
      displayName: json['display_name'] as String?,
      createdAt: parsed,
      handle: json['handle'] as String?,
    );
  }

  /// Promote the DTO into a domain [CommunityProfile].
  ///
  /// Several entity fields are not in the wire shape:
  ///
  /// * [CommunityProfile.avatarUrl] — backend has no column (UI-only
  ///   this round, ADR 0400 §4).
  /// * [CommunityProfile.bio] — backend has no column (UI-only).
  /// * [CommunityProfile.skillInterests] / [CommunityProfile.badges] —
  ///   backend has no column (UI-only).
  /// * [CommunityProfile.relationship] — the Kör 7 social-graph
  ///   repository populates this from the follow / block data; for
  ///   Kör 6 the viewer is always ``notRelated`` because the
  ///   fetched profile IS the viewer's own (the only path that
  ///   produces a ``createProfile`` / ``updateProfile`` response is
  ///   the ``/community/profiles/me`` endpoint, and the viewer is
  ///   the owner).
  /// * [CommunityProfile.visibility] — the privacy row is not
  ///   returned by the profile endpoint. The Kör 4
  ///   ``/community/privacy`` endpoint owns it; the onboarding flow
  ///   already knows the value the user just submitted, so the
  ///   controller passes it through [CommunityProfile.copyWith]
  ///   after the round-trip.
  ///
  /// The factory's parameter list makes the "where the rest of the
  /// values come from" contract explicit so a future reader does
  /// not have to grep the file for default-init.
  CommunityProfile toDomain({
    required CommunityHandle handle,
    required String displayName,
    required ProfileVisibility visibility,
  }) {
    return CommunityProfile(
      userId: PublicUserId(publicId),
      handle: handle,
      displayName: displayName,
      visibility: visibility,
      avatarUrl: null,
      bio: null,
      skillInterests: const <String>[],
      badges: const <String>[],
      relationship: CommunityRelationshipToViewer.notRelated,
      createdAt: createdAt,
    );
  }
}

/// Builder for the ``POST /community/profiles/me`` request body.
///
/// The function is the EXACT mirror of the backend
/// ``CommunityProfileCreate`` schema (ADR 0400 §5.4 ``extra="forbid"``
/// contract): no ``user_id`` / ``profile_id`` field, no UI-only
/// fields (bio / skillInterests / avatarUrl). A future migration
/// that adds the corresponding DB columns will extend this map
/// in one place.
Map<String, Object?> communityProfileCreatePayload({
  required CommunityHandle handle,
  required String displayName,
  required ProfileVisibility visibility,
  required CommunityAudience audienceDefault,
}) {
  return <String, Object?>{
    'handle': handle.value,
    'display_name': displayName,
    'visibility': visibility.wireValue,
    'audience_default': audienceDefault.wireValue,
  };
}

/// Builder for the ``PUT /community/profiles/me`` request body.
///
/// The schema (ADR 0400 §3) accepts ONLY ``display_name``; the
/// privacy fields are a separate endpoint (Kör 4 ``privacy.py``,
/// not wired into the module in this round). The narrow body is
/// the A8 measure-matrix contract on the update path: no field
/// the server reads to identify the row (no user_id, no
/// profile_id).
Map<String, Object?> communityProfileUpdatePayload({
  required String displayName,
}) {
  return <String, Object?>{'display_name': displayName};
}
