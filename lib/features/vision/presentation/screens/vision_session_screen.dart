import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/camera/camera_providers.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/vision_session_controller.dart';
import '../../application/vision_session_state.dart';
import '../overlays/vision_preview_overlay.dart';

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
                  detailedOverlayEnabled: state.detailedOverlayEnabled,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Text(_statusText(l10n, state.status)),
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
