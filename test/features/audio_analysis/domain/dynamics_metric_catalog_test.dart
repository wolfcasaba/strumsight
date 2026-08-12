import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/public.dart';

void main() {
  group('dynamics metric catalog (ADR 0234)', () {
    test('all seven dynamics IDs are registered and versioned', () {
      final pattern = RegExp(r'^[a-z_]+\.[a-z0-9_]+\.v[0-9]+$');
      expect(DynamicsMetricIds.all, everyElement(matches(pattern)));
      for (final id in DynamicsMetricIds.all) {
        expect(AnalysisMetricId.contains(id), isTrue, reason: id);
      }
      expect(DynamicsMetricIds.all.length, 7);
    });

    test('the catalog has no accidental collisions', () {
      expect(
        AnalysisMetricId.known.length,
        AnalysisMetricId.known.toSet().length,
      );
    });

    test('dynamics IDs live in the dynamics namespace', () {
      for (final id in DynamicsMetricIds.all) {
        expect(id, startsWith('dynamics.'));
      }
    });

    test(
      'metric and localization strings never frame down/up as better/worse',
      () {
        final forbidden = RegExp(
          r'(lower|higher|better|worse)_?is_?(better|worse)',
          caseSensitive: false,
        );
        final strings = <String>[
          ...AnalysisMetricId.known,
          File('lib/l10n/app_en.arb').readAsStringSync(),
          File('lib/l10n/app_hu.arb').readAsStringSync(),
        ];
        for (final value in strings) {
          expect(forbidden.hasMatch(value), isFalse, reason: value);
        }
      },
    );

    test('en and hu ARB carry every dynamics metric label', () {
      const keys = <String>[
        'dynamicsMetricStrokeStrengthCv',
        'dynamicsMetricDownUpMedianRatio',
        'dynamicsMetricDrift',
        'dynamicsMetricOutlierRatio',
        'dynamicsMetricAccentAccuracy',
        'dynamicsMetricQuietRegionRatio',
        'dynamicsMetricClippedEventRatio',
      ];
      final en = File('lib/l10n/app_en.arb').readAsStringSync();
      final hu = File('lib/l10n/app_hu.arb').readAsStringSync();
      for (final key in keys) {
        expect(en, contains('"$key"'), reason: key);
        expect(hu, contains('"$key"'), reason: key);
      }
    });
  });
}
