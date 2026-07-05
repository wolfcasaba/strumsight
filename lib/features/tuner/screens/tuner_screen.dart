import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
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
    final reading = ref.watch(tunerReadingProvider).asData?.value ??
        TunerReading.silent;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.tunerTitle)),
      body: Center(
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
                      style: const TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: FontWeight.w600,
                        letterSpacing: 2,
                        color: AppColors.confidenceHigh,
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
    );
  }
}
