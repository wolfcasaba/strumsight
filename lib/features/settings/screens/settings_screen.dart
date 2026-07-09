import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/i18n/locale_provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/theme_mode_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../../auth/providers/auth_providers.dart';
import '../providers/capo_provider.dart';
import '../providers/confidence_threshold_provider.dart';
import '../providers/left_handed_provider.dart';
import '../providers/tuning_reference_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);
    final threshold = ref.watch(confidenceThresholdProvider);

    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
        children: [
          Text(
            l10n.settingsTitle,
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontWeight: FontWeight.w800,
              fontSize: 30,
              color: palette.ink,
            ),
          ),
          const SizedBox(height: 28),

          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: ListTile(
              leading: const Icon(Icons.insights_outlined,
                  color: AppColors.primary),
              title: Text(l10n.progressTitle),
              subtitle: Text(l10n.progressTotalPractice),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/progress'),
            ),
          ),
          const SizedBox(height: 28),

          if (ref.watch(accountEnabledProvider)) ...[
            _SectionHeader(l10n.settingsAccount),
            const _AccountSection(),
            const SizedBox(height: 28),
          ],

          _SectionHeader(l10n.settingsAppearance),
          SegmentedButton<ThemeMode>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment(value: ThemeMode.light, label: Text(l10n.themeLight)),
              ButtonSegment(value: ThemeMode.dark, label: Text(l10n.themeDark)),
              ButtonSegment(value: ThemeMode.system, label: Text(l10n.themeSystem)),
            ],
            selected: {themeMode},
            onSelectionChanged: (s) =>
                ref.read(themeModeProvider.notifier).setMode(s.first),
          ),
          const SizedBox(height: 28),

          _SectionHeader(l10n.settingsLanguage),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: Text(l10n.settingsSystemLanguage),
                selected: locale == null,
                onSelected: (_) => ref.read(localeProvider.notifier).set(null),
              ),
              ChoiceChip(
                label: const Text('English'),
                selected: locale?.languageCode == 'en',
                onSelected: (_) =>
                    ref.read(localeProvider.notifier).set(const Locale('en')),
              ),
              ChoiceChip(
                label: const Text('Magyar'),
                selected: locale?.languageCode == 'hu',
                onSelected: (_) =>
                    ref.read(localeProvider.notifier).set(const Locale('hu')),
              ),
            ],
          ),
          const SizedBox(height: 28),

          _SectionHeader(l10n.settingsConfidenceThreshold),
          Row(
            children: [
              Expanded(
                child: Slider(
                  value: threshold,
                  onChanged: (v) =>
                      ref.read(confidenceThresholdProvider.notifier).set(v),
                ),
              ),
              SizedBox(
                width: 48,
                child: Text(
                  '${(threshold * 100).round()}%',
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontWeight: FontWeight.w600,
                    color: palette.ink,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          Text(
            l10n.settingsConfidenceHint,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              color: palette.muted,
            ),
          ),
          const SizedBox(height: 28),

          _SectionHeader(l10n.settingsTuningReference),
          const _TuningReferenceStepper(),
          const SizedBox(height: 28),

          _SectionHeader(l10n.settingsCapo),
          const _CapoStepper(),
          const SizedBox(height: 28),

          _SectionHeader(l10n.settingsPlaying),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(l10n.settingsLeftHanded),
            subtitle: Text(l10n.settingsLeftHandedHint),
            value: ref.watch(leftHandedProvider),
            onChanged: (v) => ref.read(leftHandedProvider.notifier).set(v),
          ),
          const SizedBox(height: 28),

          _SectionHeader(l10n.settingsAbout),
          FutureBuilder<String>(
            future: _appVersion(),
            builder: (context, snap) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 20, color: palette.muted),
                  const SizedBox(width: 12),
                  Text(
                    l10n.settingsVersion(snap.data ?? '…'),
                    style: TextStyle(fontFamily: 'Poppins', color: palette.ink),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Optional account: sign in to sync settings across devices. The app is fully
/// usable logged out — detection never needs the network.
class _AccountSection extends ConsumerWidget {
  const _AccountSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final auth = ref.watch(authControllerProvider);
    final user = auth.value;

    if (auth.isLoading && !auth.hasValue) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 8),
        child: SizedBox(
          height: 20,
          width: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    if (user != null) {
      return Row(
        children: [
          const Icon(Icons.account_circle_outlined, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              l10n.accountSignedInAs(user.email),
              style: TextStyle(fontFamily: 'Poppins', color: palette.ink),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          TextButton(
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
            child: Text(l10n.accountSignOut),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.accountSyncHint,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            color: palette.muted,
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () => context.push('/login'),
          icon: const Icon(Icons.login, size: 18, color: AppColors.primary),
          label: Text(l10n.accountSignIn),
        ),
      ],
    );
  }
}

/// A4 concert-pitch stepper (400–480 Hz). Standard is 440; the value drives
/// the tuner's note/cents mapping and syncs to the account when signed in.
class _TuningReferenceStepper extends ConsumerWidget {
  const _TuningReferenceStepper();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final a4 = ref.watch(tuningReferenceProvider);
    final notifier = ref.read(tuningReferenceProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton.outlined(
              onPressed: a4 > TuningReferenceNotifier.minHz
                  ? () => notifier.set(a4 - 1)
                  : null,
              icon: const Icon(Icons.remove),
              tooltip: '−1 Hz',
            ),
            Expanded(
              child: Text(
                'A = $a4 Hz',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                  color: palette.ink,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            IconButton.outlined(
              onPressed: a4 < TuningReferenceNotifier.maxHz
                  ? () => notifier.set(a4 + 1)
                  : null,
              icon: const Icon(Icons.add),
              tooltip: '+1 Hz',
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          l10n.settingsTuningHint,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            color: palette.muted,
          ),
        ),
      ],
    );
  }
}

/// Capo fret stepper (0–11). 0 = no capo; a higher fret transposes the shown
/// chord SHAPE down by that many semitones. Local-only (a capo is a physical,
/// per-guitar state), so unlike A4 it is not synced.
class _CapoStepper extends ConsumerWidget {
  const _CapoStepper();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final capo = ref.watch(capoProvider);
    final notifier = ref.read(capoProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton.outlined(
              onPressed:
                  capo > CapoNotifier.minFret ? () => notifier.set(capo - 1) : null,
              icon: const Icon(Icons.remove),
              tooltip: '−1',
            ),
            Expanded(
              child: Text(
                capo == 0 ? l10n.settingsCapoOff : l10n.settingsCapoFret(capo),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontWeight: FontWeight.w600,
                  fontSize: 18,
                  color: palette.ink,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            IconButton.outlined(
              onPressed:
                  capo < CapoNotifier.maxFret ? () => notifier.set(capo + 1) : null,
              icon: const Icon(Icons.add),
              tooltip: '+1',
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          l10n.settingsCapoHint,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 13,
            color: palette.muted,
          ),
        ),
      ],
    );
  }
}

/// App version, with a safe fallback (the platform channel is absent in tests).
Future<String> _appVersion() async {
  try {
    final info = await PackageInfo.fromPlatform();
    return info.version;
  } catch (_) {
    return '1.0.0';
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text.toUpperCase(),
        style: TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w600,
          fontSize: 12,
          letterSpacing: 1.5,
          color: palette.muted,
        ),
      ),
    );
  }
}
