import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/design_system/public.dart';
import '../../../core/music/guitar_strings.dart';
import '../../../core/music/tuning.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/mic_error_banner.dart';
import '../../../core/widgets/mic_permission_banner.dart';
import '../../../l10n/app_localizations.dart';
import '../../live/public.dart';
import '../../settings/public.dart';
import '../model/in_tune_lock.dart';
import '../model/tuner_reading.dart';
import '../model/tuner_stability.dart';
import '../model/tuner_ui_state.dart';
import '../providers/pinned_string_provider.dart';
import '../providers/reference_tone_provider.dart';
import '../providers/tuner_providers.dart';
import '../providers/tuner_tuning_provider.dart';
import '../widgets/cents_gauge.dart';

/// A simple chromatic tuner, pushed full-screen from the Live screen.
/// Migrated onto [SsStageScaffold] (Ch13 §9.9): the note/gauge cluster is the
/// hero, the multi-channel in-tune/direction readout is the feedback slot,
/// the string chips are the timeline slot, and the reference-tone control
/// plus the A4 readout are the bottom action.
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

  /// The "unstable" state has no field on the estimator's output — derived
  /// here in the UI layer only (brief §0.0/R5.1).
  final TunerStability _stability = TunerStability();
  bool _unstable = false;

  @override
  Widget build(BuildContext context) {
    ref.listen(tunerReadingProvider, (_, next) {
      final r = next.asData?.value;
      if (r == null) return;
      // The lock celebrates what the USER sees: in manual mode that is the
      // pinned target, not the chromatic nearest note (round 91).
      final pin = ref.read(pinnedStringProvider);
      final targetCents = pin == null
          ? r.cents
          : (r.hasSignal
                ? GuitarStrings.centsTo(
                    pin,
                    r.frequencyHz,
                    a4: ref.read(tuningReferenceProvider),
                  )
                : r.cents);
      final inTune = pin == null
          ? r.inTune
          : r.hasSignal && targetCents.abs() <= TunerReading.inTuneCents;
      final note = r.hasSignal ? (pin?.label ?? r.note) : '';
      final unstable = _stability.feed(
        hasSignal: r.hasSignal,
        note: note,
        cents: targetCents,
      );
      final justLocked = _lock.feed(inTune: inTune, note: note);
      if (justLocked) {
        HapticFeedback.mediumImpact();
      }
      if (justLocked || unstable != _unstable) {
        setState(() => _unstable = unstable);
      }
    });
    // A pin must not outlive its tuning (E2 isn't a drop-D target).
    ref.listen(tunerTuningProvider, (_, next) {
      ref.read(pinnedStringProvider.notifier).reconcile(next.strings);
    });
    // Tied to this route's lifetime: leaving Tuner drops the last listener,
    // so Riverpod tears the player (and the reference tone still sounding)
    // down (A5) — see `reference_tone_provider.dart`.
    final tone = ref.watch(referenceTonePlayerProvider);

    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final brightness = Theme.of(context).brightness;
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
    final state = tunerUiStateOf(
      hasSignal: reading.hasSignal,
      inTune: displayInTune,
      unstable: _unstable,
    );
    String tuningName(Tuning t) => switch (t.id) {
      'dropD' => l10n.tunerTuningDropD,
      'halfStepDown' => l10n.tunerTuningHalfStepDown,
      'dadgad' => l10n.tunerTuningDadgad,
      _ => l10n.tunerTuningStandard,
    };

    return SsStageScaffold(
      statusHeader: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (Navigator.canPop(context))
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              Expanded(
                child: Text(
                  l10n.tunerTitle,
                  style: TextStyle(
                    fontFamily: 'Montserrat',
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    color: palette.ink,
                  ),
                ),
              ),
              // Alternate tunings (round 89): the chips + nearest-string
              // mapping follow the selection, so a drop-D player tunes to
              // D2, not E2.
              PopupMenuButton<Tuning>(
                tooltip: l10n.tunerTuningLabel,
                onSelected: (t) =>
                    ref.read(tunerTuningProvider.notifier).set(t),
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
          // Mic problems must never be a silent idle (parity with Live,
          // round 13): denied permission gets the settings deep-link banner;
          // a start failure (busy / platform error) gets Retry. The error
          // banner stays up through a Retry until the restarted engine
          // produces a reading (AsyncData clears hasError) or fails again.
          if (!micGranted) const MicPermissionBanner(),
          if (micGranted && readingAsync.hasError)
            MicErrorBanner(onRetry: () => ref.invalidate(tunerReadingProvider)),
        ],
      ),
      hero: state == TunerUiState.idle
          ? Text(
              l10n.tunerListening,
              style: TextStyle(color: palette.muted, fontSize: 16),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedScale(
                  scale: _lock.isLocked ? 1.08 : 1.0,
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutBack,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      displayNote,
                      style: TextStyle(
                        fontFamily: 'Montserrat',
                        fontWeight: FontWeight.w800,
                        fontSize: 96,
                        height: 1,
                        color: _lock.isLocked
                            ? AppColors.successOn(brightness)
                            : palette.ink,
                      ),
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
              ],
            ),
      // The "hangolt" feedback is multi-channel (icon + text + colour, and a
      // haptic already fires on lock above) — never colour alone (A3). The
      // cents direction is spoken by `CentsGauge`'s own semantics AND shown
      // here as visible, scalable text (A2) — a screen-reader-only label
      // does nothing for a large-text/low-vision reader who isn't using one
      // (brief §5.1).
      feedback: state == TunerUiState.idle
          ? const SizedBox.shrink()
          : _TunerFeedback(state: state, cents: displayCents, l10n: l10n),
      // Which string is being tuned (round 84): the selected tuning's chips;
      // the nearest one lights copper, green once in tune.
      timeline: _StringChips(
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
      // Tune by EAR (round 94): with a target pinned, sound its reference
      // tone. Works with zero mic signal — that's the point.
      bottomAction: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (pinned != null)
            IconButton(
              tooltip: l10n.tunerPlayReference,
              icon: const Icon(Icons.volume_up),
              color: AppColors.primary,
              onPressed: () => tone.play(pinned.frequencyHz(a4)),
            ),
          Text(
            l10n.tunerReference(a4),
            style: TextStyle(
              fontFamily: 'Poppins',
              fontSize: 13,
              letterSpacing: 0.5,
              color: palette.muted,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// The visible (not merely spoken) in-tune / direction readout — icon,
/// colour and text together (A3), with the cents direction always shown as
/// text while a signal is present (A2).
class _TunerFeedback extends StatelessWidget {
  const _TunerFeedback({
    required this.state,
    required this.cents,
    required this.l10n,
  });

  final TunerUiState state;
  final double cents;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final brightness = Theme.of(context).brightness;
    final rounded = cents.abs().round();
    // Direction is the primary channel on BOTH `outOfTune` and `unstable`
    // (review MINOR-1): a big same-note jump is exactly the moment — a
    // string being wound — when the player most needs to see which way to
    // turn. `unstable` keeps the same direction icon/text as `outOfTune` and
    // adds "Hold steady…" as a secondary, dimmer line rather than replacing
    // the direction outright.
    final (icon, color, text) = switch (state) {
      TunerUiState.inTune => (
        Icons.check_circle,
        AppColors.successOn(brightness),
        l10n.tunerInTune.toUpperCase(),
      ),
      TunerUiState.unstable || TunerUiState.outOfTune => (
        cents >= 0 ? Icons.arrow_upward : Icons.arrow_downward,
        AppColors.primary,
        cents >= 0
            ? l10n.tunerCentsSharp(rounded)
            : l10n.tunerCentsFlat(rounded),
      ),
      TunerUiState.idle => (Icons.mic_none, palette.muted, ''),
    };
    final directionRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              fontFamily: 'Poppins',
              fontWeight: FontWeight.w600,
              letterSpacing: 1,
              color: color,
            ),
          ),
        ),
      ],
    );
    if (state != TunerUiState.unstable) return directionRow;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        directionRow,
        const SizedBox(height: 2),
        Text(
          l10n.tunerHoldSteady,
          style: TextStyle(
            fontFamily: 'Poppins',
            fontSize: 12,
            color: palette.muted,
          ),
        ),
      ],
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

  /// The state suffix a screen reader appends to the string name (round 126):
  /// the ✓/📌 glyphs are decorative, so their meaning has to be spoken.
  String _stateSuffix(AppLocalizations l10n, GuitarString s) {
    if (identical(s, active) && inTune) return ', ${l10n.tunerInTune}';
    if (identical(s, pinned)) return ', ${l10n.tunerPinned}';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final l10n = AppLocalizations.of(context);
    // scaleDown: six chips are wider than a 320-wide screen.
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (final s in strings)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Semantics(
                button: true,
                selected: identical(s, active),
                label: l10n.tunerStringSemantic(s.label, _stateSuffix(l10n, s)),
                // onTap HERE so a screen reader can activate the pin toggle —
                // excludeSemantics drops the child's own action (round 130).
                onTap: () => onTap(s),
                excludeSemantics: true,
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
            ),
        ],
      ),
    );
  }
}
