import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/config/app_config.dart';
import '../../../../core/camera/camera_providers.dart';
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
    return Scaffold(
      appBar: AppBar(title: Text(l10n.visionSessionTitle)),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                ),
                child: VisionPreviewOverlay(
                  quality: state.overlayQuality,
                  realtimeCue: state.realtimeCue,
                  detailedOverlayEnabled:
                      labEnabled && state.detailedOverlayEnabled,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (thermalState == VisionThermalUiState.throttled)
                    const _ThermalBanner(),
                  Text(_statusText(l10n, state.status)),
                  if (labAvailable)
                    SwitchListTile(
                      key: const Key('vision-detailed-overlay-toggle'),
                      value: state.detailedOverlayEnabled,
                      onChanged: controller.setDetailedOverlayEnabled,
                      title: Text(l10n.visionSessionDetailedOverlay),
                    ),
                  const SizedBox(height: 8),
                  _SessionActions(controller: controller, state: state),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

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
        FilledButton(
          key: const Key('vision-session-begin'),
          onPressed: controller.begin,
          child: Text(l10n.visionSessionStart),
        ),
      ],
      VisionSessionStatus.permissionDenied ||
      VisionSessionStatus.permissionPermanentlyDenied ||
      VisionSessionStatus.cameraUnavailable => <Widget>[
        FilledButton(
          key: const Key('vision-session-request-permission'),
          onPressed: controller.requestPermission,
          child: Text(l10n.visionSetupRequestPermission),
        ),
      ],
      VisionSessionStatus.setup => <Widget>[
        FilledButton(
          key: const Key('vision-session-calibrate'),
          onPressed: controller.beginCalibration,
          child: Text(l10n.visionSessionCalibrate),
        ),
      ],
      VisionSessionStatus.calibrating => <Widget>[
        FilledButton(
          key: const Key('vision-session-start'),
          onPressed: controller.start,
          child: Text(l10n.visionSessionStart),
        ),
      ],
      VisionSessionStatus.running => <Widget>[
        OutlinedButton(
          key: const Key('vision-session-pause'),
          onPressed: controller.pause,
          child: Text(l10n.livePause),
        ),
        OutlinedButton(
          key: const Key('vision-session-recalibrate'),
          onPressed: controller.recalibrate,
          child: Text(l10n.visionSessionRecalibrate),
        ),
        FilledButton(
          key: const Key('vision-session-stop'),
          onPressed: controller.stop,
          child: Text(l10n.analyzeStop),
        ),
      ],
      VisionSessionStatus.paused => <Widget>[
        OutlinedButton(
          key: const Key('vision-session-resume'),
          onPressed: controller.resume,
          child: Text(l10n.liveResume),
        ),
        OutlinedButton(
          key: const Key('vision-session-recalibrate'),
          onPressed: controller.recalibrate,
          child: Text(l10n.visionSessionRecalibrate),
        ),
        FilledButton(
          key: const Key('vision-session-stop'),
          onPressed: controller.stop,
          child: Text(l10n.analyzeStop),
        ),
      ],
      VisionSessionStatus.calibrationLost => <Widget>[
        FilledButton(
          key: const Key('vision-session-recalibrate'),
          onPressed: controller.recalibrate,
          child: Text(l10n.visionSessionRecalibrate),
        ),
        FilledButton(
          key: const Key('vision-session-stop'),
          onPressed: controller.stop,
          child: Text(l10n.analyzeStop),
        ),
      ],
      VisionSessionStatus.cameraBusy ||
      VisionSessionStatus.finalizing ||
      VisionSessionStatus.disposed => const <Widget>[],
    };
    return Wrap(spacing: 8, runSpacing: 8, children: actions);
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
    return Container(
      key: const Key('vision-thermal-throttled'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.thermostat),
          const SizedBox(width: 8),
          Expanded(child: Text(l10n.visionSessionThermalThrottled)),
        ],
      ),
    );
  }
}
