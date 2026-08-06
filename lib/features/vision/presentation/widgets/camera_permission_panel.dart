import 'package:flutter/material.dart';

import '../../../../core/camera/camera_permission.dart';
import '../../../../l10n/app_localizations.dart';

/// Capability-aware permission copy and actions for the Vision setup.
///
/// The panel never requests permission by itself. Its caller supplies the two
/// explicit actions so the route owns both the user gesture and navigation.
class CameraPermissionPanel extends StatelessWidget {
  const CameraPermissionPanel({
    super.key,
    required this.state,
    required this.onRequest,
    required this.onOpenSettings,
  });

  final CameraPermissionState state;
  final VoidCallback onRequest;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return switch (state) {
      CameraPermissionState.granted => _PanelMessage(
        key: const Key('vision-permission-granted'),
        icon: Icons.check_circle_outline,
        message: l10n.visionSetupPermissionGranted,
      ),
      CameraPermissionState.denied => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _PanelMessage(
            icon: Icons.camera_alt_outlined,
            message: l10n.visionSetupPermissionDenied,
          ),
          const SizedBox(height: 12),
          FilledButton(
            key: const Key('vision-permission-request'),
            onPressed: onRequest,
            child: Text(l10n.visionSetupRequestPermission),
          ),
        ],
      ),
      CameraPermissionState.permanentlyDenied => _settingsPanel(
        context,
        l10n.visionSetupPermissionSettings,
      ),
      CameraPermissionState.restricted => _settingsPanel(
        context,
        l10n.visionSetupPermissionRestricted,
      ),
      CameraPermissionState.unavailable => _PanelMessage(
        key: const Key('vision-permission-unavailable'),
        icon: Icons.portable_wifi_off_outlined,
        message: l10n.visionSetupPermissionUnavailable,
      ),
    };
  }

  Widget _settingsPanel(BuildContext context, String message) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _PanelMessage(icon: Icons.settings_outlined, message: message),
        const SizedBox(height: 12),
        OutlinedButton(
          key: const Key('vision-permission-settings'),
          onPressed: onOpenSettings,
          child: Text(l10n.visionSetupOpenSettings),
        ),
      ],
    );
  }
}

class _PanelMessage extends StatelessWidget {
  const _PanelMessage({super.key, required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Icon(icon),
        const SizedBox(width: 12),
        Expanded(child: Text(message)),
      ],
    ),
  );
}
