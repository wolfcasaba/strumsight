/// Stable, machine-readable failure codes (SDD Ch2 §7.2).
///
/// A code is part of the app's contract: the UI maps it to a **localised**
/// message, tests assert on it, and later a crash reporter groups by it.
/// Never change an existing string — add a new one instead.
///
/// A failure must NOT carry user-facing English text; the code is the only
/// thing that crosses into the presentation layer.
abstract final class FailureCode {
  // --- network -------------------------------------------------------------
  static const String networkUnavailable = 'network.unavailable';
  static const String networkTimeout = 'network.timeout';
  static const String networkServer = 'network.server';
  static const String networkTls = 'network.tls';
  static const String networkBadResponse = 'network.bad_response';

  // --- authentication ------------------------------------------------------
  static const String authInvalidCredentials = 'auth.invalid_credentials';
  static const String authSessionExpired = 'auth.session_expired';
  static const String authForbidden = 'auth.forbidden';

  // --- validation ----------------------------------------------------------
  static const String validationEmailTaken = 'validation.email_taken';
  static const String validationInvalidInput = 'validation.invalid_input';

  // --- permission ----------------------------------------------------------
  static const String permissionMicrophoneDenied = 'permission.microphone';
  static const String permissionUnavailable = 'permission.unavailable';

  // --- storage -------------------------------------------------------------
  static const String storageRead = 'storage.read';
  static const String storageWrite = 'storage.write';
  static const String storageUnavailable = 'storage.unavailable';

  // --- audio ---------------------------------------------------------------
  static const String audioCaptureFailed = 'audio.capture_failed';
  static const String audioUnavailable = 'audio.unavailable';
  static const String audioSessionBusy = 'audio.session_busy';

  // --- ml ------------------------------------------------------------------
  static const String mlModelLoad = 'ml.model_load';
  static const String mlInference = 'ml.inference';

  // --- configuration / control flow ---------------------------------------
  static const String configurationInvalid = 'configuration.invalid';
  static const String cancelled = 'cancelled';
  static const String unknown = 'unknown';

  // --- practice -----------------------------------------------------------
  static const String practiceContentUnsupported =
      'practice.content_unsupported';
  static const String practiceTargetUncompilable =
      'practice.target_uncompilable';
  static const String practiceInvalidSessionTransition =
      'practice.invalid_session_transition';
}

/// Base type of every expected failure in the app (SDD Ch2 §7.2).
///
/// Expected failures travel as values (see `AppResult`), not as exceptions —
/// so the UI can never be handed a `DioException`, a `PlatformException` or
/// any other transport/plugin type.
sealed class AppFailure {
  const AppFailure({
    required this.code,
    required this.retryable,
    this.cause,
    this.stackTrace,
  });

  /// Stable machine code — see [FailureCode]. The UI localises by this.
  final String code;

  /// Whether repeating the same operation could plausibly succeed.
  final bool retryable;

  /// The originating error, kept for logging only. Never rendered.
  final Object? cause;

  final StackTrace? stackTrace;

  /// Diagnostic only — deliberately excludes [cause], which may contain a URL,
  /// a request body or other sensitive payload. Logging goes through the
  /// redacting logger instead.
  @override
  String toString() => '$runtimeType($code, retryable: $retryable)';
}

/// Transport-level problem: offline, timeout, TLS, 5xx, malformed response.
final class NetworkFailure extends AppFailure {
  const NetworkFailure({
    super.code = FailureCode.networkUnavailable,
    super.retryable = true,
    super.cause,
    super.stackTrace,
  });
}

/// The caller is not (or no longer) authenticated, or the credentials are wrong.
final class AuthenticationFailure extends AppFailure {
  const AuthenticationFailure({
    super.code = FailureCode.authInvalidCredentials,
    super.retryable = false,
    super.cause,
    super.stackTrace,
  });
}

/// A runtime permission (microphone, camera, notifications) was refused or the
/// permission platform channel is unavailable.
final class PermissionFailure extends AppFailure {
  const PermissionFailure({
    super.code = FailureCode.permissionMicrophoneDenied,
    super.retryable = true,
    super.cause,
    super.stackTrace,
  });
}

/// Local persistence (preferences, secure storage, files) failed.
final class StorageFailure extends AppFailure {
  const StorageFailure({
    super.code = FailureCode.storageUnavailable,
    super.retryable = false,
    super.cause,
    super.stackTrace,
  });
}

/// Microphone capture / audio engine problem.
final class AudioFailure extends AppFailure {
  const AudioFailure({
    super.code = FailureCode.audioCaptureFailed,
    super.retryable = true,
    super.cause,
    super.stackTrace,
  });
}

/// On-device model load or inference problem.
final class MlFailure extends AppFailure {
  const MlFailure({
    super.code = FailureCode.mlInference,
    super.retryable = false,
    super.cause,
    super.stackTrace,
  });
}

/// The input was rejected — by a local rule or by the server (e.g. 409).
final class ValidationFailure extends AppFailure {
  const ValidationFailure({
    super.code = FailureCode.validationInvalidInput,
    super.retryable = false,
    super.cause,
    super.stackTrace,
  });
}

/// The build/runtime configuration is invalid (see `AppConfig.resolve`).
final class ConfigurationFailure extends AppFailure {
  const ConfigurationFailure({
    super.code = FailureCode.configurationInvalid,
    super.retryable = false,
    super.cause,
    super.stackTrace,
  });
}

/// The operation was cancelled by the app or the user — not an error to report.
final class CancelledFailure extends AppFailure {
  const CancelledFailure({
    super.code = FailureCode.cancelled,
    super.retryable = true,
    super.cause,
    super.stackTrace,
  });
}

/// Nothing above matched. An unknown error is NEVER treated as success; it is
/// reported (and logged) as this.
final class UnknownFailure extends AppFailure {
  const UnknownFailure({
    super.code = FailureCode.unknown,
    super.retryable = false,
    super.cause,
    super.stackTrace,
  });
}
