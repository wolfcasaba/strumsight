// E12-R20 accessibility/localization RELEASE AUDIT (brief §1/§3, A3/A4):
// walks the SAME core flow as `release_flow_text_scale_test.dart` — boot →
// onboarding skip → practice hub → setup → session → result — and asserts
// screen-reader reachability and focus order using the ACTUAL simulated
// accessibility traversal (`tester.semantics.simulatedAccessibilityTraversal`),
// never a single `find.bySemanticsLabel` presence check
// (§0.0.A/R9/docs/LESSONS.md L460): a presence-only guard cannot tell
// whether an element is reachable in a sensible order, only that a label
// exists somewhere in the tree.
//
// This round audits; it does not fix (brief §0.0/§5.2). Any missing label
// or scrambled order this file finds is a LELET recorded in
// `docs/accessibility/known-exceptions.yaml` and `release-audit.md` — never
// patched in `lib/**` (this round's tilos zona, brief §4).
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/features/practice/domain/model/practice_session_state.dart';
import 'package:strumsight/features/practice/presentation/practice_effect_listener.dart';
import 'package:strumsight/features/practice/presentation/screens/practice_result_screen.dart'
    show PracticeResultFallback;
import 'package:strumsight/l10n/app_localizations.dart';

import '../support/e2e_harness.dart';
// MAJOR-1 javító kör: the A6 guard cell below cross-checks BOTH test files'
// known-exception tolerance mirrors against `known-exceptions.yaml` in one
// place, so it imports the text-scale file's public `knownOverflows` list
// (this file's own tolerance, [switchRowSplitUnlabeledCount] below, needs no
// import). `main()`'s import of this file does not execute
// `release_flow_text_scale_test.dart`'s own `main()` — only its top-level
// declarations are visible.
import 'release_flow_text_scale_test.dart' as text_scale;

/// §0.0.A/R5: the same mandatory phone viewport as the text-scale file —
/// the default flutter_test 800x600 is not evidence of anything here either.
const _phoneViewport = Size(412, 915);

Future<void> _setPhoneViewport(WidgetTester tester) async {
  tester.view.physicalSize = _phoneViewport;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

/// Drives the session from `running` to `completed` and asserts the
/// `NavigateToResult` effect lands the flow on the result route — shared
/// by both locale cells in `main()` below.
///
/// MÉRT (2026-09-01): the router's `AppRoutes.practiceResult` route always
/// builds `PracticeResultFallback`, never `PracticeResultScreen` directly
/// (`lib/app/routing/app_router.dart:346-348`) — the detailed result view
/// is reached only via a `Navigator.push` with an explicit
/// `PracticeHistoryEntry`, not through this round-trip. This is the
/// documented, intentional landing state (practice_result_screen.dart:
/// 765-775), not a defect.
Future<void> _finishToResult(
  WidgetTester tester,
  E2eSession session,
  AppLocalizations l10n,
) async {
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
  expect(find.byType(PracticeResultFallback), findsOneWidget);
}

/// The `docs/accessibility/known-exceptions.yaml` entry `id` this file's
/// `knownUnlabeledCount` tolerance (below, at the practice-setup traversal
/// cell) mirrors. Public (not `_`-prefixed), MAJOR-1 javító kör: the A6
/// guard cell later in this file cross-checks this id against the YAML
/// registry, and the count itself is passed to the call site instead of a
/// bare literal so the two cannot silently drift apart.
const switchRowSplitSemanticsId = 'switch-row-split-semantics-node';
const switchRowSplitUnlabeledCount = 3;

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

/// A3 helper: every node the simulated traversal actually reaches that
/// carries a tap action must expose a non-empty label — the traversal
/// itself is the reachability proof (§0.0.A/R9), not a separate finder call.
///
/// [knownUnlabeledCount] tolerates an EXACT, already-measured, dated count
/// of unlabeled-but-tappable nodes on [screen] (mirrored in
/// `docs/accessibility/known-exceptions.yaml`) — `lib/**` is this round's
/// tilos zona (brief §4), so a real `lib/**` defect this audit finds cannot
/// be fixed here. The count is exact, not a ceiling: if it no longer
/// matches (fixed, or a NEW unlabeled node appeared), this fails loudly
/// instead of silently tolerating a changed shape — the same "can only
/// shrink" discipline as `_excludedByKey` in
/// `e13_r36_variant_matrix_test.dart`.
void _expectEveryTappableNodeIsLabeled(
  Iterable<SemanticsNode> traversal, {
  required String screen,
  int knownUnlabeledCount = 0,
  bool requireAtLeastOneTappable = true,
}) {
  final tappable = traversal
      .where((node) => node.getSemanticsData().hasAction(SemanticsAction.tap))
      .toList();
  if (requireAtLeastOneTappable) {
    expect(
      tappable,
      isNotEmpty,
      reason: '$screen: the traversal found no tappable node at all',
    );
  }
  final unlabeled = tappable
      .where((node) => node.getSemanticsData().label.isEmpty)
      .toList();
  expect(
    unlabeled.length,
    knownUnlabeledCount,
    reason:
        '$screen: expected exactly $knownUnlabeledCount known-unlabeled '
        'tappable node(s) per docs/accessibility/known-exceptions.yaml, '
        'found ${unlabeled.length}: a screen-reader user landing on one of '
        'these hears nothing ($unlabeled)',
  );
}

// ---------------------------------------------------------------------------
// MAJOR-1 javító kör (E12-R20 review): the A6 acceptance criterion — "every
// found exception has an owner + expiry, evidenced by the file + its test
// cell" — previously had no cell that actually opened
// `docs/accessibility/known-exceptions.yaml`. The reader below does, and is
// FAIL-CLOSED (docs/LESSONS.md L566): an unparsable line, an unknown key, a
// missing `exceptions:` block, or a missing/unreadable file all throw —
// never "found nothing, so the registry must be empty and clean". There is
// no `package:yaml` dependency on this tree (measured in E12-R19), so this
// is a hand-rolled reader scoped to exactly this document's own restricted
// shape, mirroring `tool/check_data_inventory.dart`'s `DataInventory.parse`.
// ---------------------------------------------------------------------------

/// One `- id: ...` entry parsed from `docs/accessibility/known-exceptions.yaml`.
final class _KnownExceptionEntry {
  const _KnownExceptionEntry({
    required this.id,
    required this.owner,
    required this.expiry,
    required this.reviewBy,
    required this.severity,
    required this.file,
    required this.measuredOn,
    required this.sourceTest,
    required this.line,
  });

  final String id;
  final String owner;
  final String expiry;

  /// Non-null only when `expiry: unscheduled` — a dated commitment to
  /// re-review, required by the expiry rule below.
  final String? reviewBy;
  final String severity;
  final String file;
  final String measuredOn;
  final String sourceTest;

  /// 1-based line of the entry's `- id:` line — for error messages only.
  final int line;
}

final class _KnownExceptionsParseError implements Exception {
  const _KnownExceptionsParseError(this.message);
  final String message;
  @override
  String toString() => message;
}

const _knownExceptionsPath = 'docs/accessibility/known-exceptions.yaml';

/// Every key this document's restricted YAML subset is allowed to use.
/// A key outside this set is a parse failure, not a silently-ignored line —
/// the fail-closed discipline this file's whole existence is about.
const _knownExceptionEntryKeys = {
  'owner',
  'expiry',
  'review_by',
  'severity',
  'file',
  'widget',
  'measured_on',
  'measured_overflow_px',
  'locales',
  'text_scale',
  'viewport',
  'description',
  'affected_instances_in_flow',
  'instance_labels_en',
  'likely_fix_direction',
  'source_test',
  'status',
};

final _dateLikePattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');
final _roundIdLikePattern = RegExp(r'^E\d+-R\d+$', caseSensitive: false);
final _entryStartPattern = RegExp(r'^  - id:\s*(.*)$');
final _entryKvPattern = RegExp(r'^    (\w+):\s?(.*)$');

String _unquote(String value) {
  final trimmed = value.trim();
  if (trimmed.length >= 2 && trimmed.startsWith('"') && trimmed.endsWith('"')) {
    return trimmed.substring(1, trimmed.length - 1);
  }
  return trimmed;
}

/// Parses [lines] (the raw contents of `known-exceptions.yaml`) into
/// entries, enforcing the A6 field-completeness rule AND the expiry rule
/// inline — a caller that receives a return value at all has already had
/// both enforced for every entry.
///
/// Field completeness: every entry must carry a non-empty `id`, `owner`,
/// `expiry`, `severity`, `file`, `measured_on`, `source_test`.
///
/// Expiry: must be a concrete commitment — a date (`YYYY-MM-DD`), a named
/// round id (`E<n>-R<n>`), or the literal `unscheduled` PLUS a dated
/// `review_by:` — a `expiry: unscheduled` with no `review_by` is exactly the
/// "no lejárat" state the round-brief §6.1 matrix names as the A6 failure
/// mode, so it throws rather than passing silently.
List<_KnownExceptionEntry> _parseKnownExceptions(List<String> lines) {
  final entries = <_KnownExceptionEntry>[];
  var sawExceptionsHeader = false;
  var inFoldedBlock = false;

  String? id, owner, expiry, reviewBy, severity, file, measuredOn, sourceTest;
  var entryLine = 0;

  void flush() {
    if (id == null) return;
    final missing = <String>[];
    if ((owner ?? '').trim().isEmpty) missing.add('owner');
    if ((expiry ?? '').trim().isEmpty) missing.add('expiry');
    if ((severity ?? '').trim().isEmpty) missing.add('severity');
    if ((file ?? '').trim().isEmpty) missing.add('file');
    if ((measuredOn ?? '').trim().isEmpty) missing.add('measured_on');
    if ((sourceTest ?? '').trim().isEmpty) missing.add('source_test');
    if (missing.isNotEmpty) {
      throw _KnownExceptionsParseError(
        '$_knownExceptionsPath entry "$id" (line $entryLine) is missing '
        'required field(s): ${missing.join(', ')}',
      );
    }
    final normalizedExpiry = expiry!.trim();
    final normalizedReviewBy = reviewBy?.trim();
    if (normalizedExpiry == 'unscheduled') {
      if (normalizedReviewBy == null ||
          !_dateLikePattern.hasMatch(normalizedReviewBy)) {
        throw _KnownExceptionsParseError(
          '$_knownExceptionsPath entry "$id" (line $entryLine) has '
          'expiry: unscheduled but no dated review_by (YYYY-MM-DD) — an '
          'unscheduled exception with no review date never actually '
          'expires, which is the A6 failure mode the round brief names',
        );
      }
    } else if (!_dateLikePattern.hasMatch(normalizedExpiry) &&
        !_roundIdLikePattern.hasMatch(normalizedExpiry)) {
      throw _KnownExceptionsParseError(
        '$_knownExceptionsPath entry "$id" (line $entryLine) has expiry '
        '"$normalizedExpiry", which is neither a date (YYYY-MM-DD), a '
        'round id (e.g. E13-R05), nor "unscheduled" with a review_by',
      );
    }
    entries.add(
      _KnownExceptionEntry(
        id: id!,
        owner: owner!,
        expiry: normalizedExpiry,
        reviewBy: normalizedReviewBy,
        severity: severity!,
        file: file!,
        measuredOn: measuredOn!,
        sourceTest: sourceTest!,
        line: entryLine,
      ),
    );
    id = owner = expiry = reviewBy = severity = file = measuredOn = sourceTest =
        null;
  }

  for (var i = 0; i < lines.length; i++) {
    final raw = lines[i];
    final lineNo = i + 1;
    if (raw.trim().isEmpty || raw.trimLeft().startsWith('#')) {
      inFoldedBlock = false;
      continue;
    }

    final indent = raw.length - raw.trimLeft().length;

    if (inFoldedBlock) {
      // A folded scalar (`key: >`) block's continuation lines are indented
      // deeper than the `key:` line that opened it (6+ spaces here) — still
      // part of the value, not a new key, so skip without re-parsing.
      if (indent >= 6) continue;
      inFoldedBlock = false;
    }

    if (indent == 0) {
      final trimmed = raw.trim();
      if (trimmed == 'exceptions:') {
        sawExceptionsHeader = true;
        continue;
      }
      if (trimmed.startsWith('schema_version:')) continue;
      throw _KnownExceptionsParseError(
        '$_knownExceptionsPath:$lineNo unrecognized top-level line: $raw',
      );
    }

    final entryStart = indent == 2 ? _entryStartPattern.firstMatch(raw) : null;
    if (entryStart != null) {
      flush();
      id = _unquote(entryStart.group(1)!);
      entryLine = lineNo;
      continue;
    }

    if (indent == 4) {
      final kv = _entryKvPattern.firstMatch(raw);
      if (kv == null) {
        throw _KnownExceptionsParseError(
          '$_knownExceptionsPath:$lineNo unrecognized entry line: $raw',
        );
      }
      final key = kv.group(1)!;
      if (!_knownExceptionEntryKeys.contains(key)) {
        throw _KnownExceptionsParseError(
          '$_knownExceptionsPath:$lineNo unknown key "$key"',
        );
      }
      final rawValue = kv.group(2)!;
      if (rawValue.trim() == '>') {
        inFoldedBlock = true;
        continue;
      }
      final value = _unquote(rawValue);
      switch (key) {
        case 'owner':
          owner = value;
        case 'expiry':
          expiry = value;
        case 'review_by':
          reviewBy = value;
        case 'severity':
          severity = value;
        case 'file':
          file = value;
        case 'measured_on':
          measuredOn = value;
        case 'source_test':
          sourceTest = value;
        default:
          break; // known but unused for the A6 cross-check (widget, locales, …)
      }
      continue;
    }

    throw _KnownExceptionsParseError(
      '$_knownExceptionsPath:$lineNo unexpected indentation: $raw',
    );
  }
  flush();

  if (!sawExceptionsHeader) {
    throw _KnownExceptionsParseError(
      '$_knownExceptionsPath has no "exceptions:" block',
    );
  }
  return List.unmodifiable(entries);
}

/// The two test files a `source_test` value is allowed to name — anything
/// else (a typo, a third file) is itself a parse-level failure of the
/// mirror contract, not a silently-ignored entry.
const _textScaleTestFile = 'release_flow_text_scale_test.dart';
const _semanticsTestFile = 'release_flow_semantics_test.dart';

/// The A6 bidirectional-mirror check (review MAJOR-1, point 3): the YAML
/// `id` set and the two test files' tolerance mirrors
/// ([text_scale.knownOverflows] + [switchRowSplitSemanticsId]) must cover
/// each other exactly — no YAML entry without a matching mirror, and no
/// mirror tolerance without a matching YAML entry. An EMPTY YAML registry is
/// legal (every defect eventually fixed); an orphan mirror tolerance with no
/// YAML backing is not — see the two `orphan*` checks below, which apply
/// regardless of whether [entries] is empty.
void _checkMirrorCoverage(List<_KnownExceptionEntry> entries) {
  final yamlIds = entries.map((e) => e.id).toList();
  expect(
    yamlIds.toSet().length,
    yamlIds.length,
    reason: '$_knownExceptionsPath has duplicate id(s): $yamlIds',
  );
  final yamlIdSet = yamlIds.toSet();

  final overflowIds = text_scale.knownOverflows.map((k) => k.id).toSet();
  const unlabeledIds = {switchRowSplitSemanticsId};

  for (final entry in entries) {
    final governsOverflow = entry.sourceTest.contains(_textScaleTestFile);
    final governsUnlabeled = entry.sourceTest.contains(_semanticsTestFile);
    expect(
      governsOverflow ^ governsUnlabeled,
      isTrue,
      reason:
          '$_knownExceptionsPath entry "${entry.id}" (line ${entry.line}) '
          'source_test "${entry.sourceTest}" must name exactly one of '
          '$_textScaleTestFile / $_semanticsTestFile',
    );
    if (governsOverflow) {
      expect(
        overflowIds.contains(entry.id),
        isTrue,
        reason:
            '$_knownExceptionsPath entry "${entry.id}" (line ${entry.line}) '
            'claims $_textScaleTestFile as its source_test, but no '
            'KnownOverflow entry in that file carries this id — orphan '
            'YAML entry with no test-side tolerance',
      );
    } else {
      expect(
        unlabeledIds.contains(entry.id),
        isTrue,
        reason:
            '$_knownExceptionsPath entry "${entry.id}" (line ${entry.line}) '
            'claims $_semanticsTestFile as its source_test, but no '
            'known-unlabeled tolerance in that file carries this id — '
            'orphan YAML entry with no test-side tolerance',
      );
    }
  }

  final orphanOverflowIds = overflowIds.difference(yamlIdSet);
  expect(
    orphanOverflowIds,
    isEmpty,
    reason:
        '$_textScaleTestFile\'s knownOverflows references id(s) with no '
        '$_knownExceptionsPath entry: $orphanOverflowIds — an undocumented '
        'tolerance is not a valid state',
  );
  final orphanUnlabeledIds = unlabeledIds.difference(yamlIdSet);
  expect(
    orphanUnlabeledIds,
    isEmpty,
    reason:
        '$_semanticsTestFile\'s known-unlabeled tolerance references id(s) '
        'with no $_knownExceptionsPath entry: $orphanUnlabeledIds',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final localeCode in ['en', 'hu']) {
    testWidgets(
      'core flow ($localeCode): every screen up to the running session '
      'exposes a reachable, labeled traversal (A3)',
      (tester) async {
        await _setPhoneViewport(tester);
        final l10n = lookupAppLocalizations(Locale(localeCode));
        final store = InMemoryKeyValueStore({'ss.settings.locale': localeCode});
        final handle = tester.ensureSemantics();
        final session = await bootE2eApp(
          tester,
          store: store,
          onboardingSeen: false,
        );

        _expectEveryTappableNodeIsLabeled(
          tester.semantics.simulatedAccessibilityTraversal(),
          screen: 'onboarding ($localeCode)',
        );

        await tester.tap(find.text(l10n.onboardSkip));
        await tester.pumpAndSettle();
        session.router.go(AppRoutes.practiceHub);
        await tester.pumpAndSettle();

        _expectEveryTappableNodeIsLabeled(
          tester.semantics.simulatedAccessibilityTraversal(),
          screen: 'practice hub ($localeCode)',
        );

        await tester.tap(find.text(l10n.practiceHubQuickStartLabel));
        await tester.pumpAndSettle();

        // MÉRT (2026-09-01): `SsSwitchRow` (lib/core/design_system/
        // components/inputs/ss_switch_row.dart) splits into TWO adjacent
        // traversal stops instead of one — the outer `InkWell`'s own
        // tap-semantics node (the FULL-row, 48dp-tall touch target §5.4
        // requires) carries NO label, while the inner `MergeSemantics` node
        // carries the label ("Metronome"/"Accent on count 1"/"Show chord
        // hint") but no tap action. A screen-reader user landing on the
        // silent outer node hears nothing before double-tapping it — a real
        // `lib/**` defect (LELET, docs/accessibility/known-exceptions.yaml)
        // this round cannot fix (brief §4). Exactly 3 — the Metronome,
        // Accent and Chord-hint switches this screen renders (chord hint is
        // absent only for `rhythmOnly`, not this flow's `strumPattern`
        // fixture) — in BOTH locales.
        _expectEveryTappableNodeIsLabeled(
          tester.semantics.simulatedAccessibilityTraversal(),
          screen: 'practice setup ($localeCode)',
          knownUnlabeledCount: switchRowSplitUnlabeledCount,
        );

        final setupStart = find.widgetWithText(
          FilledButton,
          l10n.practiceSetupStart,
        );
        // Two steps, not one: the Setup form is a lazily-built `ListView`,
        // so the button does not exist in the element tree until
        // `scrollUntilVisible` scrolls far enough for the sliver to build
        // it; `ensureVisible` then centers it precisely before the tap —
        // see the identical comment in `release_flow_text_scale_test.dart`.
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

        final runningTraversal = tester.semantics
            .simulatedAccessibilityTraversal()
            .toList();
        _expectEveryTappableNodeIsLabeled(
          runningTraversal,
          screen: 'practice session, running ($localeCode)',
        );
        // A3 "meaningful focus order": at `running` `PracticeControls`
        // (lib/features/practice/presentation/widgets/practice_controls.dart)
        // adds exactly Pause, Finish, Exit, in that order — the traversal
        // must present them in that same reading order, not merely contain
        // all three labels somewhere.
        expect(
          runningTraversal,
          containsAllInOrder(<Matcher>[
            isSemantics(
              label: l10n.practiceSessionPause,
              isButton: true,
              hasTapAction: true,
            ),
            isSemantics(
              label: l10n.practiceSessionFinish,
              isButton: true,
              hasTapAction: true,
            ),
            isSemantics(
              label: l10n.practiceSessionExit,
              isButton: true,
              hasTapAction: true,
            ),
          ]),
          reason:
              '$localeCode: Pause -> Finish -> Exit must appear in that '
              'reading order in the simulated traversal',
        );

        // A4: `PracticeReadinessRow` (practice_readiness_row.dart:5-11,
        // built into the session screen at practice_session_screen.dart:233)
        // renders its weak-signal/degraded-capability state as an icon
        // colour AND a `_ReadinessChip.label` on the SAME semantics node
        // ("status is never conveyed by colour alone", its own doc
        // comment) — the traversal must expose one of the two localised
        // texts for each indicator, proving the state reads as text.
        final readinessLabels = <String>{
          l10n.practiceSessionReadinessWeakSignal,
          l10n.practiceSessionReadinessSignalOk,
          l10n.practiceSessionReadinessDegraded,
          l10n.practiceSessionReadinessCapabilityOk,
        };
        expect(
          runningTraversal.any(
            (node) => readinessLabels.contains(node.getSemanticsData().label),
          ),
          isTrue,
          reason:
              '$localeCode: the session readiness row must expose its '
              'weak-signal/degraded-capability state as one of '
              '$readinessLabels, not colour alone',
        );

        await _finishToResult(tester, session, l10n);

        final resultTraversal = tester.semantics
            .simulatedAccessibilityTraversal()
            .toList();
        // `PracticeResultFallback` (practice_result_screen.dart:776-815) is
        // a static icon+title+body message with NO interactive control at
        // all — `requireAtLeastOneTappable: false` reflects that measured
        // fact rather than masking a real gap; the unlabeled-count check
        // below still runs (trivially 0/0) so a FUTURE unlabeled control
        // added to this screen would still be caught.
        _expectEveryTappableNodeIsLabeled(
          resultTraversal,
          screen: 'practice result fallback ($localeCode)',
          requireAtLeastOneTappable: false,
        );

        await session.dispose(tester);
        handle.dispose();
      },
    );
  }

  // A6 (review MAJOR-1 fix): a machine guard on
  // `docs/accessibility/known-exceptions.yaml` — see the fail-closed reader
  // and `_checkMirrorCoverage` defined above `main()`. `test` (not
  // `testWidgets`) is deliberate — no widget tree is pumped, only the file
  // is read and cross-checked.
  group('A6 — known-exceptions.yaml is a machine-checked registry', () {
    test('the registry parses cleanly under the fail-closed reader — every '
        'entry has a non-empty id/owner/expiry/severity/file/measured_on/'
        'source_test, and an unscheduled expiry carries a dated review_by', () {
      final entries = _parseKnownExceptions(
        File(_knownExceptionsPath).readAsLinesSync(),
      );
      // If parsing reached this line, every entry already satisfied both
      // rules above — `_parseKnownExceptions` throws otherwise. This
      // assertion just proves the call actually ran (not vacuously
      // skipped) and records the measured entry count for the log.
      expect(entries, everyElement(isA<_KnownExceptionEntry>()));
    });

    test('every entry is mirrored by exactly one test file\'s tolerance, and '
        'neither test file tolerates an id the registry does not declare', () {
      final entries = _parseKnownExceptions(
        File(_knownExceptionsPath).readAsLinesSync(),
      );
      _checkMirrorCoverage(entries);
    });
  });
}
