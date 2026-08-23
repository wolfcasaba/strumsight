/// Wire-enum bridge for Community audiences and profile visibilities
/// (E09-R05, ADR 0399 4. döntés, SDD §9.1, ADR 0398 §7).
///
/// The single source of truth for the two wire-enums
/// (`ProfileVisibility`, `CommunityAudience`) is
/// `lib/features/community/domain/policies/community_audience.dart`
/// (Kör 4). This module does NOT redefine them — it imports them and
/// provides the **controllált, sosem dobó** wire-string decoder the
/// Kör 5 entities rely on (A3, brief §0.0 D3). JSON binding lands in
/// Kör 6's `data/repositories/`, which is why the decoder returns
/// `null` for unknown wire values instead of throwing — the caller
/// decides whether to fall back to a private default, surface an error
/// or drop the payload.
library;

import '../policies/community_audience.dart';

/// Decode a wire-string into [ProfileVisibility].
///
/// Returns `null` for empty / unknown wire values; it never throws. The
/// caller MUST decide whether a `null` is an error, a fallback (`private`)
/// or a payload-drop, and document that decision in the consuming
/// repository's contract.
ProfileVisibility? profileVisibilityFromWire(String? wire) {
  if (wire == null) return null;
  for (final value in ProfileVisibility.values) {
    if (value.wireValue == wire) return value;
  }
  return null;
}

/// Decode a wire-string into [CommunityAudience].
///
/// Same never-throwing contract as [profileVisibilityFromWire].
CommunityAudience? communityAudienceFromWire(String? wire) {
  if (wire == null) return null;
  for (final value in CommunityAudience.values) {
    if (value.wireValue == wire) return value;
  }
  return null;
}

/// The wire-string for the given [ProfileVisibility].
///
/// Convenience for the Kör 6 JSON layer; the underlying enum is the
/// single source of truth, so re-exporting `wireValue` is the only
/// surface this module adds on the outbound side.
String profileVisibilityToWire(ProfileVisibility value) => value.wireValue;

/// The wire-string for the given [CommunityAudience].
String communityAudienceToWire(CommunityAudience value) => value.wireValue;
