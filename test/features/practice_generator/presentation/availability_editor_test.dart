import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice_generator/domain/model/weekly_availability.dart';
import 'package:strumsight/features/practice_generator/presentation/widgets/availability_editor.dart';
import 'package:strumsight/l10n/app_localizations.dart';

void main() {
  Future<void> pumpEditor(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: AvailabilityEditor(
            days: const <DailyAvailability>[],
            onChanged: (_) {},
          ),
        ),
      ),
    ),
  );

  testWidgets('remains accessible without overflow at a large text size (A6)', (
    tester,
  ) async {
    await pumpEditor(tester);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('provides semantic labels for day availability controls (A7)', (
    tester,
  ) async {
    await pumpEditor(tester);
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Monday availability'), findsOneWidget);
  });
}
