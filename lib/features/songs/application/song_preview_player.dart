import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/music/strum.dart';
import '../../learn/public.dart' show ChordAudition;

/// One stroke of a progression preview: when, which chord, which way.
@immutable
final class PreviewStrum {
  const PreviewStrum({
    required this.timeSec,
    required this.bar,
    required this.chord,
    required this.direction,
  });

  final double timeSec;

  /// Zero-based bar (= index into the progression) the stroke belongs to.
  final int bar;
  final String chord;
  final StrumDirection direction;

  @override
  bool operator ==(Object other) =>
      other is PreviewStrum &&
      other.timeSec == timeSec &&
      other.bar == bar &&
      other.chord == chord &&
      other.direction == direction;

  @override
  int get hashCode => Object.hash(timeSec, bar, chord, direction);

  @override
  String toString() => 'PreviewStrum(${timeSec}s bar $bar $chord $direction)';
}

/// The timed strokes of a progression under a one-bar strum pattern
/// (ADR 0535 D3). Pure: eighth-note slots, `null` = rest, one chord per bar.
///
/// A pattern whose length does not match `beatsPerBar * 2` is fitted the way
/// `Song.fromJson` fits it (truncate / rest-pad) rather than spilling into
/// the next bar. A non-positive tempo or an empty progression yields nothing.
List<PreviewStrum> previewSchedule({
  required List<String> chords,
  required List<StrumDirection?> pattern,
  required int bpm,
  required int beatsPerBar,
}) {
  if (bpm <= 0 || beatsPerBar <= 0 || chords.isEmpty) return const [];
  final slots = beatsPerBar * 2;
  final secPerBeat = 60.0 / bpm;
  final out = <PreviewStrum>[];
  for (var bar = 0; bar < chords.length; bar++) {
    for (var slot = 0; slot < slots; slot++) {
      final dir = slot < pattern.length ? pattern[slot] : null;
      if (dir == null) continue;
      out.add(
        PreviewStrum(
          timeSec: (bar * beatsPerBar + slot * 0.5) * secPerBeat,
          bar: bar,
          chord: chords[bar],
          direction: dir,
        ),
      );
    }
  }
  return out;
}

/// Plays a progression preview through a [ChordAudition] on a timer chain
/// (ADR 0535 D3): the composer hears the whole song — chords AND the ↓/↑
/// pattern — before picking up the guitar.
///
/// The schedule is computed once by [previewSchedule]; this class only owns
/// the clock. Listeners are notified on start, on every bar change and on
/// stop, so the editor can highlight the bar that is sounding. Stopping —
/// explicitly, at the end, or on [dispose] — cancels the pending timer and
/// silences the audition, so nothing keeps ringing after the user leaves.
final class SongPreviewController extends ChangeNotifier {
  SongPreviewController(this.audition);

  /// The player this preview strums through (identity matters to the
  /// owning screen — see `SongBuilderScreen._previewFor`).
  final ChordAudition audition;

  Timer? _timer;
  bool _playing = false;
  int? _currentBar;
  bool _disposed = false;

  bool get isPlaying => _playing;

  /// The bar sounding right now, or null when idle.
  int? get currentBar => _currentBar;

  /// Start (or restart) the preview of this progression.
  void start({
    required List<String> chords,
    required List<StrumDirection?> pattern,
    required int bpm,
    required int beatsPerBar,
  }) {
    stop();
    final schedule = previewSchedule(
      chords: chords,
      pattern: pattern,
      bpm: bpm,
      beatsPerBar: beatsPerBar,
    );
    if (schedule.isEmpty) return;
    final totalSec = chords.length * beatsPerBar * 60.0 / bpm;
    _playing = true;
    _currentBar = null;
    _step(schedule, 0, totalSec);
  }

  void _step(List<PreviewStrum> schedule, int index, double totalSec) {
    if (_disposed || !_playing) return;
    if (index >= schedule.length) {
      // Let the last bar ring out before reporting the end.
      final lastSec = schedule.last.timeSec;
      _timer = Timer(_delay(totalSec - lastSec), stop);
      return;
    }
    final strum = schedule[index];
    if (strum.bar != _currentBar) {
      _currentBar = strum.bar;
      notifyListeners();
    }
    unawaited(audition.strum(strum.chord, direction: strum.direction));
    final next = index + 1;
    final nextSec = next < schedule.length ? schedule[next].timeSec : totalSec;
    _timer = Timer(
      _delay(nextSec - strum.timeSec),
      () => _step(schedule, next, totalSec),
    );
  }

  static Duration _delay(double seconds) {
    final micros = (seconds.clamp(0, double.infinity) * 1e6).round();
    return Duration(microseconds: micros);
  }

  /// Stop the preview and silence the audition. Idempotent.
  void stop() {
    _timer?.cancel();
    _timer = null;
    if (!_playing && _currentBar == null) return;
    _playing = false;
    _currentBar = null;
    unawaited(audition.stop());
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    if (_playing) {
      _playing = false;
      _currentBar = null;
      unawaited(audition.stop());
    }
    _disposed = true;
    super.dispose();
  }
}
