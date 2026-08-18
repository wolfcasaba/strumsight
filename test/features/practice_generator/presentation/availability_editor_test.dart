import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice_generator/domain/model/weekly_availability.dart';
import 'package:strumsight/features/practice_generator/presentation/widgets/availability_editor.dart';
import 'package:strumsight/l10n/app_localizations.dart';

void main() {
  Future<void> pumpEditor(
    WidgetTester tester, {
    DateTime? referenceDate,
    ValueChanged<List<DailyAvailability>>? onChanged,
  }) => tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: AvailabilityEditor(
            days: const <DailyAvailability>[],
            onChanged: onChanged ?? (_) {},
            referenceDate: referenceDate ?? DateTime.utc(2026, 8, 18),
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

  testWidgets('uses the injected reference date for the current week', (
    tester,
  ) async {
    Future<LocalDate> selectMonday(DateTime referenceDate) async {
      List<DailyAvailability>? selectedDays;
      await pumpEditor(
        tester,
        referenceDate: referenceDate,
        onChanged: (days) => selectedDays = days,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('plan-availability-monday')));

      return selectedDays!.single.date;
    }

    expect(
      await selectMonday(DateTime.utc(2026, 8, 18)),
      LocalDate(2026, 8, 17),
    );
    expect(
      await selectMonday(DateTime.utc(2026, 9, 1)),
      LocalDate(2026, 8, 31),
    );
  });
}
