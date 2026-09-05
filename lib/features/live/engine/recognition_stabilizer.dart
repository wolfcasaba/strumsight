import '../../../core/music/strum.dart';
import '../domain/recognition/recognition_decision.dart';
import '../model/live_frame.dart';

/// Tuning for [RecognitionStabilizer] (ADR 0518 D4) — a design choice, not a
/// calibration: Free favours lower latency, Guided trades latency for a
/// steadier label against a lesson target the UI won't second-guess.
enum StabilizerProfile {
  free(minAgreeFrames: 3),
  guided(minAgreeFrames: 5);

  const StabilizerProfile({required this.minAgreeFrames});

  /// Consecutive, already-decided frames the incoming label must agree on
  /// before the label is confirmed (ADR 0518 D3, inclusive boundary).
  final int minAgreeFrames;
}

/// Gates an already-decided [LiveFrame] stream so the Live chord timeline
/// records only a stable label change, not every frame-level flicker
/// (ADR 0518).
///
/// This is NOT a second confirmation gate over the pipeline's own chord
/// decision (ADR 0516): it never re-derives presence, tonalness, or signal
/// quality. Its input is a frame the pipeline already decided
/// (`frame.current != null`); its only question is how many consecutive
/// such frames agree on the same label. [stabilize] therefore only passes a
/// frame through or drops it — it never rewrites one, since `LiveFrame`'s
/// `copyWith` cannot clear a nullable field and the model file is out of
/// this round's scope.
class RecognitionStabilizer {
  RecognitionStabilizer({this.profile = StabilizerProfile.free});

  final StabilizerProfile profile;

  RecognitionDecision _chordState = RecognitionDecision.candidate;
  String? _pendingLabel;
  int _agreeFrames = 0;
  String? _confirmedLabel;
  int _pendingFirstFrame = 0;
  int _framesProcessed = 0;
  int _confirmedFlips = 0;
  int _confirmationLatencyFrames = 0;

  int? _acceptedStrumSeq;
  StrumDirection? _acceptedStrumDirection;

  /// Label-stability state: `candidate` before any decided frame has ever
  /// been seen, `provisional` while the current run is still under the
  /// profile's agreement threshold, `confirmed` at or above it (ADR 0518 D1).
  RecognitionDecision get chordState => _chordState;

  /// Frames elapsed from the last confirmed label's first appearance in its
  /// current run to its confirmation — includes any interleaved idle frames,
  /// not just the profile's `minAgreeFrames` (ADR 0518 D8).
  int get confirmationLatencyFrames => _confirmationLatencyFrames;

  /// Confirmed label changes divided by frames processed, `0..1` (ADR 0518 D8).
  double get flipRate =>
      _framesProcessed == 0 ? 0 : _confirmedFlips / _framesProcessed;

  /// Returns [frame] when it should reach the timeline, `null` when it
  /// should be dropped.
  LiveFrame? stabilize(LiveFrame frame) {
    _framesProcessed++;

    if (!_admitStrum(frame)) return null;

    final current = frame.current;
    if (current == null) return frame;

    if (current.label == _pendingLabel) {
      _agreeFrames++;
    } else {
      _pendingLabel = current.label;
      _agreeFrames = 1;
      _pendingFirstFrame = _framesProcessed;
    }

    if (_agreeFrames < profile.minAgreeFrames) {
      _chordState = RecognitionDecision.provisional;
      return null;
    }

    if (_confirmedLabel != current.label) {
      _confirmedFlips++;
      _confirmationLatencyFrames = _framesProcessed - _pendingFirstFrame + 1;
      _confirmedLabel = current.label;
    }
    _chordState = RecognitionDecision.confirmed;
    return frame;
  }

  /// ADR 0518 D7 — an accepted strum event's direction is immutable, keyed by
  /// `LiveFrame.strumSeq`: the same seq later proposing a different direction
  /// is refused (its frame is dropped, never rewritten); a new seq is a fresh
  /// event and is admitted.
  bool _admitStrum(LiveFrame frame) {
    final strum = frame.latestStrum;
    if (strum == null) return true;
    if (_acceptedStrumSeq == frame.strumSeq) {
      return strum.direction == _acceptedStrumDirection;
    }
    _acceptedStrumSeq = frame.strumSeq;
    _acceptedStrumDirection = strum.direction;
    return true;
  }
}
