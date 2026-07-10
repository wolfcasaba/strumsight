import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/mic_error_banner.dart';
import '../../../core/widgets/mic_permission_banner.dart';
import '../../../l10n/app_localizations.dart';
import '../../live/providers/live_providers.dart';
import '../../settings/providers/tuning_reference_provider.dart';
import '../model/tuner_reading.dart';
import '../providers/tuner_providers.dart';
import '../widgets/cents_gauge.dart';

/// A simple chromatic tuner, pushed full-screen from the Live screen.
class TunerScreen extends ConsumerWidget {
  const TunerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final readingAsync = ref.watch(tunerReadingProvider);
    final reading = readingAsync.asData?.value ?? TunerReading.silent;
    final a4 = ref.watch(tuningReferenceProvider);
    final micGranted = ref.watch(micPermissionProvider).asData?.value ?? true;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.tunerTitle)),
      body: Column(
        children: [
          // Mic problems must never be a silent idle (parity with Live,
          // round 13): denied permission gets the settings deep-link banner;
          // a start failure (busy / platform error) gets Retry. The error
          // banner stays up through a Retry until the restarted engine
          // produces a reading (AsyncData clears hasError) or fails again.
          if (!micGranted)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: MicPermissionBanner(),
            ),
          if (micGranted && readingAsync.hasError)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: MicErrorBanner(
                onRetry: () => ref.invalidate(tunerReadingProvider),
              ),
            ),
          Expanded(
            child: Center(
        child: reading.hasSignal
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    reading.note,
                    style: TextStyle(
                      fontFamily: 'Montserrat',
                      fontWeight: FontWeight.w800,
                      fontSize: 96,
                      height: 1,
                      color: palette.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${reading.frequencyHz.toStringAsFixed(1)} Hz',
                    style: TextStyle(
                      fontFamily: 'Poppins',
                      color: palette.muted,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 32),
                  CentsGauge(cents: reading.cents, inTune: reading.inTune),
                  const SizedBox(height: 12),
                  AnimatedOpacity(
                    opacity: reading.inTune ? 1 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: Text(
                      l10n.tunerInTune.toUpperCase(),
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        letterSpacing: 2,
                        color: AppColors.successOn(Theme.of(context).brightness),
                      ),
                    ),
                  ),
                ],
              )
            : Text(
                l10n.tunerListening,
                style: TextStyle(color: palette.muted, fontSize: 16),
              ),
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 16, top: 8),
              child: Text(
                l10n.tunerReference(a4),
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 13,
                  letterSpacing: 0.5,
                  color: palette.muted,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
