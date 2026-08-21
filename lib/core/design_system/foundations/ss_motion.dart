/// Pinned motion durations and reduced-motion fallback verified by tests.
abstract final class SsMotion {
  static const Duration instant = Duration(milliseconds: 80);
  static const Duration fast = Duration(milliseconds: 120);
  static const Duration standard = Duration(milliseconds: 200);
  static const Duration emphasized = Duration(milliseconds: 300);
  static const Duration celebration = Duration(milliseconds: 700);

  static const List<Duration> durations = [
    instant,
    fast,
    standard,
    emphasized,
    celebration,
  ];

  static Duration forReducedMotion(bool reducedMotion) =>
      reducedMotion ? Duration.zero : standard;
}
