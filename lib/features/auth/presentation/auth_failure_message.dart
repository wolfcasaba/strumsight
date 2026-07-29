import '../../../core/foundation/app_failure.dart';
import '../../../l10n/app_localizations.dart';

/// Turns an auth [AppFailure] into a localised message (E01-R04 §4.4).
///
/// The mapping keys on the **stable code**, never on the failure's Dart type or
/// on any English text the failure might carry — it carries none by design.
/// Anything unrecognised (including a non-[AppFailure] error that slipped
/// through) falls back to the generic message rather than showing internals.
String authFailureMessage(AppLocalizations l10n, Object? error) {
  final code = error is AppFailure ? error.code : FailureCode.unknown;
  return switch (code) {
    FailureCode.authInvalidCredentials ||
    FailureCode.authSessionExpired ||
    FailureCode.authForbidden => l10n.authErrorInvalidCredentials,
    FailureCode.validationEmailTaken => l10n.authErrorEmailTaken,
    FailureCode.networkUnavailable ||
    FailureCode.networkTimeout ||
    FailureCode.networkServer ||
    FailureCode.networkTls => l10n.authErrorNetwork,
    _ => l10n.authErrorUnknown,
  };
}
