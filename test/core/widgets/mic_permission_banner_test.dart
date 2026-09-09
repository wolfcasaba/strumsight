// Audit F1 / A7 — the shared microphone-permission banner has to survive the
// worst layout the app hands it: a 2.0 text scale inside the narrow column of
// a small portrait stage, and the 412-px-high landscape viewport.
//
// MEASURED before the fix (CI run 34289746358,
// `test/features/tuner/tuner_ui_mapping_test.dart` A7): the banner's single
// `Row` — icon + `Expanded` message + a fixed-width `TextButton` —
// overflowed by 167 px on the right at a 258-px width: the button claimed
// its intrinsic width first and squeezed the message into a sliver that
// then grew thousands of pixels tall. The action now sits on its own line.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/widgets/mic_permission_banner.dart';
import 'package:strumsight/l10n/app_localizations.dart';

Future<void> _pumpBanner(
  WidgetTester tester, {
  required Size viewport,
  required double width,
  required double textScale,
}) async {
  tester.view.physicalSize = viewport;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        // The height is the caller's problem (every stage puts the banner in
        // a scrollable header); this cell pins the banner's OWN layout, so it
        // is given a scroll view and a fixed width to fill.
        body: SingleChildScrollView(
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(width: width, child: const MicPermissionBanner()),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('no overflow at textScale 2.0 in a 915x412 landscape viewport', (
    tester,
  ) async {
    await _pumpBanner(
      tester,
      viewport: const Size(915, 412),
      width: 883,
      textScale: 2.0,
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('no overflow at textScale 2.0 in the 258 px column that used to '
      'overflow by 167 px', (tester) async {
    await _pumpBanner(
      tester,
      viewport: const Size(320, 690),
      width: 258,
      textScale: 2.0,
    );

    expect(tester.takeException(), isNull);
  });

  testWidgets('renders the message and the settings action', (tester) async {
    final l10n = lookupAppLocalizations(const Locale('en'));

    await _pumpBanner(
      tester,
      viewport: const Size(412, 915),
      width: 380,
      textScale: 1.0,
    );

    expect(find.text(l10n.micPermissionBody), findsOneWidget);
    expect(
      find.widgetWithText(TextButton, l10n.micPermissionAction),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
