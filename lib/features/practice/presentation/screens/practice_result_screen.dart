import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../../../core/design_system/public.dart';
import '../../../../l10n/app_localizations.dart';
import '../../domain/model/practice_history_entry.dart';
import '../../domain/model/practice_insight.dart';
import '../../domain/model/practice_metric_snapshot.dart';
import '../../domain/model/practice_mode.dart';
import '../../domain/model/practice_session_result.dart';
import '../../domain/model/speed_builder_policy.dart';
import '../../domain/model/tempo.dart';
import '../practice_route_args.dart';
import '../providers/practice_result_providers.dart';
import '../widgets/practice_mode_card.dart' show practiceModeLabel;
import '../widgets/score_breakdown.dart';
import '../widgets/timing_bias_chart.dart';
import 'practice_history_screen.dart';
import 'practice_setup_screen.dart';
import 'speed_builder_screen.dart';

/// The confidence threshold below which a scored result is shown as a
/// qualitative range instead of an exact categorical percentage (ADR 0283
/// §Döntés 1, inclusive at the boundary — §0.0/B/R8). The measured input is
/// the session's target-coverage ratio; there is no session-level
/// `confidence` field on the fan today.
const double practiceResultConfidenceThreshold = 0.60;

/// The coverage-ratio confidence for one history entry, or `null` when the
/// session set no targets (e.g. Free Practice, which never reads this).
double? practiceResultConfidence(PracticeHistoryEntry entry) {
  if (entry.totalTargets <= 0) return null;
  return entry.resolvedTargets / entry.totalTargets;
}

/// Whether [entry] ended before reaching every target (§6 A2). Only
/// [PracticeFinishReason.completedAllTargets] counts as a full session —
/// every other reason (including a user-initiated stop) ended the session
/// before its targets were exhausted.
bool practiceResultIsPartial(PracticeHistoryEntry entry) {
  return entry.finishReasonCode !=
      PracticeFinishReason.completedAllTargets.code;
}

/// The mode-specific Practice result screen (ADR 0084 §Döntés 1, 10, 11).
///
/// Every dimension is rendered iff:
///   * it is **applicable** to the entry's mode (otherwise the dimension
///     is omitted entirely — `findsNothing` — never rendered as 0%);
///   * the entry recorded an [PracticeMetricDimensionAvailable] for it
///     (otherwise a localised "not enough data" string is shown).
class PracticeResultScreen extends ConsumerWidget {
  const PracticeResultScreen({required this.entry, super.key});

  final PracticeHistoryEntry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final mode = _modeFor(entry.modeCode);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.practiceResultTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Header(entry: entry),
            const SizedBox(height: 16),
            if (mode == PracticeMode.freePractice)
              _FreePracticeLayout(entry: entry)
            else
              _ScoredLayout(entry: entry, mode: mode),
            const SizedBox(height: 16),
            _InsightSection(entry: entry),
            const SizedBox(height: 16),
            _RewardSection(sessionId: entry.id),
            const SizedBox(height: 16),
            _NextStepAction(entry: entry),
            const SizedBox(height: 12),
            _ShareSection(entry: entry),
            const SizedBox(height: 12),
            _QuickLinksRow(entry: entry),
          ],
        ),
      ),
    );
  }

  PracticeMode _modeFor(String code) {
    for (final mode in PracticeMode.values) {
      if (mode.code == code) return mode;
    }
    return PracticeMode.strumPattern;
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.entry});
  final PracticeHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final typography = Theme.of(context).extension<SsTypography>()!;
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          entry.displayTitle.isEmpty
              ? l10n.practiceResultTitle
              : entry.displayTitle,
          style: typography.titleLarge.copyWith(color: colors.textPrimary),
        ),
        const SizedBox(height: SsSpacing.space1),
        Row(
          children: [
            Flexible(
              child: Text(
                _finishReasonLabel(l10n, entry.finishReasonCode),
                style: typography.bodyMedium.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
            if (practiceResultIsPartial(entry)) ...[
              const SizedBox(width: SsSpacing.space2),
              _Badge(label: l10n.practiceResultPartialBadge),
            ],
          ],
        ),
      ],
    );
  }
}

/// A small pill-shaped status label (A2 — the "partial session" marker).
class _Badge extends StatelessWidget {
  const _Badge({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: SsSpacing.space2,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceSunken,
        borderRadius: BorderRadius.circular(SsRadius.pill),
      ),
      child: Text(
        label,
        style: typography.labelLarge.copyWith(color: colors.textPrimary),
      ),
    );
  }
}

class _ScoredLayout extends StatelessWidget {
  const _ScoredLayout({required this.entry, required this.mode});
  final PracticeHistoryEntry entry;
  final PracticeMode mode;

  @override
  Widget build(BuildContext context) {
    final confidence = practiceResultConfidence(entry);
    if (confidence != null && confidence < practiceResultConfidenceThreshold) {
      // A1 — below the threshold the result is NOT categorical: no exact
      // percentage is rendered anywhere, only the qualitative range the
      // measurement actually supports (ADR 0283 §Döntés 1).
      return _LowConfidenceSummary(entry: entry);
    }
    return _ScoredBreakdown(entry: entry, mode: mode);
  }
}

/// The categorical breakdown — rendered only at/above the confidence
/// threshold, unchanged from the pre-R22 shape (the three pinned tests all
/// fixture ratios above the threshold, so this path stays byte-identical).
class _ScoredBreakdown extends StatelessWidget {
  const _ScoredBreakdown({required this.entry, required this.mode});
  final PracticeHistoryEntry entry;
  final PracticeMode mode;

  @override
  Widget build(BuildContext context) {
    final snapshot = entry.finalMetricSnapshot;
    final l10n = AppLocalizations.of(context);

    final breakdown = ScoreBreakdown(
      dimensions: <ScoreBreakdownRow>[
        if (PracticeMetricKind.overall.isApplicableTo(mode))
          (
            label: PracticeMetricKind.overall.label(l10n),
            dimension: snapshot.overall,
          ),
        if (PracticeMetricKind.completion.isApplicableTo(mode))
          (
            label: PracticeMetricKind.completion.label(l10n),
            dimension: snapshot.completion,
          ),
        if (PracticeMetricKind.rhythm.isApplicableTo(mode))
          (
            label: PracticeMetricKind.rhythm.label(l10n),
            dimension: snapshot.rhythm,
          ),
        if (PracticeMetricKind.direction.isApplicableTo(mode))
          (
            label: PracticeMetricKind.direction.label(l10n),
            dimension: snapshot.direction,
          ),
        if (PracticeMetricKind.chord.isApplicableTo(mode))
          (
            label: PracticeMetricKind.chord.label(l10n),
            dimension: snapshot.chord,
          ),
        if (PracticeMetricKind.chordPair.isApplicableTo(mode))
          (label: PracticeMetricKind.chordPair.label(l10n), dimension: null),
        // Speed Builder result tile: dead-code branch removed (brief m3).
        // The real wiring lives one layer down — the controller owns
        // `SpeedBuilderState` and the controller is out of scope for
        // R18; until then this screen has no Speed Builder row to show.
        // Re-introduce once the controller exposes the active state
        // through `entry` (R19 follow-up, see the brief's §3 followups).
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        breakdown,
        const SizedBox(height: 16),
        TimingBiasChart(
          detailAttempts: entry.detailAttempts,
          timingBias: entry.timingBias,
        ),
      ],
    );
  }
}

/// The qualitative range shown instead of a categorical score when the
/// coverage-ratio confidence is below [practiceResultConfidenceThreshold]
/// (A1). No `%` is ever rendered here — only the counted targets, which the
/// user can verify against the session they just ran.
class _LowConfidenceSummary extends StatelessWidget {
  const _LowConfidenceSummary({required this.entry});
  final PracticeHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    return SsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: colors.info),
              const SizedBox(width: SsSpacing.space2),
              Expanded(
                child: Text(
                  l10n.practiceResultConfidenceLowTitle,
                  style: typography.titleMedium.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: SsSpacing.space2),
          Text(
            l10n.practiceResultConfidenceLowBody(
              entry.resolvedTargets,
              entry.totalTargets,
            ),
            style: typography.bodyMedium.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Reads the finished session's reward straight from the ledger (A5, ADR
/// 0283 §Döntés 4). Never computes a number itself — an absent ledger entry
/// renders as "no reward", not an estimate.
class _RewardSection extends ConsumerWidget {
  const _RewardSection({required this.sessionId});
  final String sessionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    final reward = ref.watch(practiceRewardForSessionProvider(sessionId));
    return SsCard(
      child: Row(
        children: [
          Icon(Icons.stars_rounded, color: colors.brand),
          const SizedBox(width: SsSpacing.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.practiceResultRewardTitle,
                  style: typography.labelLarge.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: SsSpacing.space1),
                Text(
                  reward == null
                      ? l10n.practiceResultRewardNone
                      : l10n.practiceResultRewardXp(reward.totalXp),
                  style: typography.bodyMedium.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The executable next step (A7): restarts the SAME definition through the
/// Setup screen, correctly parameterized by [PracticeHistoryEntry.definitionId]
/// — never a text-only suggestion.
class _NextStepAction extends StatelessWidget {
  const _NextStepAction({required this.entry});
  final PracticeHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => PracticeSetupScreen(
              argsOverride: PracticeSetupArgs(
                request: PracticeSetupRequest.hasId,
                definitionId: entry.definitionId,
              ),
            ),
          ),
        ),
        icon: const Icon(Icons.replay),
        label: Text(l10n.practiceResultNextStepCta),
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
      ),
    );
  }
}

/// The MINIMAL, hand-picked share projection (§0.0/B/R12, ADR 0283 A8): a
/// session id, a title, the mode, the date, and one summary metric. The raw
/// [PracticeHistoryEntry] — per-attempt detail, coaching codes, skill tags,
/// timing bias, score points — is never read by [_ShareSummaryCard].
@immutable
class PracticeResultShareSummary {
  const PracticeResultShareSummary({
    required this.sessionId,
    required this.title,
    required this.modeLabel,
    required this.createdAt,
    required this.resultLabel,
  });

  final String sessionId;
  final String title;
  final String modeLabel;
  final DateTime createdAt;
  final String resultLabel;
}

/// Builds the minimal share projection from an entry. The result label is
/// the counted target coverage — never an exact percentage — so a share
/// action never overstates certainty even at high confidence (ADR 0283
/// §Döntés 1 applies here too).
PracticeResultShareSummary practiceResultShareSummaryFrom(
  PracticeHistoryEntry entry,
  AppLocalizations l10n,
) {
  final mode = PracticeMode.values.firstWhere(
    (m) => m.code == entry.modeCode,
    orElse: () => PracticeMode.strumPattern,
  );
  return PracticeResultShareSummary(
    sessionId: entry.id,
    title: entry.displayTitle.isEmpty
        ? l10n.practiceResultTitle
        : entry.displayTitle,
    modeLabel: practiceModeLabel(l10n, mode),
    createdAt: entry.createdAt,
    resultLabel: entry.totalTargets > 0
        ? '${entry.resolvedTargets}/${entry.totalTargets}'
        : '${entry.attemptsCount}',
  );
}

class _ShareSummaryCard extends StatelessWidget {
  const _ShareSummaryCard({required this.summary});
  final PracticeResultShareSummary summary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    return SsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.practiceResultShareSummaryTitle,
            style: typography.labelLarge.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: SsSpacing.space2),
          Text(
            summary.title,
            style: typography.bodyLarge.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: SsSpacing.space1),
          Text(
            l10n.practiceResultShareMode(summary.modeLabel),
            style: typography.bodyMedium.copyWith(color: colors.textSecondary),
          ),
          Text(
            l10n.practiceResultShareWhen(
              DateFormat.yMMMd().format(summary.createdAt),
            ),
            style: typography.bodyMedium.copyWith(color: colors.textSecondary),
          ),
          Text(
            l10n.practiceResultShareResult(summary.resultLabel),
            style: typography.bodyMedium.copyWith(color: colors.textSecondary),
          ),
          Text(
            l10n.practiceResultShareSessionId(summary.sessionId),
            style: typography.bodyMedium.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

/// Toggleable share affordance (A8). Tapping "Share" reveals the minimal
/// projection card in-place; there is no real share sink wired in this round
/// (§0.0/B/R12 — the Community composer wiring is a named follow-up).
class _ShareSection extends StatefulWidget {
  const _ShareSection({required this.entry});
  final PracticeHistoryEntry entry;

  @override
  State<_ShareSection> createState() => _ShareSectionState();
}

class _ShareSectionState extends State<_ShareSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: () => setState(() => _expanded = !_expanded),
          icon: const Icon(Icons.ios_share),
          label: Text(l10n.practiceResultShareCta),
        ),
        if (_expanded) ...[
          const SizedBox(height: 8),
          _ShareSummaryCard(
            summary: practiceResultShareSummaryFrom(widget.entry, l10n),
          ),
        ],
      ],
    );
  }
}

/// Round-scoped, route-free entry points to the two new practice surfaces
/// (§0.0/B/R11): pushed via `Navigator`, not a named route.
class _QuickLinksRow extends StatelessWidget {
  const _QuickLinksRow({required this.entry});
  final PracticeHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const PracticeHistoryScreen(),
              ),
            ),
            icon: const Icon(Icons.history),
            label: Text(l10n.practiceResultHistoryCta),
          ),
        ),
        const SizedBox(width: SsSpacing.space3),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    SpeedBuilderScreen(policy: _speedBuilderPolicyFor(entry)),
              ),
            ),
            icon: const Icon(Icons.speed),
            label: Text(l10n.practiceResultSpeedBuilderCta),
          ),
        ),
      ],
    );
  }
}

/// Derives a starting Speed Builder policy from the entry's own stable
/// tempo when it has one, otherwise a conservative default. Presentation-
/// layer construction of a domain value object — not a policy decision, the
/// domain's [SpeedBuilderEngine] still owns every ladder rule.
SpeedBuilderPolicy _speedBuilderPolicyFor(PracticeHistoryEntry entry) {
  final startBpm = (entry.highestStableTempoBpm ?? 80.0).clamp(
    Tempo.minimumBpm,
    Tempo.maximumBpm,
  );
  final targetBpm = (startBpm + 40).clamp(Tempo.minimumBpm, Tempo.maximumBpm);
  return SpeedBuilderPolicy(
    startBpm: Tempo(startBpm),
    targetBpm: Tempo(targetBpm),
    stepBpm: 5,
  );
}

class _FreePracticeLayout extends StatelessWidget {
  const _FreePracticeLayout({required this.entry});
  final PracticeHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Free Practice is intentionally score-free (ADR 0082 §1).
    // The result screen surfaces only the facts the engine already exposes
    // in the per-session summary — no accuracy, no combo, no pass/fail.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FactTile(
          label: l10n.practiceFreePracticeActiveDuration,
          value: _durationLabel(entry.activeDuration),
        ),
        _FactTile(
          label: l10n.practiceFreePracticeStrumCount,
          value: '${entry.attemptsCount}',
        ),
      ],
    );
  }
}

class _InsightSection extends StatelessWidget {
  const _InsightSection({required this.entry});
  final PracticeHistoryEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Without the live coach context, the result screen reads the entry's
    // already-persisted coachingSummary as the human-readable hints. The
    // codes are localisable here so a future i18n round can map them.
    if (entry.coachingSummary.isEmpty) {
      return const SizedBox.shrink();
    }
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    return SsCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.practiceResultCoachingTitle,
            style: typography.titleMedium.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: SsSpacing.space2),
          for (final code in entry.coachingSummary) _InsightRow(code: code),
        ],
      ),
    );
  }
}

class _InsightRow extends StatelessWidget {
  const _InsightRow({required this.code});
  final String code;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text('• ${_label(context, code)}'),
    );
  }

  /// Resolves a coach code to its ARB-backed localised string.
  ///
  /// Each code in [PracticeInsightCode.values] / [PracticeRecommendationKind.values]
  /// has a paired `practiceInsight*` / `practiceRecommendation*` ARB key
  /// (R20 §6 A2). Unknown codes fall through to a humanised form of the
  /// code itself so a future code never produces an empty row.
  String _label(BuildContext context, String code) {
    final l10n = AppLocalizations.of(context);
    switch (code) {
      case PracticeInsightCode.noSignal:
        return l10n.practiceInsightNoSignal;
      case PracticeInsightCode.lowCompletion:
        return l10n.practiceInsightLowCompletion;
      case PracticeInsightCode.biasLate:
        return l10n.practiceInsightBiasLate;
      case PracticeInsightCode.biasEarly:
        return l10n.practiceInsightBiasEarly;
      case PracticeInsightCode.directionError:
        return l10n.practiceInsightDirectionError;
      case PracticeInsightCode.chordError:
        return l10n.practiceInsightChordError;
      case PracticeInsightCode.chordPairProblem:
        return l10n.practiceInsightChordPairProblem;
      case PracticeInsightCode.tempoTooHigh:
        return l10n.practiceInsightTempoTooHigh;
      case PracticeInsightCode.positiveReinforcement:
        return l10n.practiceInsightPositiveReinforcement;
      case PracticeInsightCode.nextDifficulty:
        return l10n.practiceInsightNextDifficulty;
      case PracticeRecommendationKind.retry:
        return l10n.practiceRecommendationRetry;
      case PracticeRecommendationKind.reduceTempo:
        return l10n.practiceRecommendationReduceTempo;
      case PracticeRecommendationKind.enableMetronome:
        return l10n.practiceRecommendationEnableMetronome;
      case PracticeRecommendationKind.focusDirection:
        return l10n.practiceRecommendationFocusDirection;
      case PracticeRecommendationKind.focusChordChanges:
        return l10n.practiceRecommendationFocusChordChanges;
      case PracticeRecommendationKind.nextDifficulty:
        return l10n.practiceRecommendationNextDifficulty;
    }
    // Unknown code: fall back to the humanised form so a future build
    // never renders an empty bullet.
    final tail = code.split('.').last;
    return tail.replaceAll('_', ' ');
  }
}

class _FactTile extends StatelessWidget {
  const _FactTile({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      trailing: Text(value, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

String _finishReasonLabel(AppLocalizations l10n, String code) {
  switch (code) {
    case 'completedAllTargets':
      return l10n.practiceSessionStatusCompleted;
    case 'userFinished':
      return l10n.practiceResultFinishUserFinished;
    case 'cancelled':
      return l10n.practiceSessionStatusCancelled;
    case 'timedOut':
      return l10n.practiceResultFinishTimedOut;
    case 'interrupted':
      return l10n.practiceResultFinishInterrupted;
    case 'failed':
      return l10n.practiceSessionStatusFailed;
  }
  return code;
}

String _durationLabel(Duration d) {
  final seconds = d.inSeconds;
  if (seconds < 60) return '${d.inSeconds}s';
  final minutes = seconds ~/ 60;
  final rest = seconds % 60;
  if (rest == 0) return '${minutes}m';
  return '${minutes}m ${rest}s';
}

/// Mode-keyed metric visibility (A1 — single source of truth).
class PracticeMetricKind {
  const PracticeMetricKind._(this._name);

  final String _name;

  static const overall = PracticeMetricKind._('overall');
  static const completion = PracticeMetricKind._('completion');
  static const rhythm = PracticeMetricKind._('rhythm');
  static const direction = PracticeMetricKind._('direction');
  static const chord = PracticeMetricKind._('chord');
  static const chordPair = PracticeMetricKind._('chordPair');

  bool isApplicableTo(PracticeMode mode) {
    return switch (this) {
      _ when identical(this, overall) => mode != PracticeMode.freePractice,
      _ when identical(this, completion) => mode != PracticeMode.freePractice,
      _ when identical(this, rhythm) => mode != PracticeMode.freePractice,
      _ when identical(this, direction) => switch (mode) {
        PracticeMode.strumPattern => true,
        PracticeMode.chordProgression => true,
        PracticeMode.chordChanges => false,
        PracticeMode.rhythmOnly => false,
        PracticeMode.freePractice => false,
      },
      _ when identical(this, chord) => switch (mode) {
        PracticeMode.strumPattern => false,
        PracticeMode.chordProgression => true,
        PracticeMode.chordChanges => true,
        PracticeMode.rhythmOnly => false,
        PracticeMode.freePractice => false,
      },
      _ when identical(this, chordPair) => mode == PracticeMode.chordChanges,
      _ => false,
    };
  }

  String label(AppLocalizations l10n) {
    return switch (this) {
      _ when identical(this, overall) => l10n.practiceResultOverall,
      _ when identical(this, completion) => l10n.practiceResultCompletion,
      _ when identical(this, rhythm) => l10n.practiceResultRhythm,
      _ when identical(this, direction) => l10n.practiceResultDirection,
      _ when identical(this, chord) => l10n.practiceResultChord,
      _ when identical(this, chordPair) => l10n.practiceResultChordPair,
      _ => _name,
    };
  }
}

/// Convenience used by the practice hub to land on this screen from a
/// navigation sink. Public, so the screen can be tested directly.
///
/// Built from design tokens directly rather than [SsEmptyState]: that
/// component mandates an `onAction` (§5.2), but this fallback never
/// navigated pre-migration (measured: `git show 0ba14f5b:…
/// practice_result_screen.dart` — the legacy `EmptyState` took no action at
/// all). Adding a `practiceHub` navigation here would be a behaviour change
/// in an appearance-only round (E15-R04 review MAJOR-3b) — this mirrors
/// [SpeedBuilderScreen]'s `_UnavailableLayout`, the same documented §5.2
/// exception used for [PracticeHubScreen]'s empty-catalog state.
class PracticeResultFallback extends StatelessWidget {
  const PracticeResultFallback({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.practiceResultTitle)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(SsSpacing.space6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bar_chart, color: colors.textSecondary, size: 40),
              const SizedBox(height: SsSpacing.space4),
              Text(
                l10n.practiceResultUnavailableTitle,
                style: typography.titleMedium.copyWith(
                  color: colors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: SsSpacing.space2),
              Text(
                l10n.practiceResultUnavailableBody,
                style: typography.bodyMedium.copyWith(
                  color: colors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
