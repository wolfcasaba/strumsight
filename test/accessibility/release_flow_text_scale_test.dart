// E12-R20 accessibility/localization RELEASE AUDIT (brief §1/§3, A1/A2):
// walks the core learning path — boot → onboarding skip → practice hub →
// setup → session → result — end to end, at the mandatory `textScale 2.0`
// (ADR 0383), in BOTH supported locales, on the mandatory phone viewport
// (§0.0.A/R5: the flutter_test default 800x600 is wider AND taller than any
// phone and hides real overflow), and asserts NO RenderFlex overflow and NO
// exception anywhere along the flow. This measures the FLOW, not isolated
// screens (brief §5.1) — Chapter 13 already golden-tested screens one at a
// time; this file is the gate for defects that only show up across a
// navigation sequence (lost state, stale focus, a dynamic string that grows
// mid-flow).
//
// This round audits; it does not fix (brief §0.0/§5.2). Any overflow or
// untranslated string this file finds is a LELET recorded in
// `docs/accessibility/known-exceptions.yaml` and `release-audit.md` — never
// patched in `lib/**` (this round's tilos zona, brief §4).
//
// `test/support/e2e_harness.dart` is out of this round's allowed-files list
// (brief §4), and its own flow helpers (`walkOnboardingViaSkip`,
// `runFirstPracticeSession`) match hardcoded English text — a hu cell driven
// through them would silently no-op on the English literal instead of
// failing on a real translation gap (§0.0.A/R2/R3). This file therefore
// drives its own locale-aware walk, reading every flow string through
// `lookupAppLocalizations(Locale(code))` — the same delegate the app itself
// resolves through `localeProvider` (`lib/core/i18n/locale_provider.dart`).
// `bootE2eApp` / `E2eSession` are still the real, merged E12-R11 harness —
// only the flow-walking helpers below are new.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_state.dart';
import 'package:strumsight/features/practice/presentation/practice_effect_listener.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_hub_screen.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_result_screen.dart'
    show PracticeResultFallback;
import 'package:strumsight/l10n/app_localizations.dart';

import '../support/e2e_harness.dart';

/// §0.0.A/R5 (L558, L452): the flutter_test default viewport (800x600) is
/// wider AND taller than any phone, so "no overflow" measured on it is not
/// evidence. Every cell in this file pumps at this exact phone size.
const _phoneViewport = Size(412, 915);

Future<void> _setPhoneViewport(WidgetTester tester) async {
  tester.view.physicalSize = _phoneViewport;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// §0.0.A/R4: `StrumSightApp`'s root is `MaterialApp.router`
/// (`lib/app/strumsight_app.dart:31`), which installs its OWN
/// `MediaQuery.fromView` — a `MediaQuery` wrapper placed above the pumped
/// tree is inert here (it sits ABOVE the override, not below it). Setting
/// the platform dispatcher's test value before boot is the only path that
/// reaches the tree, mirroring `analysis_compare_screen_test.dart:17` and
/// `practice_result_screen_test.dart:163`.
void _setTextScale(WidgetTester tester, double scale) {
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
}

/// The own, locale-parameterised flow walker (§0.0.A/R2): every string is
/// read from the REAL localization delegate for [locale], so an
/// English-only implementation fails the `hu` cell instead of silently
/// matching nothing (§0.0.A/R3 — the five flow keys measurably differ
/// between `en` and `hu`).
Future<void> _walkCoreFlow(
  WidgetTester tester,
  E2eSession session,
  AppLocalizations l10n,
) async {
  expect(
    find.text(l10n.onboardSkip),
    findsOneWidget,
    reason: 'a fresh install must land on the onboarding welcome carousel',
  );
  await tester.tap(find.text(l10n.onboardSkip));
  await tester.pumpAndSettle();

  session.router.go(AppRoutes.practiceHub);
  await tester.pumpAndSettle();
  expect(find.byType(PracticeHubScreen), findsOneWidget);

  await tester.tap(find.text(l10n.practiceHubQuickStartLabel));
  await tester.pumpAndSettle();

  final setupStart = find.widgetWithText(FilledButton, l10n.practiceSetupStart);
  // Two steps, not one: the Setup form is a lazily-built `ListView`, so the
  // button does not exist in the element tree at all until
  // `scrollUntilVisible` scrolls far enough for the sliver to build it —
  // `ensureVisible` alone throws "No element" on an unbuilt widget. Once
  // built, `scrollUntilVisible`'s fixed 120px increment can still leave the
  // button only PARTIALLY on screen at textScale > 1.0 (center past the
  // 412x915 viewport edge, missing the tap's hit-test), so a final
  // `ensureVisible` (Scrollable.ensureVisible/showOnScreen) centers it
  // exactly regardless of scale.
  await tester.scrollUntilVisible(
    setupStart,
    120,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.ensureVisible(setupStart);
  await tester.pumpAndSettle();
  await tester.tap(setupStart);
  await tester.pumpAndSettle();

  await tester.tap(
    find.widgetWithText(ElevatedButton, l10n.practiceSessionStart),
  );
  await tester.pump();
  await _driveSessionUntil(
    tester,
    session,
    (status) => status == PracticeSessionStatus.running,
  );

  await tester.tap(
    find.widgetWithText(ElevatedButton, l10n.practiceSessionFinish),
  );
  await tester.pump();
  await _driveSessionUntil(
    tester,
    session,
    (status) => status == PracticeSessionStatus.completed,
  );
  await tester.pumpAndSettle();

  // MÉRT (2026-09-01): the router's `AppRoutes.practiceResult` route always
  // builds `PracticeResultFallback`, never `PracticeResultScreen` directly
  // (`lib/app/routing/app_router.dart:346-348`) — the detailed result view
  // is reached only via a `Navigator.push` with an explicit
  // `PracticeHistoryEntry` (from `PracticeHistoryScreen` / the "next step"
  // action), not through this round-trip. `PracticeResultFallback` is the
  // documented, intentional landing state for the `NavigateToResult` effect
  // in this flow shape (practice_result_screen.dart:765-775) — this is the
  // real "eredmény" step the brief's §1 core flow reaches, not a defect.
  expect(
    find.byType(PracticeResultFallback),
    findsOneWidget,
    reason:
        'the NavigateToResult effect (practice_effect_listener.dart) must '
        'land the flow on the result route once the session completes',
  );
}

/// §0.0.A/R7: the only two public levers the private `_driveSessionUntil`
/// in `e2e_harness.dart` also uses — `HarnessClock.tick` and
/// `practiceSessionHostProvider` — bounded by `maxTicks` so a stuck reducer
/// fails loudly instead of hanging the suite (no `pumpAndSettle` on a
/// wall-clock duration).
Future<void> _driveSessionUntil(
  WidgetTester tester,
  E2eSession session,
  bool Function(PracticeSessionStatus status) reached, {
  int maxTicks = 100,
}) async {
  for (var i = 0; i < maxTicks; i++) {
    final host = session.container.read(practiceSessionHostProvider);
    if (host != null && reached(host.state.status)) return;
    await session.clock.tick(tester, const Duration(milliseconds: 200));
  }
  fail(
    'fake_clock ticked $maxTicks times without the practice session '
    'reaching the expected status',
  );
}

/// One captured `FlutterError.onError` report: the short exception message
/// (what a naive capture would keep) plus the `<file>.dart:<line>` of the
/// "relevant error-causing widget" the framework prints in the FULL
/// [FlutterErrorDetails.toString()] — the only place that source location
/// appears; [FlutterErrorDetails.exception] alone never carries it.
typedef _CapturedError = ({String message, String? source});

final _sourceLinePattern = RegExp(r'(\w+\.dart:\d+):\d+');

_CapturedError _captureError(FlutterErrorDetails details) => (
  message: details.exception.toString(),
  source: _sourceLinePattern.firstMatch(details.toString())?.group(1),
);

/// A `lib/**` overflow this round's audit MEASURED but — per brief §0.0/§5.2
/// — must not fix: `lib/**` is this round's tilos zona. Mirrored in
/// `docs/accessibility/known-exceptions.yaml` and
/// `docs/accessibility/release-audit.md`. Matched against BOTH the source
/// location and the exact overflow magnitude, so a regression that grows
/// (or shrinks to zero) at the SAME site still surfaces — this list can only
/// describe today's measured defect, never absorb a different one silently.
///
/// Public (not `_`-prefixed, MAJOR-1 javító kör): [known_exceptions_registry_test]
/// in `release_flow_semantics_test.dart` imports [knownOverflows] to prove
/// every [id] here has a matching `docs/accessibility/known-exceptions.yaml`
/// entry, and that no YAML entry claiming this file as its `source_test`
/// lacks a matching entry here.
final class KnownOverflow {
  const KnownOverflow({
    required this.id,
    required this.locale,
    required this.textScale,
    required this.source,
    required this.overflowPx,
    required this.measuredOn,
  });

  /// The `docs/accessibility/known-exceptions.yaml` entry `id` this
  /// tolerance mirrors.
  final String id;
  final String locale;
  final double textScale;
  final String source;
  final int overflowPx;
  final String measuredOn;

  /// Private (not part of [KnownOverflow]'s public surface, which exists
  /// only so `release_flow_semantics_test.dart` can import [id] for the A6
  /// mirror-coverage guard) — takes the file-private [_CapturedError], so a
  /// public signature would trip `library_private_types_in_public_api`.
  bool _matches(String locale, double textScale, _CapturedError error) =>
      locale == this.locale &&
      textScale == this.textScale &&
      error.source == source &&
      error.message.contains('overflowed by $overflowPx pixels');
}

/// Measured 2026-09-01 on this box (phone viewport 412x915, the core flow
/// driven end to end — brief §6.1's "Egyetlen állapot sincs..." matrix does
/// not name this class, but the §0.0.A/R10 STOP-protokoll does: every
/// overflow this audit finds is a LELET, `lib/**` stays untouched). Both
/// entries are also recorded in `docs/accessibility/known-exceptions.yaml`
/// with owner + lejárat; this list can only SHRINK (a cell that stops
/// overflowing must have its entry removed here — see `_assertFlowCell`).
/// Public: see [KnownOverflow]'s doc comment — the A6 guard cell in
/// `release_flow_semantics_test.dart` imports this list.
const knownOverflows = <KnownOverflow>[
  // `_ScoringProfileReadout` (practice_setup_screen.dart:410-430) puts an
  // un-`Expanded` `Text(profileId)` next to an `Expanded` label in a `Row`
  // — at textScale 2.0 the fixed-width sibling no longer fits. Identical
  // 43px on BOTH locales: the overflow is driven by `profileId` (a
  // non-localised scoring-profile id), not by the label's translation
  // length.
  KnownOverflow(
    id: 'setup-scoring-profile-overflow',
    locale: 'en',
    textScale: 2.0,
    source: 'practice_setup_screen.dart:418',
    overflowPx: 43,
    measuredOn: '2026-09-01',
  ),
  KnownOverflow(
    id: 'setup-scoring-profile-overflow',
    locale: 'hu',
    textScale: 2.0,
    source: 'practice_setup_screen.dart:418',
    overflowPx: 43,
    measuredOn: '2026-09-01',
  ),
  // The combo-count `Row` (practice_feedback.dart:89-101) has neither Text
  // child `Expanded` — hu's longer `practiceFeedbackComboLabel` translation
  // overflows at textScale 2.0 where en's shorter "Combo" does not.
  KnownOverflow(
    id: 'feedback-combo-row-overflow-hu',
    locale: 'hu',
    textScale: 2.0,
    source: 'practice_feedback.dart:89',
    overflowPx: 65,
    measuredOn: '2026-09-01',
  ),
];

/// §0.0.A/R6: overflow/exception detection via `FlutterError.onError`
/// capture (the merged `e13_r36_variant_matrix_test.dart:269-294` pattern)
/// — never a text heuristic on rendered output.
Future<List<_CapturedError>> _runFlowCell(
  WidgetTester tester, {
  required String localeCode,
  required double textScale,
}) async {
  await _setPhoneViewport(tester);
  _setTextScale(tester, textScale);

  final captured = <_CapturedError>[];
  final previousOnError = FlutterError.onError;
  FlutterError.onError = (details) => captured.add(_captureError(details));

  final l10n = lookupAppLocalizations(Locale(localeCode));
  final store = InMemoryKeyValueStore({'ss.settings.locale': localeCode});

  late final E2eSession session;
  try {
    session = await bootE2eApp(tester, store: store, onboardingSeen: false);
    await _walkCoreFlow(tester, session, l10n);
  } finally {
    FlutterError.onError = previousOnError;
  }
  await session.dispose(tester);
  return captured;
}

/// Splits [errors] into unexpected (fails the cell) and expected (a
/// `knownOverflows` entry for this exact cell). Also fails if a listed
/// entry no longer reproduces — a STALE exclusion is exactly as wrong as a
/// silently-added one (mirrors `_excludedByKey`'s `expectOverflow` branch in
/// `e13_r36_variant_matrix_test.dart`).
void _assertFlowCell(
  List<_CapturedError> errors, {
  required String localeCode,
  required double textScale,
}) {
  final applicable = knownOverflows.where(
    (k) => k.locale == localeCode && k.textScale == textScale,
  );
  final unexpected = errors
      .where(
        (e) => !applicable.any((k) => k._matches(localeCode, textScale, e)),
      )
      .toList();
  expect(
    unexpected,
    isEmpty,
    reason:
        'locale=$localeCode textScale=$textScale produced unrecorded '
        'errors: ${unexpected.map((e) => e.message).toList()}',
  );
  for (final known in applicable) {
    expect(
      errors.any((e) => known._matches(localeCode, textScale, e)),
      isTrue,
      reason:
          'STALE known-exception entry (${known.source}, measured '
          '${known.overflowPx}px on ${known.measuredOn}): this cell no '
          'longer overflows — remove the `KnownOverflow` entry AND its '
          'docs/accessibility/known-exceptions.yaml mirror',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A1/A2 + the §6 threshold-cell-triple's two IN-SCOPE points: below the
  // mandatory 2.0 threshold (1.5, must be green) and exactly on it (2.0,
  // the actual release condition, INCLUSIVE). A point ABOVE 2.0 (2.5) is
  // deliberately absent — the brief states it is NOT a requirement and must
  // not be measured here, or a passing 2.5 cell could be misread as
  // evidence for the 2.0 release gate.
  for (final localeCode in ['en', 'hu']) {
    for (final textScale in [1.5, 2.0]) {
      testWidgets(
        'core flow ($localeCode, textScale $textScale) has no overflow and '
        'no exception (A1/A2)',
        (tester) async {
          final errors = await _runFlowCell(
            tester,
            localeCode: localeCode,
            textScale: textScale,
          );
          _assertFlowCell(errors, localeCode: localeCode, textScale: textScale);
        },
      );
    }
  }

  // §6 "Valódi-sértés próba" (KÖTELEZŐ): proves the `textScaleFactorTestValue`
  // switch actually reaches `StrumSightApp`'s tree, through the SAME boot
  // path (`bootE2eApp`) the cells above use. Measured on this box
  // (2026-09-01, phone viewport 412x915, `en` locale, the onboarding
  // "Skip" label): height @1.0 = 20.0px, height @2.0 = 40.0px — a clear,
  // reproducible difference (documented again in
  // `docs/accessibility/release-audit.md` §"Valódi-sértés próba" and the
  // brief §10). If `MaterialApp.router` ignored the platform dispatcher's
  // test value (the R4 hypothetical), both heights would come out
  // IDENTICAL and this assertion would fail — exactly the failure mode the
  // §6.1 mérce-mátrix names.
  testWidgets(
    'the textScale switch measurably changes the booted tree — 2.0 differs '
    'from 1.0 (falsifies R4: textScaler not reaching MaterialApp.router)',
    (tester) async {
      Future<double> skipLabelHeightAt(double scale) async {
        await _setPhoneViewport(tester);
        _setTextScale(tester, scale);
        final store = InMemoryKeyValueStore({'ss.settings.locale': 'en'});
        final session = await bootE2eApp(
          tester,
          store: store,
          onboardingSeen: false,
        );
        final l10n = lookupAppLocalizations(const Locale('en'));
        final height = tester.getSize(find.text(l10n.onboardSkip)).height;
        await session.dispose(tester);
        return height;
      }

      final heightAt1 = await skipLabelHeightAt(1.0);
      final heightAt2 = await skipLabelHeightAt(2.0);

      // ignore: avoid_print
      print(
        'valódi-sértés próba: onboardSkip rendered height '
        '@1.0=${heightAt1}px, @2.0=${heightAt2}px',
      );

      expect(
        heightAt2,
        greaterThan(heightAt1),
        reason:
            'textScale 2.0 must render measurably taller than 1.0 — an '
            'identical height would mean the switch never reached the '
            'app root, and every "no overflow" cell above would be '
            'vacuously green',
      );
    },
  );
}
