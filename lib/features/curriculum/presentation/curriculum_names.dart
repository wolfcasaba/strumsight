/// What to call a rung, a stage and a skill when a learner is reading.
///
/// ## Why this file exists
///
/// The ladder shipped showing `mission.downQuarters` as a row title and
/// `rhythm.downQuarters` after "Needs first:". Those are **persistence codes** —
/// deliberately stable, deliberately never translated, and deliberately never
/// renamed — and putting one on screen is showing internals where an instruction
/// belongs. The same mistake was already corrected once for capabilities
/// (`_capabilityName`, E18-R12); this file finishes the job for the content.
///
/// ## Why a map here rather than a field on the mission
///
/// `CurriculumMission` carries a `SuccessCriteria.description` already, and it
/// would have been one line to render that instead. It is the wrong source: those
/// strings live in `beginner_course.dart` as **English-only data**, so rendering
/// them would put untranslated English in front of a Hungarian learner, and the
/// l10n parity gate would never notice because nothing would be missing from the
/// arb files. Names a learner reads belong in the arb files with every other
/// piece of user-facing text.
///
/// ## The fallback is unreachable in shipped content, and that is enforced
///
/// An id with no name returns a neutral generic, never the id itself: a token on
/// screen is worse than a vague label, because a learner cannot tell a token from
/// a typo. That it stays unreachable is not a hope —
/// `test/features/curriculum/curriculum_names_test.dart` walks the shipped course
/// and fails if ANY mission, stage or referenced skill id falls through to it. So
/// adding a rung without naming it is a red test, not a leaked token.
library;

import '../../../l10n/app_localizations.dart';

/// The rung's name, as a learner would say it.
String curriculumMissionName(AppLocalizations l10n, String missionId) =>
    switch (missionId) {
      'mission.tuneAndSit' => l10n.curriculumMissionTuneAndSit,
      'mission.downQuarters' => l10n.curriculumMissionDownQuarters,
      'mission.eMinor' => l10n.curriculumMissionEMinor,
      'mission.aMinor' => l10n.curriculumMissionAMinor,
      'mission.emToAm' => l10n.curriculumMissionEmToAm,
      'mission.twoChordSong' => l10n.curriculumMissionTwoChordSong,
      'mission.downUpEighths' => l10n.curriculumMissionDownUpEighths,
      'mission.dDuUdU' => l10n.curriculumMissionDDuUdU,
      'mission.dMajor' => l10n.curriculumMissionDMajor,
      'mission.amToD' => l10n.curriculumMissionAmToD,
      'mission.gMajor' => l10n.curriculumMissionGMajor,
      'mission.dToG' => l10n.curriculumMissionDToG,
      'mission.cMajor' => l10n.curriculumMissionCMajor,
      'mission.gToC' => l10n.curriculumMissionGToC,
      _ => l10n.curriculumUnnamedStep,
    };

/// The stage's name. Stages are the two broad sections of the beginner course.
String curriculumStageName(AppLocalizations l10n, String stageId) =>
    switch (stageId) {
      'stage.firstSounds' => l10n.curriculumStageFirstSounds,
      'stage.rhythmAndReach' => l10n.curriculumStageRhythmAndReach,
      _ => l10n.curriculumUnnamedStep,
    };

/// The skill's name, phrased to read inside a sentence.
///
/// These are lower-case and written as things a learner HAS ("steady
/// down-strokes", "the Em to Am change") because that is where they appear: after
/// "Needs first:", listing what has to come before this rung. A title-case noun
/// would read as the name of a different screen.
String curriculumSkillName(AppLocalizations l10n, String skillId) =>
    switch (skillId) {
      'rhythm.downQuarters' => l10n.curriculumSkillDownQuarters,
      'rhythm.downUpEighths' => l10n.curriculumSkillDownUpEighths,
      'strumPattern.dDuUdU' => l10n.curriculumSkillStrumPattern,
      'chord.eMinor' => l10n.curriculumSkillChordEMinor,
      'chord.aMinor' => l10n.curriculumSkillChordAMinor,
      'chord.dMajor' => l10n.curriculumSkillChordDMajor,
      'chord.gMajor' => l10n.curriculumSkillChordGMajor,
      'chord.cMajor' => l10n.curriculumSkillChordCMajor,
      'chord.emToAm' => l10n.curriculumSkillChangeEmToAm,
      'chord.amToD' => l10n.curriculumSkillChangeAmToD,
      'chord.dToG' => l10n.curriculumSkillChangeDToG,
      'chord.gToC' => l10n.curriculumSkillChangeGToC,
      'songPerformance.twoChord' => l10n.curriculumSkillTwoChordSong,
      _ => l10n.curriculumUnnamedSkill,
    };
