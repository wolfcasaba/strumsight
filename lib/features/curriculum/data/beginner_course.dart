/// The shipped beginner course.
///
/// Design: `docs/superpowers/specs/2026-09-11-gamified-curriculum-design.md` §1.
/// This is DATA. It says what to practise and when the next rung opens; the
/// existing adaptive generator produces the actual exercise from the learner's
/// own evidence, so there is no exercise content here.
///
/// ## Why this order
///
/// Researched, and the research changed it twice. Sources and the disagreements
/// between them are in the design doc §1.1; the short version:
///
/// - **Em first, then Am.** Em is two fingers with all six strings ringing, the
///   easiest shape there is, and Em→Am is among the easiest CHANGES — which
///   matters more, because every source agrees the change is the hard part, not
///   the shape. This is contested: JustinGuitar, the largest structured beginner
///   course, starts D-A-E and defers minors to its module 3, and Musicademy
///   rejects the whole bedrock-chord opening in favour of G/Em7/Cadd9. Em-first
///   is supported by the National Guitar Academy and Guitar Noise, it is the
///   easiest physical start, and it agrees with the three built-in lessons this
///   app already ships (`Lessons.all` opens on Em/G), so the app teaches ONE
///   order rather than two. That last point decided it.
/// - **A playable two-chord song at rung 5**, not at the end. Withholding real
///   music until the whole chord set is learned is a documented attrition risk:
///   JustinGuitar has a two-chord song in module 1, and Tom Hess's
///   teacher-training material argues explicitly against strict "master one
///   skill before the next" sequencing.
/// - **"Keep the strumming hand moving" belongs to the FIRST change** (rung 4),
///   not a later milestone. Three independent teaching sources treat it as a
///   rule applied from the very first chord change. It is also the one thing
///   here a chord-only recogniser cannot check and this app can.
/// - **Right-hand rhythm runs in parallel from rung 2.** Isolating the strumming
///   hand on muted strings is uniformly recommended and no source objects; it
///   also removes the confound, since with no chord to get right a direction
///   error cannot be mistaken for a fingering error.
/// - **C and G last**, which most sources support as the harder shapes.
///
/// ## Why there is no simplified stepping-stone chord
///
/// Sources that dislike delaying C and G reach for simplified voicings instead —
/// Cmaj7 for C, the two-finger G6 for G. MEASURED through the real
/// `LivePipeline`, neither can be scored honestly:
///
/// - **G6 is not in the recogniser's vocabulary at all** (`chord_dictionary.dart`
///   has maj, min, 7, maj7, m7, sus4, dim, aug — no 6), so the two-finger shape
///   reads as `G`. The app would be scoring a label it cannot distinguish.
/// - **Cmaj7 does not reliably confirm**: on a clean three-second voicing it sat
///   below the presence gate for 24 of 32 frames, against 3 for plain C. That is
///   the documented maj7 Occam handicap doing its job — maj7 must be CLEARLY
///   present or phantom overtone energy would rename every triad — and plain C
///   sits right next door taking the margin (RAG chunk 012).
///
/// So the course scores **major and minor triads only**, and a simplified shape
/// can be shown as an unscored hint but never set as a mission target. A
/// learner must never play something correctly and be told nothing happened.
///
/// ## Skill ids
///
/// These follow the vocabulary already shipped in
/// `practice_generator/data/adapter/legacy_mapping_table.dart`
/// (`chord.gMajor`, `chord.cMajor`, `chord.dMajor`, `chord.gToC`) rather than a
/// parallel scheme. Four of the ids below are exactly those.
library;

import '../../practice_generator/public.dart';
import '../domain/course.dart';
import '../domain/unlock_rule.dart';

/// Skill ids this course trains, named once so nothing can typo them apart.
abstract final class BeginnerSkills {
  static const rhythmDownQuarters = 'rhythm.downQuarters';
  static const rhythmDownUpEighths = 'rhythm.downUpEighths';
  static const strumPattern = 'strumPattern.dDuUdU';
  static const chordEMinor = 'chord.eMinor';
  static const chordAMinor = 'chord.aMinor';
  static const chordDMajor = 'chord.dMajor';
  static const chordGMajor = 'chord.gMajor';
  static const chordCMajor = 'chord.cMajor';
  static const changeEmToAm = 'chord.emToAm';
  static const changeAmToD = 'chord.amToD';
  static const changeDToG = 'chord.dToG';
  static const changeGToC = 'chord.gToC';
  static const twoChordSong = 'songPerformance.twoChord';
}

const _micDirection = <ExerciseCapability>{
  ExerciseCapability.requiresMicrophone,
  ExerciseCapability.supportsDirectionScoring,
  ExerciseCapability.supportsOffline,
};

const _micChord = <ExerciseCapability>{
  ExerciseCapability.requiresMicrophone,
  ExerciseCapability.supportsChordScoring,
  ExerciseCapability.supportsOffline,
};

const _micChordDirection = <ExerciseCapability>{
  ExerciseCapability.requiresMicrophone,
  ExerciseCapability.supportsChordScoring,
  ExerciseCapability.supportsDirectionScoring,
  ExerciseCapability.supportsOffline,
};

UnlockRule _after(Set<String> skills) => UnlockRule.skillConfidence(
  prerequisiteSkillIds: skills,
  minimumState: SkillEstimateState.emerging,
  minimumLevel: 0.6,
);

CurriculumMission _scored({
  required String id,
  required PracticeGoalType goal,
  required Set<String> trains,
  required UnlockRule unlock,
  required String description,
  required Set<ExerciseCapability> capabilities,
  double minimumAccuracy = 0.7,
}) => CurriculumMission(
  missionId: id,
  goalType: goal,
  trainedSkillIds: trains,
  unlock: unlock,
  successCriteria: SuccessCriteria(
    kind: SuccessCriterionKind.accuracyThreshold,
    description: description,
    requiredCapabilities: capabilities,
    minimumAccuracy: minimumAccuracy,
  ),
  isOutcomeMeasured: true,
);

CurriculumLevel _level({
  required String id,
  required PracticeGoalType goal,
  required List<CurriculumMission> missions,
}) => CurriculumLevel(levelId: id, goalType: goal, missions: missions);

/// The first stage of the shipped beginner course.
Course beginnerCourse() => Course(
  courseId: 'course.beginner',
  version: 1,
  stages: [
    CurriculumStage(
      stageId: 'stage.firstSounds',
      levels: [
        // 1 — setup. Measured by nothing, and says so (design §2 rule 7).
        _level(
          id: 'level.setup',
          goal: PracticeGoalType.technique,
          missions: [
            CurriculumMission(
              missionId: 'mission.tuneAndSit',
              goalType: PracticeGoalType.technique,
              trainedSkillIds: const {},
              unlock: UnlockRule.always,
              successCriteria: SuccessCriteria(
                kind: SuccessCriterionKind.completion,
                description: 'tune the guitar and settle into playing position',
                requiredCapabilities: const [
                  ExerciseCapability.supportsOffline,
                ],
              ),
              isOutcomeMeasured: false,
            ),
          ],
        ),

        // 2 — the right hand alone, on muted strings. No chord to get wrong, so
        // a direction error cannot be confused with a fingering error.
        _level(
          id: 'level.downQuarters',
          goal: PracticeGoalType.rhythm,
          missions: [
            _scored(
              id: 'mission.downQuarters',
              goal: PracticeGoalType.rhythm,
              trains: const {BeginnerSkills.rhythmDownQuarters},
              unlock: UnlockRule.always,
              description:
                  'damp the strings and play steady down-strokes on every beat',
              capabilities: _micDirection,
            ),
          ],
        ),

        // 3 — the first shape, one strum per chord. No pattern yet: every source
        // agrees a rhythm pattern comes after the shape is findable.
        _level(
          id: 'level.firstShape',
          goal: PracticeGoalType.chordChanges,
          missions: [
            _scored(
              id: 'mission.eMinor',
              goal: PracticeGoalType.chordChanges,
              trains: const {BeginnerSkills.chordEMinor},
              unlock: _after(const {BeginnerSkills.rhythmDownQuarters}),
              description:
                  'play E minor, one strum at a time, every string '
                  'ringing',
              capabilities: _micChord,
            ),
          ],
        ),

        // 4 — the first CHANGE, which is the hard part, and the rung where
        // "keep the strumming hand moving" is taught.
        _level(
          id: 'level.firstChange',
          goal: PracticeGoalType.chordChanges,
          missions: [
            _scored(
              id: 'mission.aMinor',
              goal: PracticeGoalType.chordChanges,
              trains: const {BeginnerSkills.chordAMinor},
              unlock: _after(const {BeginnerSkills.chordEMinor}),
              description: 'play A minor cleanly',
              capabilities: _micChord,
            ),
            _scored(
              id: 'mission.emToAm',
              goal: PracticeGoalType.chordChanges,
              trains: const {BeginnerSkills.changeEmToAm},
              unlock: _after(const {BeginnerSkills.chordAMinor}),
              description:
                  'change between E minor and A minor WITHOUT stopping '
                  'the strumming hand',
              capabilities: _micChordDirection,
            ),
          ],
        ),

        // 5 — music, early. Withholding a real song until the end is a measured
        // attrition risk, so the song arrives as soon as two chords exist.
        _level(
          id: 'level.firstSong',
          goal: PracticeGoalType.songPerformance,
          missions: [
            _scored(
              id: 'mission.twoChordSong',
              goal: PracticeGoalType.songPerformance,
              trains: const {BeginnerSkills.twoChordSong},
              unlock: _after(const {BeginnerSkills.changeEmToAm}),
              description: 'play a two-chord song all the way through',
              capabilities: _micChordDirection,
              minimumAccuracy: 0.6,
            ),
          ],
        ),
      ],
    ),

    CurriculumStage(
      stageId: 'stage.rhythmAndReach',
      levels: [
        // 6 — up-strokes, still isolated on muted strings.
        _level(
          id: 'level.downUpEighths',
          goal: PracticeGoalType.rhythm,
          missions: [
            _scored(
              id: 'mission.downUpEighths',
              goal: PracticeGoalType.rhythm,
              trains: const {BeginnerSkills.rhythmDownUpEighths},
              unlock: _after(const {BeginnerSkills.rhythmDownQuarters}),
              description: 'damped down-up eighths, even and relaxed',
              capabilities: _micDirection,
            ),
          ],
        ),

        // 7 — the pattern, on the two chords already known rather than gated
        // behind the whole chord set.
        _level(
          id: 'level.firstPattern',
          goal: PracticeGoalType.strummingPattern,
          missions: [
            _scored(
              id: 'mission.dDuUdU',
              goal: PracticeGoalType.strummingPattern,
              trains: const {BeginnerSkills.strumPattern},
              unlock: _after(const {
                BeginnerSkills.rhythmDownUpEighths,
                BeginnerSkills.changeEmToAm,
              }),
              description: 'down, down-up, up-down-up over E minor and A minor',
              capabilities: _micChordDirection,
            ),
          ],
        ),

        // 8-10 — the remaining open chords, hardest last.
        _level(
          id: 'level.dMajor',
          goal: PracticeGoalType.chordChanges,
          missions: [
            _scored(
              id: 'mission.dMajor',
              goal: PracticeGoalType.chordChanges,
              trains: const {BeginnerSkills.chordDMajor},
              unlock: _after(const {BeginnerSkills.changeEmToAm}),
              description: 'play D major with the top three strings clean',
              capabilities: _micChord,
            ),
            _scored(
              id: 'mission.amToD',
              goal: PracticeGoalType.chordChanges,
              trains: const {BeginnerSkills.changeAmToD},
              unlock: _after(const {BeginnerSkills.chordDMajor}),
              description: 'change A minor to D without stopping the strum',
              capabilities: _micChordDirection,
            ),
          ],
        ),
        _level(
          id: 'level.gMajor',
          goal: PracticeGoalType.chordChanges,
          missions: [
            _scored(
              id: 'mission.gMajor',
              goal: PracticeGoalType.chordChanges,
              trains: const {BeginnerSkills.chordGMajor},
              unlock: _after(const {BeginnerSkills.chordDMajor}),
              description: 'play G major, reaching without squeezing',
              capabilities: _micChord,
            ),
            _scored(
              id: 'mission.dToG',
              goal: PracticeGoalType.chordChanges,
              trains: const {BeginnerSkills.changeDToG},
              unlock: _after(const {BeginnerSkills.chordGMajor}),
              description: 'change D to G without stopping the strum',
              capabilities: _micChordDirection,
            ),
          ],
        ),
        _level(
          id: 'level.cMajor',
          goal: PracticeGoalType.chordChanges,
          missions: [
            _scored(
              id: 'mission.cMajor',
              goal: PracticeGoalType.chordChanges,
              trains: const {BeginnerSkills.chordCMajor},
              unlock: _after(const {BeginnerSkills.chordGMajor}),
              description: 'play C major across three frets',
              capabilities: _micChord,
            ),
            _scored(
              id: 'mission.gToC',
              goal: PracticeGoalType.chordChanges,
              trains: const {BeginnerSkills.changeGToC},
              unlock: _after(const {BeginnerSkills.chordCMajor}),
              description: 'change G to C without stopping the strum',
              capabilities: _micChordDirection,
            ),
          ],
        ),
      ],
    ),
  ],
);

/// The chords the course SCORES, in the order they are introduced.
///
/// Exposed so a test can check every one against the recogniser's vocabulary —
/// the course must never set a target the engine cannot name (see the
/// stepping-stone note above).
const List<String> beginnerScoredChords = <String>['Em', 'Am', 'D', 'G', 'C'];
