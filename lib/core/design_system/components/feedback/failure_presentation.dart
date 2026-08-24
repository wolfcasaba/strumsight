import '../../../foundation/app_failure.dart';
import '../../../../l10n/app_localizations.dart';

/// The concrete next step a failure presentation offers the user.
enum SsFailureActionKind {
  retry,
  openSettings,
  continueOffline,
  contactSupport,
}

/// One caller-actionable button: a stable [kind] plus its localised [label].
final class SsFailureAction {
  const SsFailureAction({required this.kind, required this.label});

  final SsFailureActionKind kind;
  final String label;
}

/// A localised, presentation-safe view of an [AppFailure] (ADR 0277).
///
/// Never carries [AppFailure.cause] or [AppFailure.stackTrace] — those never
/// cross into the UI (D2). [actions] is never empty: every failure resolves
/// to at least one next step.
final class SsFailurePresentation {
  const SsFailurePresentation._({
    required this.title,
    required this.message,
    required this.retryable,
    required this.actions,
  });

  /// Maps [failure] to a localised presentation model, reading ONLY
  /// [AppFailure.code] and [AppFailure.retryable] (D2) — the `code` alone is
  /// not enough to decide the action: the microphone-permission code is
  /// identical for a plain denial and a permanent one, and only `retryable`
  /// tells them apart (§5.1).
  factory SsFailurePresentation.from(
    AppLocalizations l10n,
    AppFailure failure,
  ) {
    return SsFailurePresentation._(
      title: _title(l10n, failure.code),
      message: _message(l10n, failure.code),
      retryable: failure.retryable,
      actions: _actions(l10n, failure),
    );
  }

  final String title;
  final String message;
  final bool retryable;
  final List<SsFailureAction> actions;

  bool hasAction(SsFailureActionKind kind) =>
      actions.any((action) => action.kind == kind);
}

String _title(AppLocalizations l10n, String code) => switch (code) {
  FailureCode.permissionMicrophoneDenied =>
    l10n.dsFailurePermissionMicrophoneTitle,
  FailureCode.permissionCameraDenied => l10n.dsFailurePermissionCameraTitle,
  FailureCode.permissionUnavailable => l10n.dsFailurePermissionUnavailableTitle,
  FailureCode.networkUnavailable => l10n.dsFailureNetworkUnavailableTitle,
  FailureCode.networkTimeout ||
  FailureCode.networkServer ||
  FailureCode.networkTls ||
  FailureCode.networkBadResponse => l10n.dsFailureNetworkGenericTitle,
  FailureCode.authInvalidCredentials ||
  FailureCode.authSessionExpired ||
  FailureCode.authForbidden => l10n.dsFailureAuthTitle,
  FailureCode.storageUnavailable ||
  FailureCode.storageRead ||
  FailureCode.storageWrite => l10n.dsFailureStorageTitle,
  _ => l10n.dsFailureUnknownTitle,
};

String _message(AppLocalizations l10n, String code) => switch (code) {
  FailureCode.permissionMicrophoneDenied =>
    l10n.dsFailurePermissionMicrophoneMessage,
  FailureCode.permissionCameraDenied => l10n.dsFailurePermissionCameraMessage,
  FailureCode.permissionUnavailable =>
    l10n.dsFailurePermissionUnavailableMessage,
  FailureCode.networkUnavailable => l10n.dsFailureNetworkUnavailableMessage,
  FailureCode.networkTimeout ||
  FailureCode.networkServer ||
  FailureCode.networkTls ||
  FailureCode.networkBadResponse => l10n.dsFailureNetworkGenericMessage,
  FailureCode.authInvalidCredentials ||
  FailureCode.authSessionExpired ||
  FailureCode.authForbidden => l10n.dsFailureAuthMessage,
  FailureCode.storageUnavailable ||
  FailureCode.storageRead ||
  FailureCode.storageWrite => l10n.dsFailureStorageMessage,
  _ => l10n.dsFailureUnknownMessage,
};

/// The retry-visibility decision (§5.3, §6.1): keyed on [AppFailure.retryable]
/// — never on the code alone — plus two additive special cases: a permanently
/// denied permission trades retry for "open settings", and the specific
/// offline code adds a "continue offline" option alongside retry.
List<SsFailureAction> _actions(AppLocalizations l10n, AppFailure failure) {
  final isPermissionDenial =
      failure.code == FailureCode.permissionMicrophoneDenied ||
      failure.code == FailureCode.permissionCameraDenied;

  if (!failure.retryable && isPermissionDenial) {
    return [
      SsFailureAction(
        kind: SsFailureActionKind.openSettings,
        label: l10n.dsFailureOpenSettingsAction,
      ),
    ];
  }

  if (failure.retryable) {
    return [
      SsFailureAction(
        kind: SsFailureActionKind.retry,
        label: l10n.dsFailureRetryAction,
      ),
      if (failure.code == FailureCode.networkUnavailable)
        SsFailureAction(
          kind: SsFailureActionKind.continueOffline,
          label: l10n.dsFailureContinueOfflineAction,
        ),
    ];
  }

  return [
    SsFailureAction(
      kind: SsFailureActionKind.contactSupport,
      label: l10n.dsFailureContactSupportAction,
    ),
  ];
}
