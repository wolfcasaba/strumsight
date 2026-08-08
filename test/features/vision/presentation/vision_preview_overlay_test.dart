import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/camera/camera_coordinate_space.dart';
import 'package:strumsight/core/camera/preview_fit.dart';
import 'package:strumsight/features/vision/application/calibration_loss_machine.dart';
import 'package:strumsight/features/vision/application/vision_session_state.dart';
import 'package:strumsight/features/vision/domain/feedback/insight_code.dart';
import 'package:strumsight/features/vision/domain/quality/vision_frame_quality.dart';
import 'package:strumsight/features/vision/presentation/overlays/vision_preview_overlay.dart';
import 'package:strumsight/l10n/app_localizations.dart';

const _quality = VisionOverlayQuality(
  hand: VisionMetricState.good,
  pose: VisionMetricState.needsImprovement,
  guitar: CalibrationLossState.tracking,
);

final _cue = VisionInsight(
  code: InsightCode.pickingFocus,
  policyVersion: 'test',
  evidenceIds: const <String>['evidence-1'],
  confidence: 0.9,
);

Widget _host(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

Future<void> _pumpOverlay(
  WidgetTester tester, {
  required Size size,
  required bool detailed,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    _host(
      VisionPreviewOverlay(
        quality: _quality,
        realtimeCue: _cue,
        detailedOverlayEnabled: detailed,
        imageSize: const UprightSize(width: 4, height: 3),
        fitMode: PreviewFitMode.fit,
        debugLandmarks: const <NormalizedPoint>[
          NormalizedPoint(0, 0),
          NormalizedPoint(1, 1),
        ],
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// Golden pixels differ across host CPU/font stacks. These remain an explicit
// local visual-regression tool, matching the existing project golden policy.
final _skipGoldens = Platform.environment['GOLDENS'] != '1';

void main() {
  testWidgets('renders exactly the R23-selected cue and quality chips', (
    tester,
  ) async {
    await _pumpOverlay(tester, size: const Size(360, 640), detailed: false);

    expect(find.byKey(const Key('vision-quality-hand')), findsOneWidget);
    expect(find.byKey(const Key('vision-quality-pose')), findsOneWidget);
    expect(find.byKey(const Key('vision-quality-guitar')), findsOneWidget);
    expect(find.byKey(const Key('vision-realtime-cue')), findsOneWidget);
    expect(find.text('Keep the picking pattern consistent.'), findsOneWidget);
    expect(find.byKey(const Key('vision-preview-skeleton')), findsNothing);
  });

  testWidgets('detailed landmarks are opt-in only', (tester) async {
    await _pumpOverlay(tester, size: const Size(360, 640), detailed: true);

    expect(find.byKey(const Key('vision-preview-skeleton')), findsOneWidget);
  });

  test('uses R07 PreviewFit mapping without widget correction', () {
    final portrait = PreviewFit(
      imageSize: const UprightSize(width: 4, height: 3),
      viewport: const PreviewRect(left: 0, top: 0, width: 360, height: 640),
      mode: PreviewFitMode.fit,
    );
    final landscape = PreviewFit(
      imageSize: const UprightSize(width: 4, height: 3),
      viewport: const PreviewRect(left: 0, top: 0, width: 640, height: 360),
      mode: PreviewFitMode.fit,
    );

    expect(
      VisionPreviewOverlay.mapLandmark(
        point: const NormalizedPoint(0.25, 0.75),
        fit: portrait,
        mirrorPreview: false,
      ),
      const Offset(90, 387.5),
    );
    expect(
      VisionPreviewOverlay.mapLandmark(
        point: const NormalizedPoint(0.25, 0.75),
        fit: landscape,
        mirrorPreview: false,
      ),
      const Offset(200, 270),
    );
  });

  testWidgets('portrait overlay golden', (tester) async {
    await _pumpOverlay(tester, size: const Size(360, 640), detailed: true);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/vision_preview_portrait.png'),
    );
  }, skip: _skipGoldens);

  testWidgets('landscape overlay golden', (tester) async {
    await _pumpOverlay(tester, size: const Size(640, 360), detailed: true);
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/vision_preview_landscape.png'),
    );
  }, skip: _skipGoldens);
}
