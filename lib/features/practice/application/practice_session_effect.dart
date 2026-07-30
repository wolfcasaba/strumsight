import '../../../../core/foundation/app_failure.dart';

/// One-shot output produced by the practice-session reducer.
///
/// Effects are *not* stored on the state — they are returned alongside the
/// new state in [PracticeSessionTransition.effects]. The UI-side runner is
/// expected to fire each effect exactly once and never re-emit on replay.
sealed class PracticeSessionEffect {
  const PracticeSessionEffect();
}

/// Emit a short haptic pulse. Used for accepted `RestartAttempt`.
final class PlayHaptic extends PracticeSessionEffect {
  const PlayHaptic();
}

/// One click of the count-in metronome, at the given zero-based beat index
/// of the current count-in span.
final class PlayCountInClick extends PracticeSessionEffect {
  const PlayCountInClick(this.beatIndex);

  /// Zero-based beat index within the count-in span. For an initial count-in
  /// of `countInBars` bars at `meter.beatsPerBar`, this is in
  /// `[0, countInBars * meter.beatsPerBar)`. For a resume count-in it is
  /// in `[0, meter.beatsPerBar)`.
  final int beatIndex;
}

/// Open the OS settings page so the user can grant the missing permission.
final class ShowPermissionSettings extends PracticeSessionEffect {
  const ShowPermissionSettings();
}

/// Navigate to the post-session result screen. Emitted on `finishing →
/// completed`.
final class NavigateToResult extends PracticeSessionEffect {
  const NavigateToResult();
}

/// Surface a recoverable failure (localised message via the failure code).
final class ShowRecoverableError extends PracticeSessionEffect {
  const ShowRecoverableError(this.failure);

  final AppFailure failure;
}

/// Reserved for a future UI accessibility round (E02-R13+). Declared now so
/// the sealed switch is exhaustive; no effect of this kind is emitted by
/// this round's reducer.
final class AnnounceAccessibilityFeedback extends PracticeSessionEffect {
  const AnnounceAccessibilityFeedback(this.messageKey);

  final String messageKey;
}
