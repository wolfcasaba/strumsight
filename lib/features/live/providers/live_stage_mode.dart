import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The Live stage's PRODUCT mode (E14-R37, ADR 0550 D2).
///
/// Deliberately a different type from `RecognitionMode` (ADR 0544 D1), which
/// is the ENGINE's construction-time regime. The two answer different
/// questions and must not be conflated:
///
/// * `RecognitionMode` — may an expected-chord hint influence the DECODER?
/// * [LiveStageMode] — is the SCREEN showing the player a target right now?
///
/// A guided stage on a free engine is a legitimate, honest configuration: the
/// player sees what to play, and the verdict stays audio-only. That is the
/// configuration this round ships (ADR 0550 D4) — the reverse (a guided
/// engine behind a free-looking screen) is the one that must never exist,
/// and `ExpectedChordHint.forMode` makes it unrepresentable.
enum LiveStageMode {
  /// Nothing is being asked of the player; the stage mirrors what it hears.
  freePlay,

  /// A lesson/song target is on screen. The target is rendered as a target
  /// (`GuidedTargetCard`), never in the detection hero.
  guided,
}

/// The chord the Live stage is currently ASKING for, or `null` in free play.
///
/// The only writer is an explicit hand-off (a lesson, a song section, a
/// practice step). Nothing derives it from the detector's own output — a
/// target inferred from a detection would be a circular claim.
class LiveGuidedTargetController extends Notifier<String?> {
  @override
  String? build() => null;

  /// Sets the on-screen target, or clears it with `null`/an empty label.
  void set(String? chordLabel) {
    state = (chordLabel == null || chordLabel.isEmpty) ? null : chordLabel;
  }

  /// Leaves guided mode.
  void clear() => state = null;
}

/// The Live stage's guided target (`null` = free play).
final liveGuidedTargetProvider =
    NotifierProvider<LiveGuidedTargetController, String?>(
      LiveGuidedTargetController.new,
    );

/// The stage mode, DERIVED from the target so the two can never disagree —
/// there is exactly one source of truth for "are we guided?".
final liveStageModeProvider = Provider<LiveStageMode>(
  (ref) => ref.watch(liveGuidedTargetProvider) == null
      ? LiveStageMode.freePlay
      : LiveStageMode.guided,
);
