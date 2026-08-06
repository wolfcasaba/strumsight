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
  static const String practiceResult = '/practice/result';
  static const String songTrainerLibrary = '/song-trainer';
  static const String songTrainerImport = '/song-trainer/import';
  static const String songTrainerNewEditor = '/song-trainer/editor/new';
  static const String songTrainerEditor = '/song-trainer/editor/:songId';
  static const String songTrainerOverview = '/song-trainer/overview/:songId';
  static const String songTrainerSetup = '/song-trainer/setup/:songId';
  static const String songTrainerSession = '/song-trainer/session/:songId';
  static const String songTrainerResult = '/song-trainer/result/:songId';
  static const String tutorHome = '/tutor/home';
  static const String tutorChat = '/tutor/chat';
  static const String tutorProfile = '/tutor/profile';
  static const String tutorPrivacy = '/tutor/privacy';
  static const String tutorData = '/tutor/data';

  /// Top-level destinations in the same order as the shell navigation bar.
  static const List<String> shellTabs = <String>[
    live,
    analyze,
    learn,
    library,
    settings,
  ];
}
