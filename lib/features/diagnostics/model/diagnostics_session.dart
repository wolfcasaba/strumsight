import 'package:flutter/foundation.dart';

import '../../analyze/engine/ml_chord_decoder.dart';
import '../../analyze/model/analyze_result.dart';

/// One ML-vs-DSP comparison point, sampled at an ML chord segment (Lab mode,
/// r198). Everything but the timestamp is nullable — the batch Analyze path
/// exposes labels + bpm but not per-frame confidences, so those stay null
/// rather than being faked. The backend stores the shape verbatim.
@immutable
class DiagnosticsEvent {
  const DiagnosticsEvent({
    required this.tSec,
    this.mlChord,
    this.dspChord,
    this.agree,
    this.mlConf,
    this.dspConf,
    this.strumDir,
    this.bpm,
    this.inputLevel,
  });

  /// Time (seconds) into the clip this comparison is sampled at.
  final double tSec;

  /// The ML head's chord label at [tSec] (majmin), or null for no-chord.
  final String? mlChord;

  /// The DSP path's chord label at [tSec] (its richer dictionary), or null.
  final String? dspChord;

  /// Whether ML and DSP agree at [tSec], both reduced to majmin.
  final bool? agree;

  /// ML posterior confidence, if the path exposes one (batch: null).
  final double? mlConf;

  /// DSP chord confidence, if the path exposes one (batch: null).
  final double? dspConf;

  /// Strum direction at [tSec] (`up`/`down`), if a strum landed here.
  final String? strumDir;

  /// The clip's detected tempo (same for every event of a session).
  final double? bpm;

  /// Input level 0..1, if available (batch: null).
  final double? inputLevel;

  Map<String, dynamic> toJson() => {
        'tSec': tSec,
        'mlChord': mlChord,
        'dspChord': dspChord,
        'agree': agree,
        'mlConf': mlConf,
        'dspConf': dspConf,
        'strumDir': strumDir,
        'bpm': bpm,
        'inputLevel': inputLevel,
      };
}

/// A short recorded audio clip attached to a diagnostics session (16-bit WAV,
/// base64) with the offset it starts at.
@immutable
class DiagnosticsAudioClip {
  const DiagnosticsAudioClip({required this.tSec, required this.wavBase64});

  final double tSec;
  final String wavBase64;

  Map<String, dynamic> toJson() => {'tSec': tSec, 'wavBase64': wavBase64};
}

/// A full Lab-mode diagnostics session, gzipped + POSTed to the backend
/// (r198). Anonymous, opt-in, and only built when Lab mode is ON with
/// diagnostics present. The server stores it verbatim; analysis is offline.
@immutable
class DiagnosticsSession {
  const DiagnosticsSession({
    required this.sessionId,
    required this.appVersion,
    required this.device,
    required this.startedAt,
    required this.events,
    this.surface = 'analyze',
    this.audioClips = const [],
  });

  final String sessionId;
  final String appVersion;
  final String device;

  /// ISO-8601 UTC timestamp the session was captured.
  final String startedAt;

  /// Which surface produced it. Analyze-only this round.
  final String surface;

  final List<DiagnosticsEvent> events;
  final List<DiagnosticsAudioClip> audioClips;

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'appVersion': appVersion,
        'device': device,
        'startedAt': startedAt,
        'surface': surface,
        'events': events.map((e) => e.toJson()).toList(),
        'audioClips': audioClips.map((c) => c.toJson()).toList(),
      };

  /// Build the events for a diagnostics session from a completed Analyze
  /// [result] whose Lab-mode [MlChordDiagnostics] are attached. One event per
  /// ML chord segment: its label, the DSP label at the segment's midpoint, and
  /// whether the two agree (both reduced to majmin). Confidences/level are not
  /// exposed by the batch path, so they stay null. Returns an empty list when
  /// no diagnostics are present — never throws.
  static List<DiagnosticsEvent> eventsFrom(AnalyzeResult result) {
    final diag = result.diagnostics;
    if (diag == null) return const [];
    final bpm = result.bpm;
    final events = <DiagnosticsEvent>[];
    for (final seg in diag.mlChords) {
      final mid = (seg.startSec + seg.endSec) / 2;
      final dspLabel = _labelAt(result.chords, mid);
      final agree = MlChordDecoder.majminReduce(seg.label) ==
          MlChordDecoder.majminReduce(dspLabel);
      events.add(DiagnosticsEvent(
        tSec: seg.startSec,
        mlChord: seg.label,
        dspChord: dspLabel,
        agree: agree,
        bpm: bpm.isFinite && bpm > 0 ? bpm : null,
        strumDir: _strumDirIn(result.strums, seg.startSec, seg.endSec),
      ));
    }
    return events;
  }

  /// The chord label covering time [t] in a timeline, or null (no-chord).
  static String? _labelAt(List<TimelineChord> chords, double t) {
    for (final c in chords) {
      if (t >= c.startSec && t < c.endSec) return c.label;
    }
    return null;
  }

  /// The direction of the first strum landing within `[start, end)`, or null.
  static String? _strumDirIn(
      List<TimelineStrum> strums, double start, double end) {
    for (final s in strums) {
      if (s.timeSec >= start && s.timeSec < end) return s.direction.name;
    }
    return null;
  }
}
