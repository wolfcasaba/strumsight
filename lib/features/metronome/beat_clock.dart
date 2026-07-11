/// Phase-preserving beat clock (round 98). The naive `beat = secs · bpm/60`
/// rescales the WHOLE elapsed time when the tempo changes mid-play (60→240
/// BPM at 30 s teleports beat 30 → 120, jumping the bar position and click).
/// BeatClock instead anchors the beat position at every tempo change, so the
/// playhead is continuous and beats accrue at the new rate only from there.
class BeatClock {
  BeatClock({required this._bpm});

  int _bpm;
  double _anchorSecs = 0;
  double _anchorBeats = 0;

  int get bpm => _bpm;

  /// Continuous beat position at wall-time [secs].
  double beatsAt(double secs) =>
      _anchorBeats + (secs - _anchorSecs) * _bpm / 60.0;

  /// Change tempo mid-flight, preserving the beat phase at [atSecs].
  void setBpm(int newBpm, {required double atSecs}) {
    _anchorBeats = beatsAt(atSecs);
    _anchorSecs = atSecs;
    _bpm = newBpm;
  }

  /// Rewind to beat zero (tempo kept) — call when playback (re)starts.
  void reset() {
    _anchorSecs = 0;
    _anchorBeats = 0;
  }
}
