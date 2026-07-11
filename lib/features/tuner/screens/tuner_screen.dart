import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/mic_error_banner.dart';
import '../../../core/widgets/mic_permission_banner.dart';
import '../../../l10n/app_localizations.dart';
import '../../learn/providers/backing_provider.dart';
import '../../live/providers/live_providers.dart';
import '../../settings/providers/tuning_reference_provider.dart';
import '../model/guitar_strings.dart';
import '../model/in_tune_lock.dart';
import '../model/tuner_reading.dart';
import '../model/tuning.dart';
import '../providers/pinned_string_provider.dart';
import '../providers/tuner_providers.dart';
import '../providers/tuner_tuning_provider.dart';
import '../widgets/cents_gauge.dart';

/// A simple chromatic tuner, pushed full-screen from the Live screen.
class TunerScreen extends ConsumerStatefulWidget {
  const TunerScreen({super.key});

  @override
  ConsumerState<TunerScreen> createState() => _TunerScreenState();
}

class _TunerScreenState extends ConsumerState<TunerScreen> {
  /// HOLDING the pitch is the achievement (round 85): after ~6 consecutive
  /// in-tune readings the lock engages once — a firm haptic + a scale pulse
  /// on the note. Re-arms when the pitch drifts or the string changes.
  final InTuneLock _lock = InTuneLock();

  @override
  Widget build(BuildContext context) {
    ref.listen(tunerReadingProvider, (_, next) {
      final r = next.asData?.value;
      if (r == null) return;
      // The lock celebrates what the USER sees: in manual mode that is the
      // pinned target, not the chromatic nearest note (round 91).
      final pin = ref.read(pinnedStringProvider);
      final inTune = pin == null
          ? r.inTune
          : r.hasSignal &&
                GuitarStrings.centsTo(
                      pin,
                      r.frequencyHz,
                      a4: ref.read(tuningReferenceProvider),
                    ).abs() <=
                    TunerReading.inTuneCents;
      final justLocked = _lock.feed(
        inTune: inTune,
        note: r.hasSignal ? (pin?.label ?? r.note) : '',
      );
      if (justLocked) {
        HapticFeedback.mediumImpact();
        setState(() {}); // reflect the locked state in the pulse
      }
    });
    // A pin must not outlive its tuning (E2 isn't a drop-D target).
    ref.listen(tunerTuningProvider, (_, next) {
      ref.read(pinnedStringProvider.notifier).reconcile(next.strings);
    });
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final readingAsync = ref.watch(tunerReadingProvider);
    final reading = readingAsync.asData?.value ?? TunerReading.silent;
    final a4 = ref.watch(tuningReferenceProvider);
    final micGranted = ref.watch(micPermissionProvider).asData?.value ?? true;
    final tuning = ref.watch(tunerTuningProvider);
    final pinned = ref.watch(pinnedStringProvider);
    // Manual mode reads against the pinned target; auto stays chromatic.
    final displayCents = pinned != null && reading.hasSignal
        ? GuitarStrings.centsTo(pinned, reading.frequencyHz, a4: a4)
        : reading.cents;
    final displayInTune = pinned == null
        ? reading.inTune
        : reading.hasSignal && displayCents.abs() <= TunerReading.inTuneCents;
    final displayNote = pinned?.label ?? reading.note;
    String tuningName(Tuning t) => switch (t.id) {
      'dropD' => l10n.tunerTuningDropD,
      'halfStepDown' => l10n.tunerTuningHalfStepDown,
      'dadgad' => l10n.tunerTuningDadgad,
      _ => l10n.tunerTuningStandard,
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tunerTitle),
        actions: [
          // Alternate tunings (round 89): the chips + nearest-string mapping
          // follow the selection, so a drop-D player tunes to D2, not E2.
          PopupMenuButton<Tuning>(
            tooltip: l10n.tunerTuningLabel,
            onSelected: (t) => ref.read(tunerTuningProvider.notifier).set(t),
            itemBuilder: (context) => [
              for (final t in Tunings.all)
                CheckedPopupMenuItem(
                  value: t,
                  checked: identical(t, tuning),
                  child: Text(tuningName(t)),
                ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    tuningName(tuning),
                    style: const TextStyle(
                      fontFamily: 'Poppins',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down, size: 20),
                ],
              ),
            ),
          ),
        ],
      ),
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
                        AnimatedScale(
                          scale: _lock.isLocked ? 1.08 : 1.0,
                          duration: const Duration(milliseconds: 160),
                          curve: Curves.easeOutBack,
                          child: Text(
                            displayNote,
                            style: TextStyle(
                              fontFamily: 'Montserrat',
                              fontWeight: FontWeight.w800,
                              fontSize: 96,
                              height: 1,
                              color: _lock.isLocked
                                  ? AppColors.successOn(
                                      Theme.of(context).brightness,
                                    )
                                  : palette.ink,
                            ),
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
                        CentsGauge(cents: displayCents, inTune: displayInTune),
                        const SizedBox(height: 12),
                        AnimatedOpacity(
                          opacity: displayInTune ? 1 : 0,
                          duration: const Duration(milliseconds: 150),
                          child: Text(
                            l10n.tunerInTune.toUpperCase(),
                            style: TextStyle(
                              fontFamily: 'Poppins',
                              fontWeight: FontWeight.w600,
                              letterSpacing: 2,
                              color: AppColors.successOn(
                                Theme.of(context).brightness,
                              ),
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
          // Which string is being tuned (round 84): the selected tuning's
          // chips; the nearest one lights copper, green once in tune.
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _StringChips(
              strings: tuning.strings,
              active:
                  pinned ??
                  (reading.hasSignal
                      ? GuitarStrings.nearest(
                          reading.frequencyHz,
                          a4: a4,
                          strings: tuning.strings,
                        )
                      : null),
              pinned: pinned,
              inTune: displayInTune,
              onTap: (s) => ref.read(pinnedStringProvider.notifier).toggle(s),
            ),
          ),
          // Tune by EAR (round 94): with a target pinned, sound its reference
          // tone. Works with zero mic signal — that's the point.
          if (pinned != null)
            IconButton(
              tooltip: l10n.tunerPlayReference,
              icon: const Icon(Icons.volume_up),
              color: AppColors.primary,
              onPressed: () =>
                  ref.read(backingProvider).playTone(pinned.frequencyHz(a4)),
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

/// The string row of the selected tuning. Shape + colour encode state (never
/// hue alone): the active chip is filled and enlarged, in-tune adds a check,
/// a manually pinned chip adds a pin glyph. Tapping toggles the pin.
class _StringChips extends StatelessWidget {
  const _StringChips({
    required this.strings,
    required this.active,
    required this.pinned,
    required this.inTune,
    required this.onTap,
  });

  final List<GuitarString> strings;
  final GuitarString? active;
  final GuitarString? pinned;
  final bool inTune;
  final ValueChanged<GuitarString> onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final s in strings)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => onTap(s),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                padding: EdgeInsets.symmetric(
                  horizontal: identical(s, active) ? 14 : 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: identical(s, active)
                      ? (inTune
                            ? AppColors.successOn(
                                Theme.of(context).brightness,
                              ).withValues(alpha: 0.18)
                            : AppColors.primary.withValues(alpha: 0.2))
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: identical(s, active)
                        ? (inTune
                              ? AppColors.successOn(
                                  Theme.of(context).brightness,
                                )
                              : AppColors.primary)
                        : palette.muted.withValues(alpha: 0.4),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (identical(s, pinned)) ...[
                      Icon(
                        Icons.push_pin,
                        size: 12,
                        color: identical(s, active)
                            ? palette.ink
                            : palette.muted,
                      ),
                      const SizedBox(width: 3),
                    ],
                    Text(
                      s.label,
                      style: TextStyle(
                        fontFamily: 'Poppins',
                        fontWeight: identical(s, active)
                            ? FontWeight.w700
                            : FontWeight.w500,
                        fontSize: 13,
                        color: identical(s, active)
                            ? palette.ink
                            : palette.muted,
                      ),
                    ),
                    if (identical(s, active) && inTune) ...[
                      const SizedBox(width: 4),
                      Icon(
                        Icons.check_rounded,
                        size: 14,
                        color: AppColors.successOn(
                          Theme.of(context).brightness,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}
