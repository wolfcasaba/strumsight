import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/public.dart';

void main() {
  test(
    'every unavailable reason has an explicit English and Hungarian string',
    () {
      final en = _arb('lib/l10n/app_en.arb');
      final hu = _arb('lib/l10n/app_hu.arb');

      for (final reason in CapabilityUnavailableReason.values) {
        final key =
            'analysisCapabilityUnavailable${reason.name[0].toUpperCase()}${reason.name.substring(1)}';
        expect(en, contains(key), reason: 'English missing $reason');
        expect(hu, contains(key), reason: 'Hungarian missing $reason');
      }
    },
  );

  test('identity calibration cannot be represented as calibrated', () {
    expect(
      () => CapabilityReport(
        capability: AnalysisCapability.signalQuality,
        status: CapabilityStatus.available,
        confidence: 0.9,
        calibrationVersion: CalibrationTable.identityVersion,
        calibrationSource: ConfidenceCalibrationSource.calibrated,
      ),
      throwsArgumentError,
    );
  });
}

Map<String, Object?> _arb(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
