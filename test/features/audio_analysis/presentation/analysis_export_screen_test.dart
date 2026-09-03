// AnalysisExportScreen (E06-R27 brief §6 acceptance criteria:
// "Előnézet-kapu", "UI" — categories not raw JSON, hu/en parity,
// 320px/textScale 2.0 without overflow).

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/themes/ss_light_theme.dart';
import 'package:strumsight/features/audio_analysis/public.dart';
import 'package:strumsight/features/share/public.dart';
import 'package:strumsight/l10n/app_localizations.dart';

class _FakeShareService extends ShareService {
  _FakeShareService();
  int callCount = 0;

  @override
  Future<void> shareExportFile({
    required File file,
    required String caption,
    String? subject,
    Rect? sharePositionOrigin,
  }) async {
    callCount += 1;
  }
}

AnalysisDocument _document() => AnalysisDocument(
  id: 'doc-screen',
  schemaVersion: analysisDocumentSchemaVersion,
  createdAt: DateTime.utc(2026, 8, 13),
  mode: AnalysisMode.freePlay,
  input: AnalysisInputSummary(
    source: AnalysisInputSource.microphone,
    duration: const Duration(seconds: 20),
    sampleRate: 48000,
    channelCount: 1,
    fingerprint: 'fp',
  ),
  provenance: AnalysisProvenance(
    appVersion: '1.0.0',
    analyzerVersion: '1',
    pipelineVersion: '1',
    stageVersions: const <String, String>{},
    dspConfigHash: 'cfg',
    modelManifestIds: const <String>[],
    inputFingerprint: 'fp',
    platform: 'android',
    featureFlagSnapshot: const <String, bool>{},
  ),
  signalQuality: SignalQualityReport(
    overall: 0.8,
    peakDbfs: -3,
    rmsDbfs: -18,
    noiseFloorDbfs: -60,
    clippedSampleRatio: 0,
    silentRatio: 0,
    tonalness: 0.5,
  ),
  capabilities: <CapabilityReport>[
    CapabilityReport(
      capability: AnalysisCapability.onsetTimeline,
      status: CapabilityStatus.available,
      confidence: 0.9,
    ),
  ],
  timeline: AnalysisTimeline(duration: const Duration(seconds: 20)),
  metrics: <AnalysisMetricResult>[
    AnalysisMetricResult(
      id: AnalysisMetricId.timingMeanAbsoluteError,
      version: 1,
      status: CapabilityStatus.available,
      confidence: 0.7,
      unit: 's',
      sampleCount: 4,
      evidence: const <String>[],
      value: ScalarMetricValue(0.05),
    ),
  ],
  hotspots: const <AnalysisHotspot>[],
  insights: const <AnalysisInsight>[],
  warnings: const <AnalysisWarning>[],
  completion: AnalysisCompletion(status: AnalysisCompletionStatus.complete),
);

Widget _harness(
  AnalysisDocument document,
  ExportAnalysisUseCase useCase, {
  Locale locale = const Locale('en'),
}) {
  return MaterialApp(
    theme: SsLightTheme.data(),
    locale: locale,
    localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
    ],
    supportedLocales: AppLocalizations.supportedLocales,
    home: AnalysisExportScreen(document: document, exportUseCase: useCase),
  );
}

void main() {
  late Directory tempRoot;

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp(
      'analysis_export_screen_test_',
    );
  });

  tearDown(() {
    if (tempRoot.existsSync()) {
      tempRoot.deleteSync(recursive: true);
    }
  });

  testWidgets('renders category labels, never raw export JSON', (tester) async {
    final fake = _FakeShareService();
    final useCase = ExportAnalysisUseCase(
      shareService: fake,
      tempDirectory: tempRoot,
    );

    await tester.pumpWidget(_harness(_document(), useCase));
    await tester.pumpAndSettle();

    expect(find.text('Metrics'), findsOneWidget);
    expect(find.text('Capabilities'), findsOneWidget);
    expect(find.textContaining('exportSchemaVersion'), findsNothing);
    expect(find.textContaining('"documentId"'), findsNothing);
  });

  testWidgets(
    'preview gate — the share call count stays 0 until confirm is tapped',
    (tester) async {
      final fake = _FakeShareService();
      final useCase = ExportAnalysisUseCase(
        shareService: fake,
        tempDirectory: tempRoot,
      );

      await tester.pumpWidget(_harness(_document(), useCase));
      await tester.pumpAndSettle();
      expect(fake.callCount, 0);

      // The use case writes the redacted export via real dart:io — the
      // default fake test zone never lets that detached Future resolve on
      // its own, so the tap and the wait for its completion both run
      // inside `runAsync`, which uses a real (non-faked) event loop.
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const Key('analysis-export-confirm')));
        for (var i = 0; i < 50 && fake.callCount == 0; i += 1) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pumpAndSettle();

      expect(fake.callCount, 1);
    },
  );

  testWidgets('locale parity — english and hungarian render translated text', (
    tester,
  ) async {
    final fake = _FakeShareService();
    final useCase = ExportAnalysisUseCase(
      shareService: fake,
      tempDirectory: tempRoot,
    );

    await tester.pumpWidget(
      _harness(_document(), useCase, locale: const Locale('en')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Export & share'), findsOneWidget);

    await tester.pumpWidget(
      _harness(_document(), useCase, locale: const Locale('hu')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Exportálás és megosztás'), findsOneWidget);
  });

  testWidgets(
    'overflow matrix — 320px / textScale 2.0 renders without overflow',
    (tester) async {
      final fake = _FakeShareService();
      final useCase = ExportAnalysisUseCase(
        shareService: fake,
        tempDirectory: tempRoot,
      );

      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(_harness(_document(), useCase));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'overflow matrix — 320px / textScale 2.0 (hu) renders without overflow',
    (tester) async {
      final fake = _FakeShareService();
      final useCase = ExportAnalysisUseCase(
        shareService: fake,
        tempDirectory: tempRoot,
      );

      tester.view.physicalSize = const Size(320, 800);
      tester.view.devicePixelRatio = 1.0;
      tester.platformDispatcher.textScaleFactorTestValue = 2.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await tester.pumpWidget(
        _harness(_document(), useCase, locale: const Locale('hu')),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
  );
}
