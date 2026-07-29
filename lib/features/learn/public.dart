/// Public lesson contract for other features (SDD Ch2 §10.4).
library;

/// Lesson, lesson events and the lesson-from-analysis builders.
export 'model/lesson.dart';

/// The play-along screen every entry point (Songs, Library, Onboarding,
/// Streak, Analyze) navigates to.
export 'screens/learn_screen.dart';

/// Pure beat→pixel/count-in maths. It stays in Learn rather than core/music
/// because it is defined in terms of [Lesson] events, not general music
/// theory — Share's strum reel reuses it through this boundary.
export 'lesson_timing.dart';

/// The play-along highway widget (reused by the strum reel).
export 'widgets/lesson_highway.dart';

/// Audio playback used by the tuner reference tone, the chord library preview
/// and the reel: backing tracks, chord pads and the metronome click.
export 'providers/backing_provider.dart';
export 'audio/chord_audio.dart';
export 'audio/metronome.dart';
