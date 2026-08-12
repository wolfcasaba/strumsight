import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/public.dart';

void main() {
  group('PitchCapabilityGate — flag and OD-01 boundaries', () {
    test(
      'flag OFF short-circuits before every OD-01 check and metric callback',
      () {
        var calls = 0;
        final result = PitchCapabilityGate().evaluate<void>(
          analysisPitchEnabled: false,
          hasMonophonicTarget: false,
          frames: const <PitchFrame>[],
          onAvailable: () => calls += 1,
        );

        expect(result.report.status, CapabilityStatus.notApplicable);
        expect(result.report.reason, isNull);
        expect(calls, 0);
      },
    );

    test('voiced-ratio threshold is inclusive at exactly 0.350', () {
      final gate = PitchCapabilityGate();
      for (final cell in <({int voiced, CapabilityStatus status})>[
        (voiced: 69, status: CapabilityStatus.unavailable),
        (voiced: 70, status: CapabilityStatus.available),
        (voiced: 71, status: CapabilityStatus.available),
      ]) {
        final result = gate.evaluate<void>(
          analysisPitchEnabled: true,
          hasMonophonicTarget: true,
          frames: _frames(total: 200, voiced: cell.voiced),
        );
        expect(result.report.status, cell.status, reason: '${cell.voiced}/200');
      }
    });

    test('polyphonic proxy blocks metrics before the callback', () {
      var calls = 0;
      final result = PitchCapabilityGate().evaluate<void>(
        analysisPitchEnabled: true,
        hasMonophonicTarget: true,
        frames: <PitchFrame>[
          ..._frames(total: 40, voiced: 20, frequency: 110),
          ..._frames(total: 40, voiced: 20, frequency: 440),
        ],
        onAvailable: () => calls += 1,
      );

      expect(result.report.status, CapabilityStatus.unavailable);
      expect(result.report.reason, CapabilityUnavailableReason.polyphonicInput);
      expect(calls, 0);
    });

    test(
      'low-confidence voiced evidence is unavailable, never a note score',
      () {
        final frames = _frames(total: 20, voiced: 20, confidence: 0.59);
        final result = PitchCapabilityGate().evaluate<void>(
          analysisPitchEnabled: true,
          hasMonophonicTarget: true,
          frames: frames,
        );
        expect(result.report.status, CapabilityStatus.unavailable);
        expect(
          result.report.reason,
          CapabilityUnavailableReason.confidenceTooLow,
        );
      },
    );
  });
}

List<PitchFrame> _frames({
  required int total,
  required int voiced,
  double frequency = 440,
  double confidence = 0.8,
}) => <PitchFrame>[
  for (var index = 0; index < total; index += 1)
    PitchFrame(
      time: Duration(milliseconds: index * 10),
      confidence: index < voiced ? confidence : 0,
      frequencyHz: index < voiced ? frequency : null,
      midiNote: index < voiced ? 69 : null,
    ),
];
