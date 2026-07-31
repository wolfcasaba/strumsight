/// Central catalogue for every route path exposed by the application.
abstract final class AppRoutes {
  static const String welcome = '/welcome';
  static const String live = '/live';
  static const String analyze = '/analyze';
  static const String learn = '/learn';
  static const String library = '/library';
  static const String settings = '/settings';
  static const String tuner = '/tuner';
  static const String metronome = '/metronome';
  static const String calibrate = '/calibrate';
  static const String streak = '/streak';
  static const String progress = '/progress';
  static const String songs = '/songs';
  static const String setlists = '/setlists';
  static const String chords = '/chords';
  static const String login = '/login';
  static const String librarySession = '/library/session';
  static const String practiceHub = '/practice';
  static const String practiceSetup = '/practice/setup';
  static const String practiceSession = '/practice/session';

  /// Top-level destinations in the same order as the shell navigation bar.
  static const List<String> shellTabs = <String>[
    live,
    analyze,
    learn,
    library,
    settings,
  ];
}
