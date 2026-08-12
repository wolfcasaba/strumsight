import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/config/app_environment.dart';
import 'package:strumsight/app/config/feature_flags.dart';
import 'package:strumsight/features/audio_analysis/public.dart';

void main() {
  group('technique-proxy metric catalog (ADR 0236)', () {
    test('all five technique IDs are registered and versioned', () {
      final pattern = RegExp(r'^[a-z_]+\.[a-z0-9_]+\.v[0-9]+$');
      expect(TechniqueProxyMetricIds.all, everyElement(matches(pattern)));
      for (final id in TechniqueProxyMetricIds.all) {
        expect(AnalysisMetricId.contains(id), isTrue, reason: id);
      }
      expect(TechniqueProxyMetricIds.all.length, 5);
    });

    test('the catalog has no accidental collisions', () {
      expect(
        AnalysisMetricId.known.length,
        AnalysisMetricId.known.toSet().length,
      );
    });

    test('technique IDs live in the technique namespace', () {
      for (final id in TechniqueProxyMetricIds.all) {
        expect(id, startsWith('technique.'));
      }
    });

    test('en and hu ARB carry every technique proxy label', () {
      const keys = <String>[
        'analysisTechniqueChordChangeGap',
        'analysisTechniqueConfidenceCollapseDuration',
        'analysisTechniqueUnexpectedExtraOnsets',
        'analysisTechniqueSustainedNoteDropout',
        'analysisTechniqueAttackInstability',
        'analysisTechniqueDisclaimer',
      ];
      final en = File('lib/l10n/app_en.arb').readAsStringSync();
      final hu = File('lib/l10n/app_hu.arb').readAsStringSync();
      for (final key in keys) {
        expect(en, contains('"$key"'), reason: key);
        expect(hu, contains('"$key"'), reason: key);
      }
    });

    test(
      'the new flag defaults to false in every environment (flag-guard)',
      () {
        for (final environment in AppEnvironment.values) {
          final flags = FeatureFlags.forEnvironment(
            environment,
            accountEnabled: false,
          );
          expect(
            flags.analysisTechniqueProxiesEnabled,
            isFalse,
            reason:
                '$environment must not implicitly enable technique proxies.',
          );
          expect(
            flags.toString(),
            contains('analysisTechniqueProxiesEnabled: false'),
          );
        }
        const defaults = FeatureFlags(
          accountEnabled: false,
          diagnosticsEnabled: false,
          labModeAvailable: false,
        );
        expect(defaults.analysisTechniqueProxiesEnabled, isFalse);
      },
    );

    test(
      'AnalysisDocument, its codec and the pipeline never reference the '
      'technique-proxy namespace — no document/pipeline wiring in this round',
      () {
        const scannedFiles = <String>[
          'lib/features/audio_analysis/domain/analysis_document.dart',
          'lib/features/audio_analysis/data/analysis_document_codec.dart',
          'lib/features/audio_analysis/engine/analysis_pipeline.dart',
        ];
        for (final path in scannedFiles) {
          final contents = File(path).readAsStringSync();
          expect(
            contents,
            isNot(contains('technique')),
            reason: '$path must not reference the technique-proxy namespace.',
          );
          expect(
            contents,
            isNot(contains('TechniqueProxy')),
            reason: '$path must not reference TechniqueProxyReport.',
          );
        }
      },
    );
  });
}
