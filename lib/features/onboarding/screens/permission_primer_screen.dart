import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart'
    show openAppSettings;

import '../../../core/audio/audio_providers.dart';
import '../../../core/design_system/components/feedback/failure_presentation.dart';
import '../../../core/design_system/components/feedback/ss_permission_state.dart';
import '../../../core/design_system/foundations/ss_colors.dart';
import '../../../core/design_system/foundations/ss_spacing.dart';
import '../../../core/design_system/foundations/ss_typography.dart';
import '../../../core/platform/microphone_permission.dart';
import '../../../l10n/app_localizations.dart';

/// The mic-permission primer (ADR 0281 §1/§5.1). Shown BEFORE any system
/// permission dialog — it states why the mic is needed and what happens if
/// it stays denied (A1) — and again, showing the settings path instead of a
/// dead re-request, whenever the permission is already permanently denied
/// (A2). Never touches the platform channel itself: every read/request goes
/// through [microphonePermissionGatewayProvider] (§9.1), fake-overridable in
/// tests.
class PermissionPrimerScreen extends ConsumerStatefulWidget {
  const PermissionPrimerScreen({
    super.key,
    this.onGranted,
    this.onSkipped,
    this.openSettings,
  });

  /// Fires once the gateway confirms the microphone is usable — whether
  /// that took a fresh system dialog or the permission was already granted.
  final VoidCallback? onGranted;

  /// "Not now" — the flow continues WITHOUT ever showing the system dialog.
  final VoidCallback? onSkipped;

  /// Injectable for tests; defaults to `permission_handler`'s
  /// `openAppSettings`.
  final Future<bool> Function()? openSettings;

  @override
  ConsumerState<PermissionPrimerScreen> createState() =>
      _PermissionPrimerScreenState();
}

class _PermissionPrimerScreenState
    extends ConsumerState<PermissionPrimerScreen> {
  MicrophonePermissionState? _state;
  bool _requesting = false;

  @override
  void initState() {
    super.initState();
    _loadCurrentState();
  }

  Future<void> _loadCurrentState() async {
    final gateway = ref.read(microphonePermissionGatewayProvider);
    final current = await gateway.currentState();
    if (!mounted) return;
    if (current.isGranted) {
      // Already granted (e.g. a returning user) — there is nothing left to
      // prime, and showing the ask-UI anyway would be a pointless extra
      // screen, not a safeguard.
      widget.onGranted?.call();
      return;
    }
    setState(() => _state = current);
  }

  Future<void> _allow() async {
    if (_requesting) return;
    setState(() => _requesting = true);
    final gateway = ref.read(microphonePermissionGatewayProvider);
    final result = await gateway.request();
    if (!mounted) return;
    setState(() {
      _requesting = false;
      _state = result;
    });
    if (result.isGranted) {
      widget.onGranted?.call();
    }
  }

  Future<void> _openSettings() => (widget.openSettings ?? openAppSettings)();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final state = _state;
    if (state == null) {
      // The one async read of the CURRENT state (never a system dialog) is
      // in flight — nothing to decide yet.
      return const Scaffold(body: SizedBox.shrink());
    }

    final deniedFailure = state.failure;
    if (deniedFailure != null && !deniedFailure.retryable) {
      // A final denial: the action is opening settings, never a re-request
      // (ADR 0281 §1/§5.1, A2).
      return Scaffold(
        body: SsPermissionState(
          kind: SsPermissionKind.microphone,
          rationale: l10n.onboardPrimerRationale,
          consequence: l10n.onboardPrimerConsequence,
          presentation: SsFailurePresentation.from(l10n, deniedFailure),
          onOpenSettings: _openSettings,
        ),
      );
    }

    final colors = Theme.of(context).extension<SsColorScheme>();
    final typography = Theme.of(context).extension<SsTypography>();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(SsSpacing.space6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.mic_none_outlined,
                  size: 48,
                  color: colors?.textSecondary,
                ),
                const SizedBox(height: SsSpacing.space4),
                Text(
                  l10n.onboardPrimerTitle,
                  style: typography?.titleLarge.copyWith(
                    color: colors?.textPrimary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: SsSpacing.space2),
                Text(
                  l10n.onboardPrimerRationale,
                  style: typography?.bodyMedium.copyWith(
                    color: colors?.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: SsSpacing.space1),
                Text(
                  l10n.onboardPrimerConsequence,
                  style: typography?.bodyMedium.copyWith(
                    color: colors?.textSecondary,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: SsSpacing.space6),
                FilledButton(
                  key: const ValueKey('onboard-primer-allow'),
                  onPressed: _requesting ? null : _allow,
                  child: Text(l10n.onboardPrimerAllowAction),
                ),
                TextButton(
                  key: const ValueKey('onboard-primer-not-now'),
                  onPressed: widget.onSkipped,
                  child: Text(l10n.onboardPrimerNotNowAction),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
