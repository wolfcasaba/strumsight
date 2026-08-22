/// Repository contract for Community profiles (E09-R05, ADR 0399 §1,
/// SDD §21.2).
///
/// Only the abstract surface lives here — the Kör 6 Dio implementation
/// imports this interface, the Kör 5 test double implements it. No
/// JSON / DTO mapping, no Dio, no SharedPreferences.
library;

import '../entities/community_profile.dart';
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
}
