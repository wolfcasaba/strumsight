import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/public.dart';

void main() {
  test('capability catalogue matches the SDD status and reason sets', () {
    expect(AnalysisCapability.values, hasLength(14));
    expect(CapabilityStatus.values, hasLength(4));
    expect(CapabilityUnavailableReason.values, hasLength(13));
  });

  test(
    'unavailable capability has an explicit explanation and immutable details',
    () {
      final details = <String, Object?>{'eventCount': 0};
      final report = CapabilityReport(
        capability: AnalysisCapability.beatGrid,
        status: CapabilityStatus.unavailable,
        confidence: 0,
        reason: CapabilityUnavailableReason.insufficientEvents,
        details: details,
      );
      details['eventCount'] = 1;
      expect(report.details['eventCount'], 0);
      expect(() => report.details['new'] = true, throwsUnsupportedError);
      expect(
        () => CapabilityReport(
          capability: AnalysisCapability.beatGrid,
          status: CapabilityStatus.unavailable,
          confidence: 0,
        ),
        throwsArgumentError,
      );
    },
  );
}
