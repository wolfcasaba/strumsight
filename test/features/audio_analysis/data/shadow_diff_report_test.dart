import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/data/shadow/shadow_diff_report.dart';

void main() {
  test('records the six deterministic V1/V2 shadow comparison fields', () {
    const report = ShadowDiffReport(
      v1EventCount: 4,
      v2EventCount: 5,
      v1ChordSegmentCount: 2,
      v2ChordSegmentCount: 3,
      v1Bpm: 120,
      v2Bpm: 121,
      v1Duration: Duration(seconds: 2),
      v2Duration: Duration(seconds: 2),
      v1Runtime: Duration(milliseconds: 4),
      v2Runtime: Duration(milliseconds: 6),
      v2Failed: false,
    );

    expect(report.v1EventCount, 4);
    expect(report.v2EventCount, 5);
    expect(report.v1ChordSegmentCount, 2);
    expect(report.v2ChordSegmentCount, 3);
    expect(report.v1Bpm, 120);
    expect(report.v2Bpm, 121);
    expect(report.v1Duration, const Duration(seconds: 2));
    expect(report.v2Duration, const Duration(seconds: 2));
    expect(report.v1Runtime, const Duration(milliseconds: 4));
    expect(report.v2Runtime, const Duration(milliseconds: 6));
    expect(report.v2Failed, isFalse);
  });
}
