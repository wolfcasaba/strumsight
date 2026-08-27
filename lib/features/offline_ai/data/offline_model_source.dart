import '../../../core/foundation/app_failure.dart';
import '../../../core/foundation/app_result.dart';
import '../model/offline_model.dart';

/// Fetches the candidate bytes + declared checksum for a model — the
/// "download" step (§3 of the round brief). Kept behind an interface so
/// production and tests can supply different sources without touching the
/// verification/activation logic in [offline_model.dart], which never
/// changes regardless of where the bytes came from (A6).
abstract interface class OfflineModelSource {
  Future<AppResult<OfflineModelAsset>> fetchCandidate(String modelId);
}

/// No on-device model distribution backend exists yet for this round
/// (§0.0.B/B1 — the feature tree itself is new). This default is honest
/// about that instead of pretending a download succeeded: the model manager
/// screen surfaces the resulting failure exactly like any other network
/// failure elsewhere in the app, rather than silently no-op'ing.
final class UnavailableOfflineModelSource implements OfflineModelSource {
  const UnavailableOfflineModelSource();

  @override
  Future<AppResult<OfflineModelAsset>> fetchCandidate(String modelId) async =>
      const Failure(NetworkFailure());
}
