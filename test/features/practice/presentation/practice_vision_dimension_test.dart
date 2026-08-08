import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice/presentation/widgets/practice_vision_dimension.dart';
import 'package:strumsight/features/vision/public.dart';
import 'package:strumsight/l10n/app_localizations.dart';
import 'package:strumsight/l10n/app_localizations_en.dart';

void main() {
  Future<void> pump(WidgetTester tester, VisionPracticeQuality quality) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: PracticeVisionDimension(quality: quality),
      ),
    );
    await tester.pump();
  }

  final l10n = AppLocalizationsEn();

  testWidgets('unavailable vision renders no summary dimension', (
    tester,
  ) async {
    await pump(tester, VisionPracticeQuality.unavailable);

    expect(find.text(l10n.practiceVisionDimensionTitle), findsNothing);
  });

  testWidgets(
    'degraded vision renders partial observation and setup guidance',
    (tester) async {
      await pump(tester, VisionPracticeQuality.degraded);

      expect(find.text(l10n.practiceVisionDimensionTitle), findsOneWidget);
      expect(find.text(l10n.practiceVisionDimensionDegraded), findsOneWidget);
    },
  );

  testWidgets('good vision renders a complete observation', (tester) async {
    await pump(tester, VisionPracticeQuality.good);

    expect(find.text(l10n.practiceVisionDimensionTitle), findsOneWidget);
    expect(find.text(l10n.practiceVisionDimensionGood), findsOneWidget);
  });
}
