import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:strumsight/features/gamification/public.dart';

import '../../../core/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';

/// Settings section for the gamification layer (ADR 0393 §5).
///
/// Rendered as a [Card] of [SwitchListTile] rows and a 3-way intensity
/// chooser. The card deliberately uses [Column] + [IntrinsicHeight]-free
/// layouts so a 200% text scale can wrap into extra rows without
/// overflowing — the §6 A7 / "fix magasságú sorok" guard.
///
/// This widget is the *only* place the user reaches the celebratory
/// behaviour switches; flipping any of them lands synchronously through
/// [GamificationPreferencesNotifier.set], so the very next reward is
/// rendered under the new value (§5.3 "azonnal és teljesen").
class GamificationSettingsSection extends ConsumerWidget {
  const GamificationSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final prefs = ref.watch(gamificationPreferencesProvider);
    final notifier = ref.read(gamificationPreferencesProvider.notifier);

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---- Title + subtitle (no fixed height) -----------------------
            Text(
              l10n.gamificationSettingsTitle,
              key: const Key('gamification-settings-title'),
              style: TextStyle(
                fontFamily: 'Poppins',
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: palette.ink,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.gamificationSettingsSubtitle,
              key: const Key('gamification-settings-subtitle'),
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 13,
                color: palette.muted,
              ),
            ),
            const SizedBox(height: 16),

            // ---- Intensity chooser (3-way) -------------------------------
            Semantics(
              container: true,
              label: l10n.gamificationSettingsIntensityTitle,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.gamificationSettingsIntensityTitle,
                    key: const Key('gamification-settings-intensity-title'),
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: palette.ink,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final option in CelebrationIntensity.values)
                        _IntensityChip(
                          label: _labelFor(option, l10n),
                          semanticLabel: _semanticFor(option, l10n),
                          selected: prefs.intensity == option,
                          onSelected: () => notifier.setIntensity(option),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // ---- Toggle rows ---------------------------------------------
            _ToggleRow(
              keyValue: const Key('gamification-settings-haptics'),
              title: l10n.gamificationSettingsHapticsLabel,
              semanticsLabel: l10n.gamificationSettingsHapticsSemantics,
              value: prefs.hapticsEnabled,
              onChanged: notifier.setHapticsEnabled,
            ),
            _ToggleRow(
              keyValue: const Key('gamification-settings-sound'),
              title: l10n.gamificationSettingsSoundLabel,
              semanticsLabel: l10n.gamificationSettingsSoundSemantics,
              value: prefs.soundEnabled,
              onChanged: notifier.setSoundEnabled,
            ),
            _ToggleRow(
              keyValue: const Key('gamification-settings-reduce-motion'),
              title: l10n.gamificationSettingsReduceMotionLabel,
              semanticsLabel: l10n.gamificationSettingsReduceMotionSemantics,
              value: prefs.reduceMotion,
              onChanged: notifier.setReduceMotion,
            ),
            _ToggleRow(
              keyValue: const Key('gamification-settings-notifications'),
              title: l10n.gamificationSettingsNotificationsLabel,
              semanticsLabel: l10n.gamificationSettingsNotificationsSemantics,
              subtitle: l10n.gamificationSettingsNotificationsHint,
              value: prefs.notificationsEnabled,
              onChanged: notifier.setNotificationsEnabled,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.gamificationSettingsProgressPreservedHint,
              key: const Key('gamification-settings-progress-preserved-hint'),
              style: TextStyle(
                fontFamily: 'Poppins',
                fontSize: 12,
                color: palette.muted,
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _labelFor(CelebrationIntensity option, AppLocalizations l10n) =>
      switch (option) {
        CelebrationIntensity.full =>
          l10n.gamificationSettingsIntensityFullLabel,
        CelebrationIntensity.subtle =>
          l10n.gamificationSettingsIntensitySubtleLabel,
        CelebrationIntensity.silent =>
          l10n.gamificationSettingsIntensitySilentLabel,
      };

  static String _semanticFor(
    CelebrationIntensity option,
    AppLocalizations l10n,
  ) => switch (option) {
    CelebrationIntensity.full =>
      l10n.gamificationSettingsIntensityFullSemantics,
    CelebrationIntensity.subtle =>
      l10n.gamificationSettingsIntensitySubtleSemantics,
    CelebrationIntensity.silent =>
      l10n.gamificationSettingsIntensitySilentSemantics,
  };
}

class _IntensityChip extends StatelessWidget {
  const _IntensityChip({
    required this.label,
    required this.semanticLabel,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final String semanticLabel;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticLabel,
      selected: selected,
      button: true,
      child: ChoiceChip(
        key: Key('gamification-settings-intensity-$label'),
        label: Text(label),
        selected: selected,
        onSelected: (_) => onSelected(),
      ),
    );
  }
}

/// A switch row whose subtitle wraps freely — no fixed height, no
/// single-line `subtitle` truncation. The §6 A7 guard against fixed
/// heights relies on this.
class _ToggleRow extends StatelessWidget {
  const _ToggleRow({
    required this.keyValue,
    required this.title,
    required this.semanticsLabel,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });

  final Key keyValue;
  final String title;
  final String semanticsLabel;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Semantics(
        container: true,
        toggled: value,
        label: semanticsLabel,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    key: keyValue,
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 14,
                      color: palette.ink,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontSize: 12,
                        color: palette.muted,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Switch(value: value, onChanged: onChanged),
          ],
        ),
      ),
    );
  }
}
