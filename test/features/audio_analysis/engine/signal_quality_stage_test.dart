import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';
import 'package:strumsight/features/audio_analysis/engine/analysis_context.dart';
import 'package:strumsight/features/audio_analysis/public.dart';

import '../../../support/synth.dart';

const _sampleRate = 44100;

AnalysisStageContext _context({
  AnalysisProgressEventSink eventSink = _noopSink,
  AnalysisCancellationToken? cancellationToken,
}) => AnalysisStageContext(
  runId: 'test-run',
  phase: AnalysisProgressPhase.preprocessing,
  cancellationToken: cancellationToken ?? AnalysisCancellationSource(),
  eventSink: eventSink,
);

void _noopSink(AnalysisProgressEvent event) {}

PcmAnalysisInput _input(List<double> samples, {int sampleRate = _sampleRate}) =>
    PcmAnalysisInput(
      samples: samples,
      sampleRate: sampleRate,
      channelCount: 1,
      source: AnalysisInputSource.microphone,
    );

List<double> _sine({
  required double freq,
  required double seconds,
  double amplitude = 0.2,
  int sampleRate = _sampleRate,
}) => List<double>.generate(
  (seconds * sampleRate).round(),
  (i) => amplitude * math.sin(2 * math.pi * freq * i / sampleRate),
);

List<double> _clamp(List<double> samples, {double limit = 1.0}) => <double>[
  for (final s in samples) s.clamp(-limit, limit).toDouble(),
];

/// Deterministic pseudo-noise (no dart:math Random) so fixtures stay
/// reproducible without a seeded-generator dependency.
List<double> _pseudoNoise(int length, {double amplitude = 0.3, int seed = 7}) {
  var state = seed;
  return List<double>.generate(length, (_) {
    state = (state * 1103515245 + 12345) & 0x7fffffff;
    return amplitude * ((state / 0x7fffffff) * 2 - 1);
  });
}

void _expectFinite(SignalQualityReport report) {
  expect(report.overall.isFinite, isTrue, reason: 'overall');
  expect(report.peakDbfs.isFinite, isTrue, reason: 'peakDbfs');
  expect(report.rmsDbfs.isFinite, isTrue, reason: 'rmsDbfs');
  expect(report.noiseFloorDbfs.isFinite, isTrue, reason: 'noiseFloorDbfs');
  expect(report.tonalness.isFinite, isTrue, reason: 'tonalness');
  expect(
    report.clippedSampleRatio,
    inInclusiveRange(0.0, 1.0),
    reason: 'clippedSampleRatio',
  );
  expect(report.silentRatio, inInclusiveRange(0.0, 1.0), reason: 'silentRatio');
  expect(
    report.peakDbfs,
    inInclusiveRange(
      QualityThresholds.silenceFloorDbfs,
      QualityThresholds.maxDbfs,
    ),
  );
  expect(
    report.rmsDbfs,
    inInclusiveRange(
      QualityThresholds.silenceFloorDbfs,
      QualityThresholds.maxDbfs,
    ),
  );
  expect(
    report.noiseFloorDbfs,
    inInclusiveRange(
      QualityThresholds.silenceFloorDbfs,
      QualityThresholds.maxDbfs,
    ),
  );
}

void main() {
  const stage = SignalQualityStage();

  group('SignalQualityStage contract', () {
    test(
      'id and version match QualityThresholds.version (ADR 0223 provenance)',
      () {
        expect(stage.id, isNotEmpty);
        expect(stage.version, QualityThresholds.version);
      },
    );

    test(
      'reports progress at most once and never publishes a terminal result',
      () async {
        final events = <AnalysisProgressEvent>[];
        final context = _context(eventSink: events.add);
        final result = await stage.run(
          _input(_sine(freq: 440, seconds: 1)),
          context,
        );
        expect(result.isSuccess, isTrue);
        expect(context.hasReportedProgress, isTrue);
        expect(events.whereType<AnalysisPhaseProgressEvent>(), hasLength(1));
        expect(events.whereType<AnalysisRunResultEvent>(), isEmpty);
      },
    );
  });

  group('fixture matrix — full report checked per cell', () {
    test('(1) clean silence', () async {
      final report = (await stage.run(
        _input(List<double>.filled(_sampleRate * 2, 0.0)),
        _context(),
      )).valueOrNull!;
      _expectFinite(report);
      expect(report.peakDbfs, QualityThresholds.silenceFloorDbfs);
      expect(report.rmsDbfs, QualityThresholds.silenceFloorDbfs);
      expect(report.noiseFloorDbfs, QualityThresholds.silenceFloorDbfs);
      expect(report.clippedSampleRatio, 0.0);
      expect(report.silentRatio, 1.0);
      expect(report.tonalness, 0.0);
      expect(
        report.warnings.any(
          (w) => w.messageKey == 'signal_quality.mostly_silent',
        ),
        isTrue,
      );
    });

    test('(2) -40 dBFS sine', () async {
      final amplitude = math.pow(10, -40.0 / 20).toDouble();
      final report = (await stage.run(
        _input(_sine(freq: 220, seconds: 2, amplitude: amplitude)),
        _context(),
      )).valueOrNull!;
      _expectFinite(report);
      expect(report.peakDbfs, closeTo(-40.0, 0.5));
      expect(report.clippedSampleRatio, 0.0);
      expect(report.silentRatio, lessThan(0.05));
      expect(
        report.warnings.any(
          (w) => w.messageKey == 'signal_quality.clipping_detected',
        ),
        isFalse,
      );
    });

    test('(3) full-scale sine with clipping', () async {
      final overdriven = _clamp(_sine(freq: 220, seconds: 2, amplitude: 1.4));
      final report = (await stage.run(
        _input(overdriven),
        _context(),
      )).valueOrNull!;
      _expectFinite(report);
      expect(report.peakDbfs, closeTo(0.0, 1e-6));
      expect(
        report.clippedSampleRatio,
        greaterThanOrEqualTo(QualityThresholds.clippedRatioWarning),
      );
      expect(
        report.warnings.any(
          (w) => w.messageKey == 'signal_quality.clipping_detected',
        ),
        isTrue,
      );
    });

    test('(4) impulsive (short, repeated) clipping', () async {
      final samples = _sine(freq: 220, seconds: 2, amplitude: 0.1);
      for (var i = 0; i < samples.length; i += 5000) {
        samples[i] = 1.0;
      }
      final report = (await stage.run(
        _input(samples),
        _context(),
      )).valueOrNull!;
      _expectFinite(report);
      expect(report.clippedSampleRatio, greaterThan(0.0));
      expect(report.clippedSampleRatio, lessThan(0.01));
      expect(report.peakDbfs, closeTo(0.0, 1e-6));
    });

    test('(5) white noise — noise floor tracks the 10th percentile', () async {
      final noise = _pseudoNoise(_sampleRate * 2, amplitude: 0.3);
      final report = (await stage.run(_input(noise), _context())).valueOrNull!;
      _expectFinite(report);
      expect(report.silentRatio, 0.0);
      expect(report.tonalness, lessThan(0.3));
      // A fairly uniform-power signal: noise floor should sit reasonably
      // close to the overall RMS, not near the -120 dBFS silence floor.
      expect(report.noiseFloorDbfs, greaterThan(-40.0));
    });

    test('(6) clean chord fixture — tonal, low clipping, no silence', () async {
      final chord = chordSignal(
        <double>[220.0, 277.18, 329.63],
        seconds: 2,
        sampleRate: _sampleRate,
        amp: 0.2,
      );
      final report = (await stage.run(
        _input(List<double>.of(chord)),
        _context(),
      )).valueOrNull!;
      _expectFinite(report);
      expect(report.tonalness, greaterThan(0.5));
      expect(report.clippedSampleRatio, 0.0);
      expect(report.silentRatio, lessThan(0.5));
    });

    test(
      '(7) 200 ms short clip completes and carries the inputQuality warning',
      () async {
        final report = (await stage.run(
          _input(_sine(freq: 440, seconds: 0.2, amplitude: 0.3)),
          _context(),
        )).valueOrNull!;
        _expectFinite(report);
        expect(report.peakDbfs, isNot(QualityThresholds.silenceFloorDbfs));
        expect(
          report.warnings.any(
            (w) => w.messageKey == 'signal_quality.short_clip',
          ),
          isTrue,
        );
        final shortClipWarning = report.warnings.firstWhere(
          (w) => w.messageKey == 'signal_quality.short_clip',
        );
        expect(shortClipWarning.kind, AnalysisWarningKind.inputQuality);
      },
    );

    test(
      '(8) silence + one loud section — active-region ratio distinguishes it from (5)',
      () async {
        final loud = _sine(freq: 220, seconds: 0.3, amplitude: 0.5);
        final samples = <double>[
          ...List<double>.filled(_sampleRate * 8, 0.0),
          ...loud,
          ...List<double>.filled(_sampleRate * 8, 0.0),
        ];
        final report = (await stage.run(
          _input(samples),
          _context(),
        )).valueOrNull!;
        _expectFinite(report);
        // Mostly silent overall, but the noise floor (10th percentile) must
        // still read the quiet floor rather than being dragged up by the mean.
        expect(report.silentRatio, greaterThan(0.95));
        expect(
          report.noiseFloorDbfs,
          closeTo(QualityThresholds.silenceFloorDbfs, 1.0),
        );
        expect(
          report.warnings.any(
            (w) => w.messageKey == 'signal_quality.mostly_silent',
          ),
          isTrue,
        );
      },
    );
  });

  group('determinism', () {
    test(
      'the same PCM produces a bit-identical report across two runs',
      () async {
        final samples = List<double>.of(
          _clamp(_sine(freq: 330, seconds: 1.5, amplitude: 0.9)),
        );
        final first = (await stage.run(
          _input(List<double>.of(samples)),
          _context(),
        )).valueOrNull!;
        final second = (await stage.run(
          _input(List<double>.of(samples)),
          _context(),
        )).valueOrNull!;

        expect(first.overall, second.overall);
        expect(first.peakDbfs, second.peakDbfs);
        expect(first.rmsDbfs, second.rmsDbfs);
        expect(first.noiseFloorDbfs, second.noiseFloorDbfs);
        expect(first.clippedSampleRatio, second.clippedSampleRatio);
        expect(first.silentRatio, second.silentRatio);
        expect(first.tonalness, second.tonalness);
        expect(
          first.warnings.map((w) => w.messageKey),
          second.warnings.map((w) => w.messageKey),
        );
      },
    );
  });

  group('no game-quality claims', () {
    final badPlayPattern = RegExp(
      r'(bad|poor|wrong|sloppy|rossz|gyenge)_?play',
      caseSensitive: false,
    );

    test(
      'no warning key across the fixture matrix grades the player',
      () async {
        final fixtures = <List<double>>[
          List<double>.filled(_sampleRate, 0.0),
          _sine(freq: 220, seconds: 1, amplitude: 0.01),
          _clamp(_sine(freq: 220, seconds: 1, amplitude: 1.4)),
          _pseudoNoise(_sampleRate, amplitude: 0.3),
          List<double>.of(
            chordSignal(
              <double>[220.0, 277.18, 329.63],
              seconds: 1,
              sampleRate: _sampleRate,
            ),
          ),
          _sine(freq: 440, seconds: 0.2, amplitude: 0.3),
        ];
        for (final samples in fixtures) {
          final report = (await stage.run(
            _input(samples),
            _context(),
          )).valueOrNull!;
          for (final warning in report.warnings) {
            expect(
              badPlayPattern.hasMatch(warning.messageKey),
              isFalse,
              reason: 'messageKey=${warning.messageKey}',
            );
          }
        }
      },
    );
  });

  group('cooperative cancellation (F1)', () {
    test('a pre-cancelled token throws instead of yielding Success', () async {
      final source = AnalysisCancellationSource()..cancel();
      await expectLater(
        stage.run(
          _input(_sine(freq: 440, seconds: 1)),
          _context(cancellationToken: source),
        ),
        throwsA(isA<AnalysisCancelledException>()),
      );
    });

    test(
      'cancellation mid frame-processing throws before the report is built',
      () async {
        final source = AnalysisCancellationSource();
        var checks = 0;
        // The stage itself checks the token twice before frame processing
        // starts (once on entry, once after the nonfinite guard); cancelling
        // after the 5th check proves the frame loop's own hook — not just the
        // pre-run checks — is what observed the cancellation.
        final context = AnalysisStageContext(
          runId: 'test-run',
          phase: AnalysisProgressPhase.preprocessing,
          cancellationToken: _CancelAfterNChecks(
            source,
            cancelAfter: 5,
            onCheck: () => checks++,
          ),
          eventSink: _noopSink,
        );
        await expectLater(
          stage.run(_input(_sine(freq: 440, seconds: 5)), context),
          throwsA(isA<AnalysisCancelledException>()),
        );
        expect(checks, greaterThan(2));
      },
    );
  });

  group('nonfinite PCM guard (F2)', () {
    for (final value in <double>[
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      test('direct stage.run rejects $value as a typed failure', () async {
        final events = <AnalysisProgressEvent>[];
        final context = _context(eventSink: events.add);
        final result = await stage.run(
          _input(<double>[0.1, value, -0.2]),
          context,
        );
        expect(result, isA<Failure<SignalQualityReport>>());
        final failure = (result as Failure<SignalQualityReport>).error;
        expect(failure, isA<AudioFailure>());
        expect(failure.code, FailureCode.audioNonFiniteSample);
        expect(context.hasReportedProgress, isFalse);
        expect(events, isEmpty);
      });
    }
  });
}

/// Delegates to [source] but throws once [onCheck] has observed [cancelAfter]
/// calls to [throwIfCancelled] — used to prove mid-processing cancellation is
/// honoured, not just the pre-run check.
final class _CancelAfterNChecks implements AnalysisCancellationToken {
  _CancelAfterNChecks(
    this.source, {
    required this.cancelAfter,
    required this.onCheck,
  });

  final AnalysisCancellationSource source;
  final int cancelAfter;
  final void Function() onCheck;
  int _checks = 0;

  @override
  bool get isCancelled => source.isCancelled || _checks >= cancelAfter;

  @override
  void throwIfCancelled() {
    onCheck();
    _checks++;
    if (isCancelled) throw const AnalysisCancelledException();
  }
}
