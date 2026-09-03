import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/gamification/domain/achievements/achievement_definition.dart';
import 'package:strumsight/features/gamification/domain/achievements/achievement_progress.dart';
import 'package:strumsight/features/gamification/presentation/screens/achievement_detail_screen.dart';
import 'package:strumsight/features/gamification/presentation/screens/achievements_screen.dart';
import 'package:strumsight/l10n/app_localizations.dart';

void main() {
  final definitions = <AchievementDefinition>[
    _definition(
      id: 'first_valid_session',
      category: AchievementCategory.practice,
      keyStem: 'achievementFirstValidSession',
    ),
    _definition(
      id: 'practice_starter',
      category: AchievementCategory.practice,
      keyStem: 'achievementPracticeStarter',
    ),
    _definition(
      id: 'balanced_practice_week',
      category: AchievementCategory.consistency,
      keyStem: 'achievementBalancedPracticeWeek',
      hidden: true,
    ),
  ];

  Map<String, AchievementProgress> progress({
    bool completeStarter = true,
    bool completeSecret = false,
  }) => <String, AchievementProgress>{
    'first_valid_session': _progress('first_valid_session', 0.6),
    'practice_starter': _progress(
      'practice_starter',
      1,
      completedAt: completeStarter ? DateTime.utc(2026, 8, 21) : null,
      rewardLedgerEntryId: completeStarter
          ? 'achievement:practice_starter:1'
          : null,
    ),
    'balanced_practice_week': _progress(
      'balanced_practice_week',
      completeSecret ? 1 : 0.4,
      completedAt: completeSecret ? DateTime.utc(2026, 8, 22) : null,
      rewardLedgerEntryId: completeSecret
          ? 'achievement:balanced_practice_week:1'
          : null,
    ),
  };

  group('A1 + A2 — filters and hidden achievements', () {
    testWidgets('filters expose only their permitted achievement sets', (
      tester,
    ) async {
      await _pumpAchievements(
        tester,
        definitions: definitions,
        progress: progress(),
      );

      await _scrollUntilText(tester, 'A secret achievement');
      expect(find.text('A secret achievement'), findsOneWidget);
      await _scrollUntilText(tester, 'First valid session');
      expect(find.text('First valid session'), findsOneWidget);
      await _scrollUntilText(tester, 'Practice starter');
      expect(find.text('Practice starter'), findsOneWidget);

      await _scrollToTop(tester);
      await tester.tap(find.byKey(const Key('achievement-filter-unlocked')));
      await tester.pumpAndSettle();
      await _scrollUntilText(tester, 'Practice starter');
      expect(find.text('Practice starter'), findsOneWidget);
      expect(find.text('First valid session'), findsNothing);
      expect(find.text('A secret achievement'), findsNothing);

      await _scrollToTop(tester);
      await tester.tap(find.byKey(const Key('achievement-filter-in-progress')));
      await tester.pumpAndSettle();
      await _scrollUntilText(tester, 'First valid session');
      expect(find.text('First valid session'), findsOneWidget);
      expect(find.text('Practice starter'), findsNothing);
      expect(find.text('A secret achievement'), findsNothing);

      await tester.tap(
        find.byKey(const Key('achievement-filter-category-consistency')),
      );
      await tester.pumpAndSettle();
      expect(find.text('A secret achievement'), findsNothing);
      expect(find.text('Balanced practice week'), findsNothing);
    });

    testWidgets(
      'locked hidden details never enter the widget or semantics tree',
      (tester) async {
        final handle = tester.ensureSemantics();
        await _pumpAchievements(
          tester,
          definitions: definitions,
          progress: progress(),
        );

        await _scrollUntilText(tester, 'A secret achievement');
        expect(find.text('A secret achievement'), findsOneWidget);
        expect(find.text('Balanced practice week'), findsNothing);
        expect(
          find.text('Complete measured practice, song, and analysis sessions.'),
          findsNothing,
        );
        expect(find.text('40%'), findsNothing);
        expect(
          find.bySemanticsLabel(
            'Achievement: balanced measured practice week.',
          ),
          findsNothing,
        );
        handle.dispose();
      },
    );

    testWidgets(
      'category filters expose real categories but never the audit marker or locked hidden details',
      (tester) async {
        await _pumpAchievements(
          tester,
          definitions: definitions,
          progress: progress(),
        );

        expect(
          find.byKey(const Key('achievement-filter-category-practice')),
          findsOneWidget,
        );
        expect(
          find.byKey(
            const Key('achievement-filter-category-accessibilityNeutral'),
          ),
          findsNothing,
        );

        await tester.tap(
          find.byKey(const Key('achievement-filter-category-consistency')),
        );
        await tester.pumpAndSettle();
        expect(find.text('A secret achievement'), findsNothing);
        expect(find.text('Balanced practice week'), findsNothing);
      },
    );
  });

  testWidgets(
    'A3 — an unlocked tile shows its ready progress and completion date',
    (tester) async {
      await _pumpAchievements(
        tester,
        definitions: definitions,
        progress: progress(),
      );

      await _scrollUntilText(tester, 'Practice starter');
      expect(find.text('Progress: 100%'), findsOneWidget);
      expect(find.textContaining('Unlocked on '), findsOneWidget);
    },
  );

  testWidgets('A2 — locked hidden detail has no private content in semantics', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final hidden = definitions.last;
    await _pumpDetail(
      tester,
      achievementId: hidden.id,
      definitions: <AchievementDefinition>[hidden],
      progressByAchievement: <String, AchievementProgress>{
        hidden.id: _progress(hidden.id, 0.4),
      },
    );

    expect(find.text('A secret achievement'), findsOneWidget);
    expect(find.text('Balanced practice week'), findsNothing);
    expect(
      find.text('Complete measured practice, song, and analysis sessions.'),
      findsNothing,
    );
    expect(find.text('40%'), findsNothing);
    expect(
      find.bySemanticsLabel('Achievement: balanced measured practice week.'),
      findsNothing,
    );
    handle.dispose();
  });

  testWidgets('A4 — detail evidence uses only a closed reason and aggregates', (
    tester,
  ) async {
    await _pumpDetail(
      tester,
      achievementId: 'practice_starter',
      evidence: AchievementEvidence(
        reason: AchievementEvidenceReasonCode.measuredProgress,
        current: 3,
        target: 5,
      ),
    );

    expect(find.text('Measured progress: 3 of 5.'), findsOneWidget);
  });

  test('A4 — evidence rejects invalid aggregate measurements', () {
    final invalidEvidence = <({num current, num target})>[
      (current: double.nan, target: 5),
      (current: double.infinity, target: 5),
      (current: -1, target: 5),
      (current: 1, target: double.nan),
      (current: 1, target: double.infinity),
      (current: 1, target: 0),
    ];

    for (final values in invalidEvidence) {
      expect(
        () => AchievementEvidence(
          reason: AchievementEvidenceReasonCode.measuredProgress,
          current: values.current,
          target: values.target,
        ),
        throwsArgumentError,
      );
    }
  });

  test('A4 — evidence contract is closed to IDs, payloads, and user text', () {
    final sources = <String>[
      'lib/features/gamification/presentation/screens/achievements_screen.dart',
      'lib/features/gamification/presentation/screens/achievement_detail_screen.dart',
      'lib/features/gamification/presentation/widgets/achievement_tile.dart',
    ];
    const forbidden = <String>[
      'AnalyzeResult',
      'TimelineChord',
      'TimelineStrum',
      'waveform',
      'eventId',
      'sessionId',
      'audioPayload',
      'videoPayload',
      'chordTimeline',
      'strumTimeline',
      'confidenceList',
      'userText',
    ];

    for (final source in sources) {
      final content = File(source).readAsStringSync();
      for (final token in forbidden) {
        expect(
          content,
          isNot(contains(token)),
          reason: '$source exposes $token',
        );
      }
    }

    final evidenceSource = File(
      'lib/features/gamification/presentation/screens/achievement_detail_screen.dart',
    ).readAsStringSync();
    final evidenceContract = RegExp(
      r'final class AchievementEvidence \{([\s\S]*?)\n\}',
    ).firstMatch(evidenceSource);
    expect(evidenceContract, isNotNull);
    final fields = evidenceContract!.group(1)!;
    expect(fields, contains('final AchievementEvidenceReasonCode reason;'));
    expect(fields, contains('final num current;'));
    expect(fields, contains('final num target;'));
    expect(fields, isNot(contains('String ')));
    expect(fields, isNot(contains('List<')));
    expect(fields, isNot(contains('Map<')));
    expect(fields, isNot(contains('Object')));
  });

  testWidgets('A5 — a new learner gets a localized empty state', (
    tester,
  ) async {
    await _pumpAchievements(tester, definitions: const [], progress: const {});

    expect(find.text('No achievements yet'), findsOneWidget);
    expect(find.byIcon(Icons.emoji_events_outlined), findsOneWidget);
  });

  testWidgets('A6 — an unknown exact ID shows a safe not-found state', (
    tester,
  ) async {
    await _pumpDetail(tester, achievementId: 'missing_achievement');

    expect(find.text('Achievement not found'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'visible tiles have one button action that returns their exact ID',
    (tester) async {
      String? selectedId;
      final handle = tester.ensureSemantics();
      await _pumpAchievements(
        tester,
        definitions: definitions,
        progress: progress(),
        onAchievementSelected: (id) => selectedId = id,
      );

      await _scrollUntilText(tester, 'First valid session');
      final tile = find.bySemanticsLabel(
        'Achievement: first valid practice session. 60% complete.',
      );
      expect(tile, findsOneWidget);
      expect(
        tester.getSemantics(tile),
        matchesSemantics(
          label: 'Achievement: first valid practice session. 60% complete.',
          isButton: true,
          hasTapAction: true,
        ),
      );
      await tester.tap(tile);
      expect(selectedId, 'first_valid_session');
      handle.dispose();
    },
  );

  group('A7 + A8 — localized, accessible responsive UI', () {
    testWidgets(
      'each real tile exposes one complete localized semantic label',
      (tester) async {
        final handle = tester.ensureSemantics();
        await _pumpAchievements(
          tester,
          definitions: definitions,
          progress: progress(),
        );

        await _scrollUntilText(tester, 'First valid session');
        expect(
          find.bySemanticsLabel(
            'Achievement: first valid practice session. 60% complete.',
          ),
          findsOneWidget,
        );
        expect(
          find.bySemanticsLabel(
            RegExp(
              r'^Achievement: five valid practice sessions\. 100% complete\. '
              r'Unlocked on .+\.$',
            ),
          ),
          findsOneWidget,
        );
        handle.dispose();
      },
    );

    for (final scale in <double>[1.99, 2, 2.01, 3]) {
      testWidgets('$scale text scale remains scrollable and overflow-free', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(320, 568);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await _pumpAchievements(
          tester,
          definitions: definitions,
          progress: progress(),
          textScale: scale,
        );

        expect(find.byType(ListView), findsOneWidget);
        await tester.scrollUntilVisible(find.text('Practice starter'), 120);
        expect(find.text('Practice starter'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('M5 — phone viewport (360x640), textScaler 1.5/2.0/2.5, en+hu', () {
    for (final scale in <double>[1.5, 2.0, 2.5]) {
      for (final locale in <Locale>[const Locale('en'), const Locale('hu')]) {
        testWidgets(
          '$scale / ${locale.languageCode} — list state, no overflow',
          (tester) async {
            tester.view.physicalSize = const Size(360, 640);
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.reset);

            await _pumpAchievements(
              tester,
              definitions: definitions,
              progress: progress(),
              locale: locale,
              textScale: scale,
            );

            expect(find.byType(ListView), findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );

        testWidgets(
          '$scale / ${locale.languageCode} — empty state, no overflow',
          (tester) async {
            tester.view.physicalSize = const Size(360, 640);
            tester.view.devicePixelRatio = 1.0;
            addTearDown(tester.view.reset);

            await _pumpAchievements(
              tester,
              definitions: const <AchievementDefinition>[],
              progress: const <String, AchievementProgress>{},
              locale: locale,
              textScale: scale,
            );

            final emptyIcon = find.byIcon(Icons.emoji_events_outlined);
            await tester.scrollUntilVisible(emptyIcon, 200);
            expect(emptyIcon, findsOneWidget);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });
}

Future<void> _scrollUntilText(WidgetTester tester, String text) =>
    tester.scrollUntilVisible(find.text(text), 160);

Future<void> _scrollToTop(WidgetTester tester) async {
  await tester.drag(find.byType(ListView), const Offset(0, 10000));
  await tester.pumpAndSettle();
}

AchievementDefinition _definition({
  required String id,
  required AchievementCategory category,
  required String keyStem,
  bool hidden = false,
}) => AchievementDefinition(
  id: id,
  category: category,
  titleKey: '${keyStem}Title',
  descriptionKey: '${keyStem}Description',
  accessibilityDescriptionKey: '${keyStem}Semantics',
  objectives: <AchievementObjective>[
    CountAchievementObjective(
      eventKind: AchievementEventKind.practice,
      target: 1,
    ),
  ],
  tierPrerequisiteIds: const [],
  hidden: hidden,
  version: 1,
  deprecated: false,
);

AchievementProgress _progress(
  String achievementId,
  num value, {
  DateTime? completedAt,
  String? rewardLedgerEntryId,
}) => AchievementProgress(
  achievementId: achievementId,
  catalogVersion: 1,
  value: value,
  completedAt: completedAt,
  rewardLedgerEntryId: rewardLedgerEntryId,
);

Future<void> _pumpAchievements(
  WidgetTester tester, {
  required List<AchievementDefinition> definitions,
  required Map<String, AchievementProgress> progress,
  double textScale = 1,
  Locale locale = const Locale('en'),
  ValueChanged<String> onAchievementSelected = _ignoreAchievementSelection,
}) => tester.pumpWidget(
  MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: AchievementsScreen(
        definitions: definitions,
        progressByAchievement: progress,
        onAchievementSelected: onAchievementSelected,
      ),
    ),
  ),
);

void _ignoreAchievementSelection(String _) {}

Future<void> _pumpDetail(
  WidgetTester tester, {
  required String achievementId,
  AchievementEvidence? evidence,
  List<AchievementDefinition>? definitions,
  Map<String, AchievementProgress>? progressByAchievement,
}) => tester.pumpWidget(
  MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: AchievementDetailScreen(
      achievementId: achievementId,
      definitions:
          definitions ??
          <AchievementDefinition>[
            _definition(
              id: 'practice_starter',
              category: AchievementCategory.practice,
              keyStem: 'achievementPracticeStarter',
            ),
          ],
      progressByAchievement:
          progressByAchievement ??
          <String, AchievementProgress>{
            'practice_starter': _progress('practice_starter', 0.6),
          },
      evidence: evidence,
    ),
  ),
);
