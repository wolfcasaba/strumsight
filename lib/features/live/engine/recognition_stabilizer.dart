import '../../../core/music/strum.dart';
import '../domain/recognition/recognition_decision.dart';
import '../model/live_frame.dart';
import 'dsp/dsp_config.dart';

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

  /// How long after a detected strum onset a confirmed chord label may still
  /// be displaced (E14-R28, ADR 0545 D2). **Derived, never tuned** — it is the
  /// sum of two constants that already existed in the tree:
  ///
  /// * [DspConfig.chordOnsetBoostSeconds] (`2 × 4096 / 44 100 ≈ 0.186 s`) —
  ///   the window in which the chord DECODER itself relaxes its switch penalty
  ///   after an onset (chunk 016 rec #2, round 138). Outside it the decoder is
  ///   already biased against changing chord, so a label change arriving later
  ///   is by construction not "on the strum".
  /// * [minAgreeFrames] × [DspConfig.frameEmitSeconds] (`0.066 s`) — the time
  ///   THIS gate needs to accumulate its own agreement evidence (ADR 0518 D3)
  ///   before it could confirm anything at all. Without this term the window
  ///   would close before the displacement it is supposed to admit.
  ///
  /// Free: `0.186 + 3 × 0.066 = 0.384 s`. Guided: `0.186 + 5 × 0.066 =
  /// 0.516 s` — guided is longer for the same reason its agreement threshold
  /// is higher, not because a second knob was tuned.
  double get onsetAlignmentWindowSec =>
      DspConfig.chordOnsetBoostSeconds +
      minAgreeFrames * DspConfig.frameEmitSeconds;
}

/// Gates an already-decided [LiveFrame] stream so the Live chord timeline
/// records only a stable label change, not every frame-level flicker
/// (ADR 0518).
///
/// This is NOT a second confirmation gate over the pipeline's own chord
/// decision (ADR 0516): it never re-derives presence, tonalness, or signal
/// quality. Its input is a frame the pipeline already decided
/// (`frame.current != null`). The very first label ever seen has no
/// established baseline to disagree with, so it confirms immediately; every
/// later, DIFFERENT label must sustain `profile.minAgreeFrames` consecutive
/// agreeing frames before it can displace the established one — this is
/// what turns A→B→A frame-level flicker into a single stable card instead
/// of three.
///
/// **E14-R28 (ADR 0545 D2) adds ONE further condition on displacement:** a
/// challenger that has met the agreement threshold is confirmed only on an
/// **onset-aligned** frame — a chord may change at or after a strum onset,
/// inside [StabilizerProfile.onsetAlignmentWindowSec]. This is a HYBRID of
/// the two mechanisms that already existed, not a third one: the agreement
/// counter says *what* the new label is, the onset says *when* a chord is
/// allowed to change (the same premise the decoder's onset boost is built on,
/// chunk 016 rec #2). Nothing about the counter, the cold-start exception or
/// the strum-immutability rule changed, and frames without a sample clock
/// (mocks, hand-built test frames) are unaffected — see [_isOnsetAligned].
///
/// [stabilize] therefore only passes a frame through or drops it —
/// it never rewrites one, since `LiveFrame`'s `copyWith` cannot clear a
/// nullable field and the model file is out of this round's scope.
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
  int _onsetHeldFrames = 0;

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

  /// Confirmed label changes divided by frames processed, `0..1` (ADR 0518
  /// D8). Includes the cold-start baseline confirmation (the very first
  /// label ever seen, raised from `null` — ADR 0518 D11), not only later
  /// displacements.
  double get flipRate =>
      _framesProcessed == 0 ? 0 : _confirmedFlips / _framesProcessed;

  /// How many frames had already met [StabilizerProfile.minAgreeFrames] but
  /// were still held back because they were not onset-aligned (E14-R28,
  /// ADR 0545 D3). Diagnostics only — it is the number that says how much
  /// latency the onset gate actually costs on a given input, so the
  /// transition-latency figure the Ch14 gate wants can be MEASURED instead of
  /// asserted.
  int get onsetHeldFrames => _onsetHeldFrames;

  /// Returns [frame] when it should reach the timeline, `null` when it
  /// should be dropped.
  LiveFrame? stabilize(LiveFrame frame) {
    _framesProcessed++;

    if (!_admitStrum(frame)) return null;

    final current = frame.current;
    if (current == null) return frame;

    // Already the established label — reaffirm immediately, even right
    // after an aborted displacement attempt: recovering to a label that is
    // ALREADY confirmed never needs to re-accumulate agreement (ADR 0518 D6).
    if (current.label == _confirmedLabel) {
      _pendingLabel = null;
      _agreeFrames = 0;
      _chordState = RecognitionDecision.confirmed;
      return frame;
    }

    // The very first decided label ever seen has no established baseline to
    // disagree with, so it confirms on sight (ADR 0518 D1: `candidate` is
    // the state before any label has been seen at all).
    if (_confirmedLabel == null) {
      _confirmedLabel = current.label;
      _confirmedFlips++;
      _confirmationLatencyFrames = 1;
      _chordState = RecognitionDecision.confirmed;
      return frame;
    }

    // A displacement attempt against an established label needs sustained
    // agreement before it can override it (ADR 0518 D3).
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

    // E14-R28 (ADR 0545 D2): agreement is necessary but no longer sufficient —
    // a chord may only CHANGE on a strum. The run keeps its accumulated
    // agreement while the gate is shut, so the moment an onset arrives the
    // already-proven challenger confirms on that frame instead of starting
    // over.
    if (!_isOnsetAligned(frame)) {
      _onsetHeldFrames++;
      _chordState = RecognitionDecision.provisional;
      return null;
    }

    _confirmedFlips++;
    _confirmationLatencyFrames = _framesProcessed - _pendingFirstFrame + 1;
    _confirmedLabel = current.label;
    _pendingLabel = null;
    _agreeFrames = 0;
    _chordState = RecognitionDecision.confirmed;
    return frame;
  }

  /// Whether [frame] sits inside a window in which a chord label change is
  /// musically plausible (E14-R28, ADR 0545 D2). Three admitting cases, in
  /// order:
  ///
  /// 1. **No clock.** `engineTimeSec` or `onsetTimeSec` is negative — the
  ///    producer does not track a sample clock or does not detect onsets
  ///    (mocks, hand-built frames, the `LiveFrameAdapter` boundary), so NO
  ///    onset evidence exists at all. The gate cannot judge and must not
  ///    freeze the label: behaviour falls back to plain ADR 0518 agreement.
  ///    Same convention as [LiveFrame.strumExpired].
  /// 2. **On the strum.** The newest onset is at most
  ///    [StabilizerProfile.onsetAlignmentWindowSec] old (and not in the
  ///    future). This is the intended path.
  /// 3. **Stale onset.** The newest onset is older than
  ///    [LiveFrame.strumHoldSec] (2 s) — the producer has itself already
  ///    dropped that strum from the frame, so the onset evidence has expired.
  ///    The gate re-opens rather than holding a label hostage to an onset the
  ///    detector never fired (a missed onset must cost latency, never a
  ///    permanently wrong chord).
  ///
  /// Between case 2 and case 3 — an onset that is real but too old — the
  /// displacement waits. That is the only behaviour this gate adds.
  bool _isOnsetAligned(LiveFrame frame) {
    final now = frame.engineTimeSec;
    // [LiveFrame.onsetTimeSec], NOT `latestStrumTime`: the latter only
    // advances for a strum whose DIRECTION was confirmed, so an onset the
    // model abstained on would otherwise hold the chord hostage.
    final onset = frame.onsetTimeSec;
    if (now < 0 || onset < 0) return true;
    final sinceOnset = now - onset;
    if (sinceOnset < 0) return true;
    return sinceOnset <= profile.onsetAlignmentWindowSec ||
        sinceOnset > LiveFrame.strumHoldSec;
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
