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
/// **It does not show progress, because the app does not yet measure it.** Skill
/// estimates are not persisted anywhere: `missionAvailability` is handed an empty
/// map, so every gated rung reads as not-yet-reached and will keep doing so until
/// a round wires attempt outcomes into `SkillEstimate`. That is why this screen
/// is written as a MAP of the path with its requirements shown, rather than as a
/// progress tracker with a bar that could never fill. Nothing here says or
/// implies that an attempt advances anything.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/design_system/public.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../live/public.dart';
import '../../../practice_generator/public.dart' show ExerciseCapability;
import '../../data/beginner_course.dart';
import '../../domain/course.dart';
import '../../domain/device_capabilities.dart';
import '../../domain/mission_availability.dart';
import 'rhythm_practice_screen.dart';

final class CurriculumLadderScreen extends ConsumerWidget {
  const CurriculumLadderScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final course = beginnerCourse();
    final live = ref.watch(liveFrameProvider).asData?.value;
    final capabilities = curriculumDeviceCapabilities(
      microphoneListening: live?.listening ?? false,
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.curriculumLadderTitle)),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(SsSpacing.space4),
          children: [
            for (final stage in course.stages)
              for (final level in stage.levels) ...[
                Padding(
                  padding: const EdgeInsets.only(
                    top: SsSpacing.space3,
                    bottom: SsSpacing.space2,
                  ),
                  child: Text(
                    level.levelId,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                for (final mission in level.missions)
                  _MissionRow(
                    mission: mission,
                    // The domain decides; this screen only renders the verdict.
                    // An empty estimate map is the true state of a learner whose
                    // skills have never been measured.
                    availability: missionAvailability(
                      mission,
                      estimates: const {},
                      deviceCapabilities: capabilities,
                    ),
                    missing: missingCapabilitiesFor(mission, capabilities),
                  ),
              ],
          ],
        ),
      ),
    );
  }
}

final class _MissionRow extends StatelessWidget {
  const _MissionRow({
    required this.mission,
    required this.availability,
    required this.missing,
  });

  final CurriculumMission mission;
  final MissionAvailability availability;
  final Set<ExerciseCapability> missing;

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
          (mission.unlock.prerequisiteSkillIds.toList()..sort()).join(', '),
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

    // Only a rhythm rung can be opened from here: it is the only kind this
    // screen has somewhere to send the learner. An available rung without one is
    // shown, and says so, rather than offering a tap that goes nowhere.
    final openable =
        availability == MissionAvailability.available && mission.rhythm != null;

    return Card(
      margin: const EdgeInsets.only(bottom: SsSpacing.space2),
      child: ListTile(
        title: Text(mission.missionId, style: text.bodyMedium),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(status, style: text.labelMedium?.copyWith(color: tone)),
            if (detail != null)
              Text(
                detail,
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
