/// Repository contract for Community profiles (E09-R05, ADR 0399 §1,
/// SDD §21.2; E09-R06, ADR 0400 §5).
///
/// Only the abstract surface lives here — the Kör 6 Dio implementation
/// imports this interface, the Kör 5 test double implements it. No
/// JSON / DTO mapping, no Dio, no SharedPreferences.
///
/// E09-R06 extends the surface with the two **write** operations
/// (``createProfile`` / ``updateProfile``) and the two **domain
/// exceptions** that the data layer translates the HTTP 409 detail
/// codes into. The exceptions are interface-level — the controller
/// uses them to branch on ``handle_taken`` vs ``profile_exists``
/// without having to know about HTTP or Dio.
library;

import '../../../core/foundation/app_failure.dart';
import '../../../core/foundation/app_result.dart';
import '../entities/community_profile.dart';
import '../policies/community_audience.dart';
import '../value_objects/community_handle.dart';
import '../value_objects/public_user_id.dart';
import 'community_page.dart';

abstract interface class CommunityProfileRepository {
  /// Fetch the viewer's own profile (Kör 6).
  ///
  /// Returns `null` when no profile has been created yet — the
  /// Community gate UI uses that signal to redirect to onboarding.
  Future<CommunityProfile?> fetchMyProfile();

  /// Fetch a profile by its public user id. The repository applies
  /// the backend access-policy and populates placeholder fields per
  /// ADR 0398 §4 SUMMARY.
  Future<CommunityProfile> fetchById(PublicUserId userId);

  /// Fetch a profile by its handle. The backend enforces uniqueness
  /// on the normalized handle; the lookup is case-insensitive after
  /// the [CommunityHandle.normalized] form is computed here.
  Future<CommunityProfile?> fetchByHandle(CommunityHandle handle);

  /// Paged profile search by handle / interest prefix
  /// (SDD §21.2, Kör 9).
  ///
  /// The minimum query length and the rate-limit are server-enforced;
  /// the repository MUST NOT add a client-side filter on top of that.
  Future<CommunityPage<CommunityProfile>> searchProfiles({
    required String query,
    required Object cursor,
  });

  /// Create a profile for the signed-in user (E09-R06, ADR 0400 §5).
  ///
  /// The repository resolves the caller identity from the auth-ladder
  /// (``CurrentUser`` equivalent on the Dio side); the payload has
  /// no user-id field. The implementation translates HTTP 409
  /// ``profile_exists`` / ``handle_taken`` into the matching
  /// [ProfileAlreadyExistsException] / [HandleTakenException] so the
  /// controller can branch on them without parsing HTTP.
  ///
  /// ``handle`` is the raw user input; the data layer passes the
  /// value through ``CommunityHandle.normalizeForBackend`` so the
  /// server's NFKC + casefold + strip pipeline receives the same
  /// canonical form the on-device pre-validation built.
  ///
  /// Returns a fully-populated [CommunityProfile] (server-authoritative
  /// — the controller MUST NOT splice in any local-only state). All
  /// non-409 transport errors (offline, timeout, 5xx) are surfaced as
  /// [AppFailure] via the [AppResult] return value, not as
  /// exceptions — the UI localises by [FailureCode].
  Future<AppResult<CommunityProfile>> createProfile({
    required CommunityHandle handle,
    required String displayName,
    required ProfileVisibility visibility,
    required CommunityAudience audienceDefault,
  });

  /// Update the signed-in user's profile — display name only
  /// (E09-R06, ADR 0400 §3 / §5).
  ///
  /// Privacy changes are a separate endpoint (the Kör 4 ``privacy.py``
  /// router, not wired into the module in this round), and the
  /// edit-mode UI therefore does not offer a privacy re-selection.
  /// The repository surfaces this scope limit in the parameter list
  /// — no [ProfileVisibility] / [CommunityAudience] argument.
  Future<AppResult<CommunityProfile>> updateProfile({
    required String displayName,
  });
}

/// Domain exception raised when the server already has a profile for
/// the caller (HTTP 409 ``profile_exists``).
///
/// The controller translates this into an inline message on the
/// onboarding flow — it is NOT a hard error. Per ADR 0400 §5.2 the
/// "create a second profile" scenario means the user landed on
/// onboarding WHILE already owning a profile; the correct UX is to
/// redirect to the read-only view, not to crash.
///
/// The exception is the FUTURE-PROOF signal the brief asks for: the
/// data layer currently translates HTTP 409 ``profile_exists`` to a
/// [AppFailure] with [FailureCode.communityProfileExists], and the
/// controller branches on the code. The exception exists as part of
/// the interface so a future caller (e.g. a CLI that does not have
/// the Failure taxonomy) can catch the typed signal directly.
class ProfileAlreadyExistsException implements Exception {
  const ProfileAlreadyExistsException();
  @override
  String toString() => 'ProfileAlreadyExistsException';
}

/// Domain exception raised when the requested handle is already taken
/// (HTTP 409 ``handle_taken``).
///
/// The controller surfaces this as an inline field-level error on the
/// handle input — a fresh ``createProfile`` with a different handle
/// will succeed without leaving the screen. The exception is
/// domain-shaped (no HTTP, no Dio) so widget tests can throw it
/// without a network.
///
/// Like [ProfileAlreadyExistsException], the current data layer uses
/// [FailureCode.communityHandleTaken] for the same signal; the
/// exception is the typed fallback for callers that do not parse
/// [AppFailure.code].
class HandleTakenException implements Exception {
  const HandleTakenException();
  @override
  String toString() => 'HandleTakenException';
}

