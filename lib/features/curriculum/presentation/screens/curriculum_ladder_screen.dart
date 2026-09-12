/// The course, made visible.
///
/// ## Why this screen had to exist before the pillar counted as delivered
///
/// The curriculum was built, measured and reachable only as a quick tool that
/// opened ONE rung with a default mission. Nothing outside the feature read
/// `Course`, `UnlockRule` or `missionAvailability` at all — so the ladder, the
/// gating and the step ordering existed in tests and nowhere a learner could see
/// them. A pillar the learner cannot find is not shipped.
///
/// ## What it claims, and what it deliberately does not
///
/// It renders each rung's availability from `missionAvailability` and never
/// re-decides it. Three states, with the design's honesty rules attached:
///
/// - **available** — open, and tapping it starts THAT mission, not a default.
/// - **lockedPendingSkill** — "not yet reached", never "failed": a mission cannot
///   fail (§2 rule 6). It also names the prerequisite skills, because "locked" on
///   its own tells the learner nothing they can act on.
/// - **unavailableCapability** — phrased as the DEVICE's limit, not the learner's,
///   and it names the missing capability, because "a microphone is needed for
///   this" is actionable where "unavailable" is not.
///
/// ## Progress, now that it is measured
///
/// Graded attempts are persisted as `SkillEvidence` and reduced to a
/// `SkillEstimate` on read (`curriculum_progress.dart`), so the estimate map is
/// real and a rung genuinely opens. What a rung shows about the learner is
/// therefore also real, and deliberately modest: the estimate's STATE in words
/// plus how many attempts it rests on. There is no percentage and no bar,
/// because the underlying level is a confidence-damped figure whose absolute
/// value would invite a precision it does not have — 0.625 after one perfect
/// attempt is the policy's caution, not a claim that the learner is 62.5% good.
/// The count is the honest part: it says what the verdict rests on.
///
/// A skill with no evidence shows NOTHING rather than a zero. Absence of
/// evidence is not a low score (§2 rule 1), and "0%" would read as one.
///
/// ## Why the estimate's STATE is not shown as a word, measured
///
/// The obvious line here would have been the state in plain language — "Steady",
/// "Solid". It is wrong, and `curriculum_progress_test.dart` is what showed it:
/// six attempts in which every stroke was confirmed travelling the WRONG way
/// reduce to `SkillEstimateState.stable` at level **0.000**. `stable` means the
/// evidence is consistent, not that the playing is good — so "Steady" would have
/// been praise for a learner who strummed everything backwards. The state
/// describes how much the app KNOWS; only `level` describes how well the learner
/// played, and the rung's own verdict above already carries that. So this line
/// reports the attempt COUNT, and the only state words kept are the two that are
/// genuinely about the evidence: it has aged, or the attempts disagreed.
///
/// **What is still not reachable, said plainly:** only rungs carrying a rhythm
/// assignment can be played here, so only those produce evidence.
/// `mission.dDuUdU` is gated on `chord.emToAm`, trained by a chord mission this
/// screen cannot open — so that rung cannot be earned yet however well the
/// learner plays. The chain that does work end to end is `mission.downQuarters`
/// then `mission.downUpEighths`.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/public.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../live/public.dart';
import '../../../practice_generator/public.dart'
    show ExerciseCapability, SkillEstimate, SkillEstimateState;
import '../../domain/course.dart';
import '../../domain/device_capabilities.dart';
import '../../domain/mission_availability.dart';
import '../../domain/next_step.dart';
import '../curriculum_names.dart';
import '../providers/curriculum_progress_providers.dart';
import 'rhythm_practice_screen.dart';

final class CurriculumLadderScreen extends ConsumerWidget {
  const CurriculumLadderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final course = ref.watch(curriculumCourseProvider);
    final live = ref.watch(liveFrameProvider).asData?.value;
    final capabilities = curriculumDeviceCapabilities(
      microphoneListening: live?.listening ?? false,
    );
    final estimates = ref.watch(curriculumEstimatesProvider);
    // The SAME answer the Today hub's primary button promises, from the same
    // function — otherwise "continue" would drop the learner onto a list of
    // fourteen rows with nothing marking the one they were just sent to.
    final nextStep = curriculumNextStep(course, estimates: estimates);
    // Numbered once, from the course's own order, so no row has to work out its
    // own position and two rows can never claim the same number.
    final rungNumbers = <String, int>{
      for (final (index, mission) in course.missionsInOrder.indexed)
        mission.missionId: index + 1,
    };

    return Scaffold(
      appBar: AppBar(title: Text(l10n.curriculumLadderTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(SsSpacing.space4),
          children: [
            // STAGE headers, not level headers. A level here usually holds one
            // mission, so its header repeated the row underneath it; the stage is
            // the division that actually groups several rungs together.
            for (final stage in course.stages) ...[
              Padding(
                padding: const EdgeInsets.only(
                  top: SsSpacing.space3,
                  bottom: SsSpacing.space2,
                ),
                child: Text(
                  curriculumStageName(l10n, stage.stageId),
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
              for (final level in stage.levels)
                for (final mission in level.missions)
                  _MissionRow(
                    mission: mission,
                    // One-based, in ladder order. The number is real information,
                    // not decoration: the order IS the teaching sequence (the
                    // course's own `validate()` refuses a gate that needs a skill
                    // trained later), so it tells the learner where they are.
                    rung: rungNumbers[mission.missionId]!,
                    // The domain decides; this screen only renders the verdict.
                    availability: missionAvailability(
                      mission,
                      estimates: estimates,
                      deviceCapabilities: capabilities,
                    ),
                    missing: missingCapabilitiesFor(mission, capabilities),
                    earned: _earnedFor(mission, estimates),
                    isNextStep: mission.missionId == nextStep?.missionId,
                  ),
            ],
          ],
        ),
      ),
    );
  }

  /// The estimate worth showing on [mission]'s row, or null when nothing about it
  /// has been measured.
  ///
  /// A mission trains one skill in the shipped course, but the type allows
  /// several. When there are several the LEAST confident one is shown: a rung is
  /// only as earned as its weakest part, and showing the strongest would let one
  /// solid skill hide a shaky one the same rung is responsible for.
  SkillEstimate? _earnedFor(
    CurriculumMission mission,
    Map<String, SkillEstimate> estimates,
  ) {
    SkillEstimate? weakest;
    for (final skillId in mission.trainedSkillIds) {
      final estimate = estimates[skillId];
      // `unknown` carries no level and means "never measured", not a low one.
      if (estimate == null || estimate.isUnknown) continue;
      if (weakest == null || estimate.uncertainty > weakest.uncertainty) {
        weakest = estimate;
      }
    }
    return weakest;
  }
}

final class _MissionRow extends StatelessWidget {
  const _MissionRow({
    required this.mission,
    required this.rung,
    required this.availability,
    required this.missing,
    required this.earned,
    required this.isNextStep,
  });

  final CurriculumMission mission;

  /// This rung's one-based position in the ladder.
  final int rung;
  final MissionAvailability availability;
  final Set<ExerciseCapability> missing;

  /// What has been MEASURED about this rung's skill, or null when nothing has.
  final SkillEstimate? earned;

  /// Whether this is the rung the course says to practise next.
  final bool isNextStep;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final text = Theme.of(context).textTheme;

    final (status, tone) = switch (availability) {
      MissionAvailability.available => (
        l10n.curriculumLadderOpen,
        colors.success,
      ),
      // Not a failure tone. A rung that has not opened is neutral, because the
      // learner has done nothing wrong by not having reached it yet.
      MissionAvailability.lockedPendingSkill => (
        l10n.curriculumLadderNotYet,
        colors.textSecondary,
      ),
      // The device's shortfall, so it reads as information, not as a warning
      // about the player.
      MissionAvailability.unavailableCapability => (
        l10n.curriculumLadderCannotMeasure,
        colors.textSecondary,
      ),
    };

    final detail = switch (availability) {
      MissionAvailability.lockedPendingSkill
          when mission.unlock.prerequisiteSkillIds.isNotEmpty =>
        l10n.curriculumLadderNeeds(
          // Named, then sorted BY NAME: sorting the ids first would order the
          // list by a code the learner cannot see, which looks arbitrary on
          // screen. Still deterministic, which is what the sort is for.
          (mission.unlock.prerequisiteSkillIds
                  .map((skillId) => curriculumSkillName(l10n, skillId))
                  .toList()
                ..sort())
              .join(', '),
        ),
      MissionAvailability.unavailableCapability when missing.isNotEmpty =>
        l10n.curriculumLadderMissing(
          (missing.map((c) => _capabilityName(l10n, c)).toList()..sort()).join(
            ', ',
          ),
        ),
      MissionAvailability.available when mission.rhythm == null =>
        l10n.curriculumLadderNoRhythm,
      _ => null,
    };

    // How much evidence stands behind this rung — a COUNT, never a quality
    // word. See the library doc for why the state's name cannot be used here.
    final earnedEstimate = earned;
    final evidence = earnedEstimate == null
        ? null
        : l10n.curriculumLadderEvidence(earnedEstimate.evidenceIds.length);
    // The two things the count alone cannot say, both about the EVIDENCE and
    // neither about the player: it has aged, or the attempts disagreed.
    final evidenceNote = switch (earnedEstimate?.state) {
      SkillEstimateState.stale => l10n.curriculumSkillStale,
      SkillEstimateState.conflicted => l10n.curriculumSkillConflicted,
      _ => null,
    };

    // Only a rhythm rung can be opened from here: it is the only kind this
    // screen has somewhere to send the learner. An available rung without one is
    // shown, and says so, rather than offering a tap that goes nowhere.
    final openable =
        availability == MissionAvailability.available && mission.rhythm != null;

    return Card(
      margin: const EdgeInsets.only(bottom: SsSpacing.space2),
      child: ListTile(
        title: Text(
          curriculumMissionName(l10n, mission.missionId),
          style: text.bodyMedium,
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isNextStep
                  ? '${l10n.curriculumLadderRung(rung)} · '
                        '${l10n.curriculumLadderNextStep}'
                  : l10n.curriculumLadderRung(rung),
              style: text.labelSmall?.copyWith(
                color: isNextStep ? colors.brand : colors.textSecondary,
              ),
            ),
            Text(status, style: text.labelMedium?.copyWith(color: tone)),
            if (detail != null)
              Text(
                detail,
                style: text.labelSmall?.copyWith(color: colors.textSecondary),
              ),
            if (evidence != null)
              Text(
                evidence,
                style: text.labelSmall?.copyWith(color: colors.textSecondary),
              ),
            if (evidenceNote != null)
              Text(
                evidenceNote,
                style: text.labelSmall?.copyWith(color: colors.textSecondary),
              ),
          ],
        ),
        trailing: openable ? const Icon(Icons.play_arrow) : null,
        enabled: openable,
        onTap: openable
            ? () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  // THAT mission, not the screen's default. Opening the ladder's
                  // third rung and being given the first would be the ladder
                  // lying about what it just offered.
                  builder: (_) => RhythmPracticeScreen(mission: mission),
                ),
              )
            : null,
      ),
    );
  }

  /// A capability named in words a learner can act on.
  ///
  /// The enum's own `code` is a persistence token, not a sentence, and putting it
  /// on screen would be showing internals where an instruction belongs.
  String _capabilityName(
    AppLocalizations l10n,
    ExerciseCapability capability,
  ) => switch (capability) {
    ExerciseCapability.requiresMicrophone =>
      l10n.curriculumCapabilityMicrophone,
    ExerciseCapability.requiresCamera => l10n.curriculumCapabilityCamera,
    ExerciseCapability.supportsDirectionScoring =>
      l10n.curriculumCapabilityDirection,
    ExerciseCapability.supportsChordScoring => l10n.curriculumCapabilityChord,
    ExerciseCapability.supportsPitchScoring => l10n.curriculumCapabilityPitch,
    ExerciseCapability.supportsTempo => l10n.curriculumCapabilityTempo,
    _ => l10n.curriculumCapabilityOther,
  };
}
