/// Compile-time release metadata (ADR 0447 D7).
///
/// [BuildInfo] is a `const`-constructible value class built purely from
/// `String.fromEnvironment` / `int.fromEnvironment` — reading it has no
/// runtime side effect and never touches the filesystem or network. A
/// release build supplies the real values via `--dart-define`
/// (`STRUMSIGHT_BUILD_VERSION`, `STRUMSIGHT_BUILD_NUMBER`,
/// `STRUMSIGHT_BUILD_SHORT_SHA`, `STRUMSIGHT_BUILD_CHANNEL`); omitting any
/// of them is not an error — the documented default below applies, and
/// `test/tooling/release_manifest_test.dart` pins those defaults. Neither
/// `main` nor `lib/app/bootstrap/**` reference this class — surfacing it in
/// the UI is a later round's work.
final class BuildInfo {
  const BuildInfo({
    this.version = const String.fromEnvironment(
      'STRUMSIGHT_BUILD_VERSION',
      defaultValue: defaultVersion,
    ),
    this.buildNumber = const int.fromEnvironment(
      'STRUMSIGHT_BUILD_NUMBER',
      defaultValue: defaultBuildNumber,
    ),
    this.shortSha = const String.fromEnvironment(
      'STRUMSIGHT_BUILD_SHORT_SHA',
      defaultValue: defaultShortSha,
    ),
    this.channel = const String.fromEnvironment(
      'STRUMSIGHT_BUILD_CHANNEL',
      defaultValue: defaultChannel,
    ),
  });

  /// Applies when `--dart-define=STRUMSIGHT_BUILD_VERSION=...` is absent.
  static const String defaultVersion = '0.0.0-dev';

  /// Applies when `--dart-define=STRUMSIGHT_BUILD_NUMBER=...` is absent.
  static const int defaultBuildNumber = 0;

  /// Applies when `--dart-define=STRUMSIGHT_BUILD_SHORT_SHA=...` is absent.
  static const String defaultShortSha = 'unknown';

  /// Applies when `--dart-define=STRUMSIGHT_BUILD_CHANNEL=...` is absent.
  static const String defaultChannel = 'dev';

  final String version;
  final int buildNumber;
  final String shortSha;
  final String channel;
}
