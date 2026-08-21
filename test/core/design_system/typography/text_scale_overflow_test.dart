import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/design_system/public.dart';

const _shortReference = 'Practice summary';
const _longHungarianTitle =
    'A következő gyakorlatszakasz részletes összefoglalója';

void main() {
  test('long Hungarian fixture retains the required expansion margin', () {
    expect(
      _longHungarianTitle.length,
      greaterThanOrEqualTo((_shortReference.length * 1.3).ceil()),
    );
  });

  for (final textScale in <double>[1, 1.3, 2, 2.5]) {
    testWidgets(
      'long Hungarian title has no render exception at $textScale text scale',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: SsDarkTheme.data(),
            home: MediaQuery(
              data: MediaQueryData(
                size: const Size(320, 800),
                textScaler: TextScaler.linear(textScale),
              ),
              child: Scaffold(
                body: SizedBox(
                  width: 320,
                  child: Builder(
                    builder: (context) => Text(
                      _longHungarianTitle,
                      style: Theme.of(
                        context,
                      ).extension<SsTypography>()!.headlineLarge,
                      softWrap: true,
                    ),
                  ),
                ),
              ),
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        expect(find.text(_longHungarianTitle), findsOneWidget);
        expect(
          tester.getSize(find.text(_longHungarianTitle)).height,
          greaterThan(0),
        );
      },
    );
  }
}
