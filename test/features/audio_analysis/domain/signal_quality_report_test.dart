import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/public.dart';

void main() {
  test('measured defaults to true for native reports', () {
    final report = SignalQualityReport(
      overall: .5,
      peakDbfs: -1,
      rmsDbfs: -12,
      noiseFloorDbfs: -48,
      clippedSampleRatio: 0,
      silentRatio: 0,
      tonalness: .5,
    );

    expect(report.measured, isTrue);
  });
}
