import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../../core/i18n/locale_provider.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/theme_mode_provider.dart';
import '../../../l10n/app_localizations.dart';
import '../providers/confidence_threshold_provider.dart';

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
