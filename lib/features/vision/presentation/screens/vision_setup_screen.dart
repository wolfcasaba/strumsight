import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart'
    show openAppSettings;

import '../../../../core/camera/camera_providers.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/vision_setup_controller.dart';
import '../../domain/vision_setup_profile.dart';
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
    final state = ref.watch(visionSetupControllerProvider);
    final controller = ref.read(visionSetupControllerProvider.notifier);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.visionSetupTitle),
        actions: [
          if (state.step != VisionSetupStep.audioOnly)
            TextButton(
              key: const Key('vision-setup-skip'),
              onPressed: () => unawaited(controller.skip()),
              child: Text(l10n.visionSetupSkipAction),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _PrivacyNotice(),
            const SizedBox(height: 24),
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
              VisionSetupStep.audioOnly => _AudioOnlyStep(),
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
    return Semantics(
      container: true,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.visionSetupPrivacyTitle,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(l10n.visionSetupPrivacyBody),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.visionSetupProfileTitle,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(l10n.visionSetupProfileBody),
        const SizedBox(height: 16),
        VisionSetupFrameGuide(profile: state.selectedProfile),
        const SizedBox(height: 16),
        Text(
          l10n.visionSetupProfileRecommended(
            _profileLabel(l10n, state.recommendedProfile),
          ),
        ),
        const SizedBox(height: 8),
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
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('vision-setup-profile-continue'),
          onPressed: onContinue,
          child: Text(l10n.visionSetupContinue),
        ),
      ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.visionSetupCameraTitle,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(l10n.visionSetupCameraBody),
        const SizedBox(height: 12),
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
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('vision-setup-camera-continue'),
          onPressed: onContinue,
          child: Text(l10n.visionSetupContinue),
        ),
      ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.visionSetupPermissionTitle,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 16),
        CameraPermissionPanel(
          state: state.permissionState,
          onRequest: onRequest,
          onOpenSettings: openAppSettings,
        ),
      ],
    );
  }
}

class _ReadyStep extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.visionSetupReadyTitle,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(l10n.visionSetupReadyBody),
      ],
    );
  }
}

class _AudioOnlyStep extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.visionSetupAudioOnlyTitle,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(l10n.visionSetupAudioOnlyBody),
        const SizedBox(height: 16),
        FilledButton(
          key: const Key('vision-audio-only-continue'),
          onPressed: () {},
          child: Text(l10n.visionSetupAudioOnlyContinue),
        ),
      ],
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
