import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/themes/ss_dark_theme.dart';
import 'package:strumsight/core/theme/app_theme.dart';
import 'package:strumsight/features/live/engine/mock_strum_engine.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/onboarding/screens/onboarding_screen.dart';
import 'package:strumsight/features/tuner/model/tuner_reading.dart';
import 'package:strumsight/features/tuner/providers/tuner_providers.dart';
import 'package:strumsight/features/tuner/screens/tuner_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/main.dart';

import '../support/fake_engines.dart';
import '../support/preference_store.dart';

const _captureBaseline = bool.fromEnvironment('CAPTURE_UI_BASELINE');
const _baselineScreenshots = <String>[
  'docs/ui/baseline/screenshots/live-compact-portrait.png',
  'docs/ui/baseline/screenshots/tuner-compact-portrait.png',
  'docs/ui/baseline/screenshots/analyze-compact-portrait.png',
  'docs/ui/baseline/screenshots/learn-compact-portrait.png',
  'docs/ui/baseline/screenshots/library-compact-portrait.png',
  'docs/ui/baseline/screenshots/settings-compact-portrait.png',
  'docs/ui/baseline/screenshots/onboarding-compact-portrait.png',
];

const _productionFontAssets = <String, List<String>>{
  'Poppins': <String>[
    'assets/fonts/Poppins-Regular.ttf',
    'assets/fonts/Poppins-Medium.ttf',
    'assets/fonts/Poppins-SemiBold.ttf',
    'assets/fonts/Poppins-Bold.ttf',
    'assets/fonts/Poppins-ExtraBold.ttf',
  ],
  'Montserrat': <String>['assets/fonts/Montserrat.ttf'],
  'MaterialIcons': <String>['fonts/MaterialIcons-Regular.otf'],
};

const _materialRobotoFontFileNames = <String>[
  'Roboto-Regular.ttf',
  'Roboto-Medium.ttf',
  'Roboto-Bold.ttf',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'the exact compact portrait baseline corpus is decodable and non-empty',
    () async {
      expect(_baselineScreenshots, hasLength(7));
      expect(_baselineScreenshots.toSet(), hasLength(7));

      for (final relativePath in _baselineScreenshots) {
        final file = File(relativePath);
        expect(
          await file.exists(),
          isTrue,
          reason: '$relativePath is required',
        );

        final bytes = await file.readAsBytes();
        expect(
          bytes,
          isNotEmpty,
          reason: '$relativePath must contain PNG bytes',
        );

        final ui.Image image = await decodeImageFromList(bytes);
        addTearDown(image.dispose);
        expect(image.width, greaterThan(0), reason: '$relativePath has width');
        expect(
          image.height,
          greaterThan(0),
          reason: '$relativePath has height',
        );
        expect(
          image.width,
          lessThan(image.height),
          reason: '$relativePath must be compact portrait',
        );
      }
    },
    timeout: const Timeout(Duration(seconds: 10)),
    skip: _captureBaseline,
  );

  testWidgets(
    'direct capture wrappers keep the production font, theme, and banner contract',
    (tester) async {
      expect(_productionFontAssets['MaterialIcons'], const <String>[
        'fonts/MaterialIcons-Regular.otf',
      ]);

      await tester.pumpWidget(_directCaptureApp(home: const SizedBox()));

      final captureApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      final productionTheme = AppTheme.dark();
      expect(captureApp.debugShowCheckedModeBanner, isFalse);
      expect(productionTheme.textTheme.bodyLarge?.fontFamily, 'Roboto');
      expect(productionTheme.textTheme.headlineLarge?.fontFamily, 'Montserrat');
      expect(
        captureApp.theme?.textTheme.bodyLarge?.fontFamily,
        productionTheme.textTheme.bodyLarge?.fontFamily,
      );
      expect(
        captureApp.theme?.textTheme.headlineLarge?.fontFamily,
        productionTheme.textTheme.headlineLarge?.fontFamily,
      );

      expect(_materialRobotoFontFileNames, const <String>[
        'Roboto-Regular.ttf',
        'Roboto-Medium.ttf',
        'Roboto-Bold.ttf',
      ]);
      for (final fontFile in _materialRobotoFontFiles()) {
        expect(
          fontFile.existsSync(),
          isTrue,
          reason: '${fontFile.path} must exist in the active Flutter SDK',
        );
      }
    },
  );

  testWidgets(
    'captures the seven fixed production-widget baseline states',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final strumEngine = FakeStrumEngine();
      final tunerEngine = FakeTunerEngine();
      addTearDown(strumEngine.dispose);
      addTearDown(tunerEngine.dispose);
      await tester.runAsync(_loadProductionFonts);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...preferenceOverrides(),
            strumEngineProvider.overrideWithValue(strumEngine),
            tunerEngineProvider.overrideWithValue(tunerEngine),
          ],
          child: const StrumSightApp(),
        ),
      );
      await tester.pumpAndSettle();
      strumEngine.emit(
        MockStrumEngine(bpm: 96).frameAt(const Duration(milliseconds: 300)),
      );
      await tester.pumpAndSettle();
      await _capture(tester, _baselineScreenshots[0]);

      for (final screen in <(String, String)>[
        ('Analyze', _baselineScreenshots[2]),
        ('Learn', _baselineScreenshots[3]),
        ('Library', _baselineScreenshots[4]),
        ('Settings', _baselineScreenshots[5]),
      ]) {
        await tester.tap(find.text(screen.$1).last);
        await tester.pumpAndSettle();
        await _capture(tester, screen.$2);
      }

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ...preferenceOverrides(),
            tunerEngineProvider.overrideWithValue(tunerEngine),
          ],
          child: _directCaptureApp(home: const TunerScreen()),
        ),
      );
      await tester.pumpAndSettle();
      tunerEngine.emit(
        const TunerReading(note: 'A', cents: 0, frequencyHz: 110),
      );
      await tester.pumpAndSettle();
      await _capture(tester, _baselineScreenshots[1]);

      await tester.pumpWidget(const SizedBox());
      await tester.pump();
      await tester.pumpWidget(
        ProviderScope(
          overrides: preferenceOverrides(),
          child: _directCaptureApp(home: const OnboardingScreen()),
        ),
      );
      await tester.pumpAndSettle();
      await _capture(tester, _baselineScreenshots[6]);
    },
    skip: !_captureBaseline,
  );
}

Future<void> _capture(WidgetTester tester, String path) =>
    expectLater(find.byType(MaterialApp), matchesGoldenFile('../../$path'));

Widget _directCaptureApp({required Widget home}) => MaterialApp(
  debugShowCheckedModeBanner: false,
  // MINOR-1 (E15-R11 review): OnboardingScreen's migrated SsButton reads
  // the design-system theme extensions — AppTheme.dark() alone null-check
  // crashes (L593-class defect). SsDarkTheme.data() is AppTheme.dark() plus
  // the Ss extensions merged in, so TunerScreen's capture is unaffected.
  theme: SsDarkTheme.data(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

Future<void> _loadProductionFonts() async {
  for (final entry in _productionFontAssets.entries) {
    final loader = FontLoader(entry.key);
    for (final assetPath in entry.value) {
      loader.addFont(rootBundle.load(assetPath));
    }
    await loader.load();
  }

  final robotoLoader = FontLoader('Roboto');
  for (final fontFile in _materialRobotoFontFiles()) {
    robotoLoader.addFont(fontFile.readAsBytes().then(ByteData.sublistView));
  }
  await robotoLoader.load();
}

List<File> _materialRobotoFontFiles() {
  final materialFontsDirectory = Directory(
    '${_activeFlutterSdkRoot().path}/bin/cache/artifacts/material_fonts',
  );
  return _materialRobotoFontFileNames
      .map((fileName) => File('${materialFontsDirectory.path}/$fileName'))
      .toList(growable: false);
}

Directory _activeFlutterSdkRoot() {
  final resolvedExecutable = File(
    Platform.resolvedExecutable,
  ).resolveSymbolicLinksSync();
  final separator = Platform.pathSeparator;
  final flutterCacheMarker =
      '$separator'
      'bin$separator'
      'cache$separator';
  final markerIndex = resolvedExecutable.indexOf(flutterCacheMarker);
  if (markerIndex == -1) {
    throw StateError(
      'Cannot derive Flutter SDK root from $resolvedExecutable.',
    );
  }
  return Directory(resolvedExecutable.substring(0, markerIndex));
}
