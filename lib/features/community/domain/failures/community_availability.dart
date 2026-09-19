/// Community availability — the module-level "this server does not host
/// Community" classification (R12, audit §5.2).
///
/// MEASURED: the live deploy runs with `STRUMSIGHT_COMMUNITY_ENABLED=false`,
/// and `backend/app/main.py` only mounts the community router when that
/// setting is on. FastAPI therefore never registers a single
/// `/community/**` path, and every call gets the framework's bare 404 —
/// which `mapNetworkFailure` classifies as
/// `NetworkFailure(FailureCode.networkBadResponse)`, the same code a
/// malformed body earns. `GET /health/ready` does NOT report the module
/// either (measured: it answers `{"status": "ready"}` whether Community is
/// on or off), so there is no readiness surface to ask — the 404 IS the
/// signal, and the data layer is where it gets a name.
///
/// The distinction lives inside the feature rather than in the core
/// taxonomy: "the operator turned this module off" is a Community fact,
/// while `FailureCode` is a whole-app contract. `AppFailure` is `sealed`, so
/// this is a code + a builder + a predicate over the existing
/// [NetworkFailure], never a new subtype.
library;

import '../../../../core/foundation/app_failure.dart';

/// Community-local failure codes. Same contract as `FailureCode`: a code is
/// machine-readable, the UI localises by it, and an existing string is never
/// changed — only added to.
abstract final class CommunityFailureCode {
  /// The server answered, but it does not host the Community module at all.
  static const String unavailable = 'community.unavailable';
}

/// The failure the Community data layer raises when an endpoint 404s because
/// the router is not mounted on this server.
///
/// Retryable on purpose: the remedy is an operator flipping a server switch,
/// after which the very next call succeeds — so the gate keeps offering
/// Retry instead of presenting a dead end.
NetworkFailure communityUnavailableFailure(Object cause) =>
    NetworkFailure(code: CommunityFailureCode.unavailable, cause: cause);

/// Whether [failure] is the "Community is not enabled on this server"
/// verdict. Callers branch on this, never on the HTTP status.
bool isCommunityUnavailable(AppFailure failure) =>
    failure.code == CommunityFailureCode.unavailable;
