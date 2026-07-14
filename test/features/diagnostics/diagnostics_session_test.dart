import 'package:flutter_test/flutter_test.dart';
import 'package:music_theory/features/analyze/model/analyze_result.dart';
import 'package:music_theory/features/diagnostics/model/diagnostics_session.dart';
import 'package:music_theory/features/live/model/strum.dart';

void main() {
  group('DiagnosticsSession.eventsFrom', () {
    test('returns empty when the result carries no diagnostics', () {
      const result = AnalyzeResult(
        durationSec: 4,
        bpm: 100,
        chords: [TimelineChord(label: 'C', startSec: 0, endSec: 4)],
        strums: [],
      );
      expect(DiagnosticsSession.eventsFrom(result), isEmpty);
    });

    test('one event per ML segment with DSP label + agree at the midpoint', () {
      final result = const AnalyzeResult(
        durationSec: 4,
        bpm: 120,
        chords: [
          TimelineChord(label: 'C', startSec: 0, endSec: 2),
          TimelineChord(label: 'Am7', startSec: 2, endSec: 4),
        ],
        strums: [
          TimelineStrum(
              direction: StrumDirection.down, timeSec: 0.5, confidence: 0.9),
        ],
      ).withDiagnostics(const MlChordDiagnostics(
        mlChords: [
          // Agrees with DSP 'C' at t=1.
          TimelineChord(label: 'C', startSec: 0, endSec: 2),
          // DSP is 'Am7' → majmin 'Am'; ML 'Am' agrees.
          TimelineChord(label: 'Am', startSec: 2, endSec: 4),
        ],
        agreement: 1.0,
      ));

      final events = DiagnosticsSession.eventsFrom(result);
      expect(events, hasLength(2));

      expect(events[0].tSec, 0);
      expect(events[0].mlChord, 'C');
      expect(events[0].dspChord, 'C');
      expect(events[0].agree, isTrue);
      expect(events[0].bpm, 120);
      // A down strum lands in [0,2).
      expect(events[0].strumDir, 'down');
      // Batch path exposes no confidences.
      expect(events[0].mlConf, isNull);
      expect(events[0].dspConf, isNull);

      expect(events[1].mlChord, 'Am');
      expect(events[1].dspChord, 'Am7');
      expect(events[1].agree, isTrue); // Am7 reduces to Am
      expect(events[1].strumDir, isNull);
    });

    test('agree is false when majmin reductions differ', () {
      final result = const AnalyzeResult(
        durationSec: 2,
        bpm: 90,
        chords: [TimelineChord(label: 'G', startSec: 0, endSec: 2)],
        strums: [],
      ).withDiagnostics(const MlChordDiagnostics(
        mlChords: [TimelineChord(label: 'Em', startSec: 0, endSec: 2)],
        agreement: 0.0,
      ));
      final events = DiagnosticsSession.eventsFrom(result);
      expect(events.single.agree, isFalse);
    });
  });

  group('DiagnosticsSession.toJson', () {
    test('emits the full contract shape', () {
      final session = DiagnosticsSession(
        sessionId: 'sid-1',
        appVersion: '1.0.0+1',
        device: 'android',
        startedAt: '2026-07-14T00:00:00.000Z',
        events: const [
          DiagnosticsEvent(
            tSec: 0,
            mlChord: 'C',
            dspChord: 'C',
            agree: true,
            bpm: 120,
          ),
        ],
        audioClips: const [
          DiagnosticsAudioClip(tSec: 0, wavBase64: 'AAAA'),
        ],
      );

      final json = session.toJson();
      expect(json['sessionId'], 'sid-1');
      expect(json['appVersion'], '1.0.0+1');
      expect(json['device'], 'android');
      expect(json['startedAt'], '2026-07-14T00:00:00.000Z');
      expect(json['surface'], 'analyze');

      final events = json['events'] as List;
      expect(events, hasLength(1));
      final e = events.first as Map<String, dynamic>;
      expect(e.keys, containsAll(<String>[
        'tSec',
        'mlChord',
        'dspChord',
        'agree',
        'mlConf',
        'dspConf',
        'strumDir',
        'bpm',
        'inputLevel',
      ]));
      expect(e['mlConf'], isNull); // null-safe, present but null

      final clips = json['audioClips'] as List;
      expect((clips.first as Map)['wavBase64'], 'AAAA');
    });
  });
}
