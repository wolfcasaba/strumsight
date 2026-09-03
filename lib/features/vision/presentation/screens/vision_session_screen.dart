import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/config/app_config.dart';
import '../../../../core/camera/camera_providers.dart';
import '../../../../core/design_system/public.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../settings/public.dart';
import '../../application/vision_session_controller.dart';
import '../../application/vision_session_state.dart';
import '../overlays/vision_preview_overlay.dart';
import '../providers/vision_thermal_providers.dart';
import 'vision_result_screen.dart';

/// The standalone, optional Vision coaching session surface.
class VisionSessionScreen extends ConsumerWidget {
  const VisionSessionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Mount the existing guard: backgrounding revokes the coordinator lease;
    // the controller's revoke callback completes the session exactly once.
    ref.watch(cameraLifecycleGuardProvider);
    final state = ref.watch(visionSessionControllerProvider);
    final controller = ref.read(visionSessionControllerProvider.notifier);
    final l10n = AppLocalizations.of(context);
    final result = state.result;
    if (state.status == VisionSessionStatus.completed && result != null) {
      // UI-47 Vision Result, composed inline — no route exists for it yet
      // (§0.0/B10). Starting a new corrective practice simply re-enters the
      // existing `begin()` flow.
      return Scaffold(
        appBar: AppBar(title: Text(l10n.visionResultTitle)),
        body: SafeArea(
          child: VisionResultScreen(
            result: result,
            onStartCorrectivePractice: controller.begin,
          ),
        ),
      );
    }

    final thermalState = ref.watch(visionThermalUiStateProvider);
    // A8: the debug skeleton is labor-only. `labModeAvailable` is the
    // build-level gate (off in production, R02 §5.4 mintája); `labModeProvider`
    // is the user's own opt-in. Both are required before the toggle even
    // renders, and the overlay is told `false` regardless of stored state
    // when the build-level gate is off (defence in depth).
    final labAvailable = ref.watch(appConfigProvider).flags.labModeAvailable;
    final labEnabled = labAvailable && ref.watch(labModeProvider);
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    final isAlarmStatus = _isPermissionOrDeviceIssue(state.status);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.visionSessionTitle)),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(color: colors.surfaceSunken),
                child: VisionPreviewOverlay(
                  quality: state.overlayQuality,
                  realtimeCue: state.realtimeCue,
                  detailedOverlayEnabled:
                      labEnabled && state.detailedOverlayEnabled,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(SsSpacing.space4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (thermalState == VisionThermalUiState.throttled)
                    const _ThermalBanner(),
                  Text(
                    _statusText(l10n, state.status),
                    style: typography.bodyLarge.copyWith(
                      color: isAlarmStatus ? colors.danger : colors.textPrimary,
                    ),
                  ),
                  if (labAvailable)
                    SsSwitchRow(
                      key: const Key('vision-detailed-overlay-toggle'),
                      value: state.detailedOverlayEnabled,
                      onChanged: controller.setDetailedOverlayEnabled,
                      label: l10n.visionSessionDetailedOverlay,
                    ),
                  const SizedBox(height: SsSpacing.space2),
                  _SessionActions(controller: controller, state: state),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static bool _isPermissionOrDeviceIssue(VisionSessionStatus status) =>
      switch (status) {
        VisionSessionStatus.permissionDenied ||
        VisionSessionStatus.permissionPermanentlyDenied ||
        VisionSessionStatus.cameraUnavailable ||
        VisionSessionStatus.cameraBusy ||
        VisionSessionStatus.inferenceFailed => true,
        _ => false,
      };

  static String _statusText(
    AppLocalizations l10n,
    VisionSessionStatus status,
  ) => switch (status) {
    VisionSessionStatus.idle ||
    VisionSessionStatus.completed => l10n.visionSessionReady,
    VisionSessionStatus.setup => l10n.visionSessionSetup,
    VisionSessionStatus.calibrating => l10n.visionSessionCalibrating,
    VisionSessionStatus.running => l10n.visionSessionRunning,
    VisionSessionStatus.paused => l10n.visionSessionPaused,
    VisionSessionStatus.finalizing => l10n.visionSessionFinalizing,
    VisionSessionStatus.permissionDenied ||
    VisionSessionStatus.permissionPermanentlyDenied =>
      l10n.visionSessionPermission,
    VisionSessionStatus.cameraUnavailable ||
    VisionSessionStatus.cameraBusy => l10n.visionSessionCameraUnavailable,
    VisionSessionStatus.calibrationLost => l10n.visionSessionCalibrationLost,
    VisionSessionStatus.inferenceFailed => l10n.visionSessionFailed,
    VisionSessionStatus.cancelled ||
    VisionSessionStatus.disposed => l10n.visionSessionCancelled,
  };
}

class _SessionActions extends StatelessWidget {
  const _SessionActions({required this.controller, required this.state});

  final VisionSessionController controller;
  final VisionSessionState state;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final status = state.status;
    final actions = switch (status) {
      VisionSessionStatus.idle ||
      VisionSessionStatus.completed ||
      VisionSessionStatus.cancelled ||
      VisionSessionStatus.inferenceFailed => <Widget>[
        SsButton(
          key: const Key('vision-session-begin'),
          label: l10n.visionSessionStart,
          onPressed: controller.begin,
        ),
      ],
      VisionSessionStatus.permissionDenied ||
      VisionSessionStatus.permissionPermanentlyDenied ||
      VisionSessionStatus.cameraUnavailable => <Widget>[
        SsButton(
          key: const Key('vision-session-request-permission'),
          label: l10n.visionSetupRequestPermission,
          onPressed: controller.requestPermission,
        ),
      ],
      VisionSessionStatus.setup => <Widget>[
        SsButton(
          key: const Key('vision-session-calibrate'),
          label: l10n.visionSessionCalibrate,
          onPressed: controller.beginCalibration,
        ),
      ],
      VisionSessionStatus.calibrating => <Widget>[
        SsButton(
          key: const Key('vision-session-start'),
          label: l10n.visionSessionStart,
          onPressed: controller.start,
        ),
      ],
      VisionSessionStatus.running => <Widget>[
        SsButton(
          key: const Key('vision-session-pause'),
          variant: SsButtonVariant.secondary,
          label: l10n.livePause,
          onPressed: controller.pause,
        ),
        SsButton(
          key: const Key('vision-session-recalibrate'),
          variant: SsButtonVariant.secondary,
          label: l10n.visionSessionRecalibrate,
          onPressed: controller.recalibrate,
        ),
        SsButton(
          key: const Key('vision-session-stop'),
          label: l10n.analyzeStop,
          onPressed: controller.stop,
        ),
      ],
      VisionSessionStatus.paused => <Widget>[
        SsButton(
          key: const Key('vision-session-resume'),
          variant: SsButtonVariant.secondary,
          label: l10n.liveResume,
          onPressed: controller.resume,
        ),
        SsButton(
          key: const Key('vision-session-recalibrate'),
          variant: SsButtonVariant.secondary,
          label: l10n.visionSessionRecalibrate,
          onPressed: controller.recalibrate,
        ),
        SsButton(
          key: const Key('vision-session-stop'),
          label: l10n.analyzeStop,
          onPressed: controller.stop,
        ),
      ],
      VisionSessionStatus.calibrationLost => <Widget>[
        SsButton(
          key: const Key('vision-session-recalibrate'),
          label: l10n.visionSessionRecalibrate,
          onPressed: controller.recalibrate,
        ),
        SsButton(
          key: const Key('vision-session-stop'),
          label: l10n.analyzeStop,
          onPressed: controller.stop,
        ),
      ],
      VisionSessionStatus.cameraBusy ||
      VisionSessionStatus.finalizing ||
      VisionSessionStatus.disposed => const <Widget>[],
    };
    return Wrap(
      spacing: SsSpacing.space2,
      runSpacing: SsSpacing.space2,
      children: actions,
    );
  }
}

/// A5 — thermal pressure is a distinct, named state from tracking loss
/// (`VisionSessionStatus.calibrationLost`, §0.0/B3): different cause,
/// different key, different text, so neither can be mistaken for the other.
class _ThermalBanner extends StatelessWidget {
  const _ThermalBanner();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    return Container(
      key: const Key('vision-thermal-throttled'),
      margin: const EdgeInsets.only(bottom: SsSpacing.space2),
      padding: const EdgeInsets.all(SsSpacing.space3),
      decoration: BoxDecoration(
        color: colors.warning.withValues(alpha: 0.15),
        border: Border.all(color: colors.warning),
        borderRadius: BorderRadius.circular(SsRadius.sm),
      ),
      child: Row(
        children: [
          Icon(Icons.thermostat, color: colors.warning),
          const SizedBox(width: SsSpacing.space2),
          Expanded(
            child: Text(
              l10n.visionSessionThermalThrottled,
              style: typography.bodyMedium.copyWith(color: colors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
