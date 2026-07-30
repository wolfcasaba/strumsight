/// Shared ARB-key / ID / source-reference constants for the legacy practice
/// adapters (Lesson, Song, Analyze, Daily Challenge).
///
/// The four adapters all read their keys from here so a new entry, rename or
/// addition touches exactly one place. The adapter tests pin against these
/// constants directly — duplicating a literal in the adapter bodies is a
/// review-blocker.
library;

abstract final class PracticeAdapterKeys {
  // --- Lesson -------------------------------------------------------------
  static const String lessonTitleKey = 'practiceSourceLessonTitle';
  static const String lessonDescriptionKey = 'practiceSourceLessonDescription';
  static const String lessonIdPrefix = 'lesson.';
  static const String lessonEasySuffix = '.easy.v1';
  static const String lessonVersionSuffix = '.v1';
  static const String lessonSourcePrefix = 'lesson:';
  static const List<String> lessonSkillTags = ['lessonImport'];
  static const List<String> lessonEasySkillTags = [
    'lessonImport',
    'easyVariation',
  ];

  // --- Song ---------------------------------------------------------------
  static const String songTitleKey = 'practiceSourceSongTitle';
  static const String songDescriptionKey = 'practiceSourceSongDescription';
  static const String songIdPrefix = 'song.';
  static const String songVersionSuffix = '.v1';
  static const String songSourcePrefix = 'song:';
  static const List<String> songSkillTags = ['songImport'];

  // --- Analyze ------------------------------------------------------------
  static const String analyzeTitleKey = 'practiceSourceAnalyzeTitle';
  static const String analyzeDescriptionKey =
      'practiceSourceAnalyzeDescription';
  static const String analyzeIdPrefix = 'analyze.';
  static const String analyzeVersionSuffix = '.v1';
  static const String analyzeSourcePrefix = 'analyze:';
  static const List<String> analyzeSkillTags = ['analyzeImport'];
  static const double analyzeFallbackBpm = 90.0;
  static const double analyzeMinimumBpm = 30.0;
  static const double analyzeMaximumBpm = 300.0;

  // --- Daily Challenge ----------------------------------------------------
  static const String dailyChallengeTitleKey =
      'practiceSourceDailyChallengeTitle';
  static const String dailyChallengeDescriptionKey =
      'practiceSourceDailyChallengeDescription';
  static const String dailyChallengeIdPrefix = 'dailyChallenge.';
  static const String dailyChallengeVersionSuffix = '.v1';
  static const String dailyChallengeSourcePrefix = 'dailyChallenge:';
  static const List<String> dailyChallengeSkillTags = ['dailyChallenge'];
  static const int dailyChallengeMaxSlots = 8;
  static const int dailyChallengeBeatsPerBar = 4;
  static const double dailyChallengeDefaultBpm = 80.0;
}
