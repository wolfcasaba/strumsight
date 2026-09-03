import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart'
    show openAppSettings;

import '../../../../core/camera/camera_providers.dart';
import '../../../../core/design_system/public.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/vision_setup_controller.dart';
import '../../domain/vision_setup_profile.dart';
import '../providers/vision_capability_providers.dart';
import '../providers/vision_setup_providers.dart';
import '../widgets/camera_permission_panel.dart';
import '../widgets/vision_setup_frame_guide.dart';

/// A guided, optional and privacy-aware camera setup route.
class VisionSetupScreen extends ConsumerStatefulWidget {
  const VisionSetupScreen({super.key});

  @override
  ConsumerState<VisionSetupScreen> createState() => _VisionSetupScreenState();
}

class _VisionSetupScreenState extends ConsumerState<VisionSetupScreen> {
  @override
  void initState() {
    super.initState();
    Future<void>.microtask(
      () => ref
          .read(visionSetupControllerProvider.notifier)
          .refreshPermissionState(),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(cameraLifecycleGuardProvider);
    final l10n = AppLocalizations.of(context);
    final capability = ref.watch(visionDeviceCapabilityProvider);
    if (capability == VisionDeviceCapability.unsupported) {
      // A6 — an unsupported device gets the audio-only alternative directly,
      // without waiting for the user to find the manual skip action
      // (§0.0/B4: `application/` has no capability signal of its own yet).
      return Scaffold(
        appBar: AppBar(title: Text(l10n.visionSetupTitle)),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _PrivacyNotice(),
              const SizedBox(height: SsSpacing.space6),
              const _AudioOnlyStep(unsupportedDevice: true),
            ],
          ),
        ),
      );
    }
    final state = ref.watch(visionSetupControllerProvider);
    final controller = ref.read(visionSetupControllerProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.visionSetupTitle, overflow: TextOverflow.ellipsis),
        actions: [
          if (state.step != VisionSetupStep.audioOnly)
            ConstrainedBox(
              // A9 — at a large text scale, an unconstrained action label
              // pushes the whole toolbar past the viewport width instead of
              // wrapping; the bound plus ellipsis below keeps this action
              // legible instead of overflowing.
              constraints: const BoxConstraints(maxWidth: 120),
              child: TextButton(
                key: const Key('vision-setup-skip'),
                onPressed: () => unawaited(controller.skip()),
                child: Text(
                  l10n.visionSetupSkipAction,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _PrivacyNotice(),
            const SizedBox(height: SsSpacing.space6),
            switch (state.step) {
              VisionSetupStep.profile => _ProfileStep(
                state: state,
                onSelected: controller.selectProfile,
                onContinue: controller.continueToCamera,
              ),
              VisionSetupStep.camera => _CameraStep(
                state: state,
                onSelected: (camera) =>
                    unawaited(controller.selectCamera(camera)),
                onContinue: () => unawaited(controller.continueToPermission()),
              ),
              VisionSetupStep.permission => _PermissionStep(
                state: state,
                onRequest: () =>
                    unawaited(controller.requestCameraPermission()),
              ),
              VisionSetupStep.ready => _ReadyStep(),
              VisionSetupStep.audioOnly => const _AudioOnlyStep(),
            },
          ],
        ),
      ),
    );
  }
}

class _PrivacyNotice extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    return Semantics(
      container: true,
      child: SsCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.visionSetupPrivacyTitle,
              style: typography.titleMedium.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: SsSpacing.space1),
            Text(
              l10n.visionSetupPrivacyBody,
              style: typography.bodyMedium.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileStep extends StatelessWidget {
  const _ProfileStep({
    required this.state,
    required this.onSelected,
    required this.onContinue,
  });

  final VisionSetupState state;
  final ValueChanged<VisionSetupProfile> onSelected;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SsSection(
      title: l10n.visionSetupProfileTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.visionSetupProfileBody),
          const SizedBox(height: SsSpacing.space4),
          VisionSetupFrameGuide(profile: state.selectedProfile),
          const SizedBox(height: SsSpacing.space4),
          Text(
            l10n.visionSetupProfileRecommended(
              _profileLabel(l10n, state.recommendedProfile),
            ),
          ),
          const SizedBox(height: SsSpacing.space2),
          RadioGroup<VisionSetupProfile>(
            groupValue: state.selectedProfile,
            onChanged: (value) {
              if (value != null) onSelected(value);
            },
            child: Column(
              children: [
                for (final profile in VisionSetupProfile.values)
                  RadioListTile<VisionSetupProfile>(
                    value: profile,
                    title: Text(_profileLabel(l10n, profile)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: SsSpacing.space4),
          SsButton(
            key: const Key('vision-setup-profile-continue'),
            label: l10n.visionSetupContinue,
            onPressed: onContinue,
          ),
        ],
      ),
    );
  }
}

class _CameraStep extends StatelessWidget {
  const _CameraStep({
    required this.state,
    required this.onSelected,
    required this.onContinue,
  });

  final VisionSetupState state;
  final ValueChanged<VisionCameraPreference> onSelected;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SsSection(
      title: l10n.visionSetupCameraTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.visionSetupCameraBody),
          const SizedBox(height: SsSpacing.space3),
          RadioGroup<VisionCameraPreference>(
            groupValue: state.selectedCamera,
            onChanged: (value) {
              if (value != null) onSelected(value);
            },
            child: Column(
              children: [
                RadioListTile<VisionCameraPreference>(
                  value: VisionCameraPreference.back,
                  title: Text(l10n.visionSetupCameraBack),
                ),
                RadioListTile<VisionCameraPreference>(
                  value: VisionCameraPreference.front,
                  title: Text(l10n.visionSetupCameraFront),
                ),
              ],
            ),
          ),
          const SizedBox(height: SsSpacing.space4),
          SsButton(
            key: const Key('vision-setup-camera-continue'),
            label: l10n.visionSetupContinue,
            onPressed: onContinue,
          ),
        ],
      ),
    );
  }
}

class _PermissionStep extends StatelessWidget {
  const _PermissionStep({required this.state, required this.onRequest});

  final VisionSetupState state;
  final VoidCallback onRequest;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SsSection(
      title: l10n.visionSetupPermissionTitle,
      child: CameraPermissionPanel(
        state: state.permissionState,
        onRequest: onRequest,
        onOpenSettings: openAppSettings,
      ),
    );
  }
}

class _ReadyStep extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SsSection(
      title: l10n.visionSetupReadyTitle,
      child: Text(l10n.visionSetupReadyBody),
    );
  }
}

class _AudioOnlyStep extends StatelessWidget {
  const _AudioOnlyStep({this.unsupportedDevice = false});

  final bool unsupportedDevice;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SsSection(
      title: l10n.visionSetupAudioOnlyTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.visionSetupAudioOnlyBody),
          if (unsupportedDevice) ...[
            const SizedBox(height: SsSpacing.space2),
            Text(
              l10n.visionSetupUnsupportedDeviceNotice,
              key: const Key('vision-setup-unsupported-notice'),
            ),
          ],
          const SizedBox(height: SsSpacing.space4),
          SsButton(
            key: const Key('vision-audio-only-continue'),
            label: l10n.visionSetupAudioOnlyContinue,
            onPressed: () {},
          ),
        ],
      ),
    );
  }
}

String _profileLabel(AppLocalizations l10n, VisionSetupProfile profile) =>
    switch (profile) {
      VisionSetupProfile.leftHandFocus => l10n.visionSetupProfileLeftHandFocus,
      VisionSetupProfile.rightHandFocus =>
        l10n.visionSetupProfileRightHandFocus,
      VisionSetupProfile.fullUpperBody => l10n.visionSetupProfileFullUpperBody,
      VisionSetupProfile.practiceBalanced =>
        l10n.visionSetupProfilePracticeBalanced,
    };
