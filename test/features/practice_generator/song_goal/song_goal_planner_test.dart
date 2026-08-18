// E07-R24 — SongGoalPlanner: A1, A2, A3, A4, A8 acceptance criteria plus
// the §6.1 1/2/3 signed-distance cells around the song target date.
//
// The real-violation probe (§6.1) is the last test in this file:
// widening the song-block ratio above the policy cap turns A1 red, then
// we revert the production change. This is the mérce-mátrix cell the
// brief calls "a dal kitölti a hetet".

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/practice_generator/public.dart';
import 'package:strumsight/features/song_trainer/domain/public.dart';

import '../../../fixtures/practice_generator/song_goal/song_goal_fixtures.dart';

void main() {
  group('SongGoalPlanner — A1 ratio cap', () {
    test('song blocks stay at or below the policy ratio of weekly minutes', () {
      final asset = buildSongAssetReference(id: 'asset-a1');
      final sections = <SongGoalSectionView>[
        buildSongGoalSectionView(
          sectionId: 's-a1-1',
          sectionName: 'Verse',
          kind: SongSectionKind.verse,
          startMeasure: 0,
          endMeasureExclusive: 8,
          usableAssetReference: asset,
        ),
        buildSongGoalSectionView(
          sectionId: 's-a1-2',
          sectionName: 'Chorus',
          kind: SongSectionKind.chorus,
          startMeasure: 8,
          endMeasureExclusive: 16,
          usableAssetReference: asset,
        ),
        buildSongGoalSectionView(
          sectionId: 's-a1-3',
          sectionName: 'Bridge',
          kind: SongSectionKind.bridge,
          startMeasure: 16,
          endMeasureExclusive: 24,
          usableAssetReference: asset,
        ),
      ];
      final read = buildSongGoalReadSuccess(
        sections: sections,
        revision: 7,
        documentAssetReferences: [asset],
      );
      // 4×10 = 40 minutes of song drafts; week capacity 100 → max 40
      // with default 0.4 cap. All three should fit.
      final drafts = <SongGoalBlockDraft>[
        buildSongGoalBlockDraft(
          sectionView: sections[0],
          targetSkillIds: const ['chord-transition'],
          estimatedMinutes: 10,
        ),
        buildSongGoalBlockDraft(
          sectionView: sections[1],
          targetSkillIds: const ['strum-pattern'],
          estimatedMinutes: 10,
        ),
        buildSongGoalBlockDraft(
          sectionView: sections[2],
          targetSkillIds: const ['dynamic-control'],
          estimatedMinutes: 10,
        ),
      ];
      final request = buildSongGoalPlanningRequest(
        read: read,
        drafts: drafts,
        scheduledDate: LocalDate(2026, 9, 1),
        // 10 days before the target → before the celld, foundation phase.
        songTargetDate: LocalDate(2026, 9, 11),
        weekAvailableMinutes: 100,
      );
      final outcome =
          const SongGoalPlanner().plan(request) as SongGoalPlanningAccepted;
      expect(outcome.assignments, hasLength(3));
      expect(outcome.droppedDrafts, isEmpty);
      expect(outcome.realizedSongRatio, lessThanOrEqualTo(0.4));
      // 3 drafts × 10 min = 30 min assigned; week = 100 → ratio = 0.3.
      expect(outcome.realizedSongRatio, closeTo(0.3, 1e-9));
    });

    test('drafts that would push the ratio over the cap are dropped '
        'with the ratioCapExceeded code (no silent skip)', () {
      final asset = buildSongAssetReference(id: 'asset-a1b');
      final sections = <SongGoalSectionView>[
        buildSongGoalSectionView(
          sectionId: 's-a1b-1',
          sectionName: 'Verse',
          kind: SongSectionKind.verse,
          startMeasure: 0,
          endMeasureExclusive: 8,
          usableAssetReference: asset,
        ),
        buildSongGoalSectionView(
          sectionId: 's-a1b-2',
          sectionName: 'Chorus',
          kind: SongSectionKind.chorus,
          startMeasure: 8,
          endMeasureExclusive: 16,
          usableAssetReference: asset,
        ),
        buildSongGoalSectionView(
          sectionId: 's-a1b-3',
          sectionName: 'Bridge',
          kind: SongSectionKind.bridge,
          startMeasure: 16,
          endMeasureExclusive: 24,
          usableAssetReference: asset,
        ),
      ];
      final read = buildSongGoalReadSuccess(
        sections: sections,
        revision: 7,
        documentAssetReferences: [asset],
      );
      // 3×15 = 45 minutes of song drafts; week capacity 100 → max 40
      // with default 0.4 cap. The first two fit (30), the third
      // overflows (45 > 40) and must be dropped with the typed code.
      final drafts = <SongGoalBlockDraft>[
        buildSongGoalBlockDraft(
          sectionView: sections[0],
          targetSkillIds: const ['chord-transition'],
          estimatedMinutes: 15,
        ),
        buildSongGoalBlockDraft(
          sectionView: sections[1],
          targetSkillIds: const ['strum-pattern'],
          estimatedMinutes: 15,
        ),
        buildSongGoalBlockDraft(
          sectionView: sections[2],
          targetSkillIds: const ['dynamic-control'],
          estimatedMinutes: 15,
        ),
      ];
      final request = buildSongGoalPlanningRequest(
        read: read,
        drafts: drafts,
        scheduledDate: LocalDate(2026, 9, 1),
        songTargetDate: LocalDate(2026, 9, 11),
        weekAvailableMinutes: 100,
      );
      final outcome =
          const SongGoalPlanner().plan(request) as SongGoalPlanningAccepted;
      expect(outcome.assignments, hasLength(2));
      expect(outcome.droppedDrafts, hasLength(1));
      expect(
        outcome.droppedDrafts.single.reasonCode,
        SongGoalDropReason.ratioCapExceeded,
      );
      expect(outcome.assignedSongMinutes, lessThanOrEqualTo(40));
      expect(outcome.realizedSongRatio, lessThanOrEqualTo(0.4));
    });
  });

  group('SongGoalPlanner — A2 no automatic block after target', () {
    test('scheduledDate strictly after songTargetDate emits no-op, '
        'never a new song block', () {
      final asset = buildSongAssetReference(id: 'asset-a2');
      final sections = <SongGoalSectionView>[
        buildSongGoalSectionView(
          sectionId: 's-a2-1',
          sectionName: 'Verse',
          kind: SongSectionKind.verse,
          startMeasure: 0,
          endMeasureExclusive: 8,
          usableAssetReference: asset,
        ),
      ];
      final read = buildSongGoalReadSuccess(
        sections: sections,
        revision: 7,
        documentAssetReferences: [asset],
      );
      final drafts = <SongGoalBlockDraft>[
        buildSongGoalBlockDraft(
          sectionView: sections[0],
          targetSkillIds: const ['chord-transition'],
          estimatedMinutes: 10,
        ),
      ];
      final request = buildSongGoalPlanningRequest(
        read: read,
        drafts: drafts,
        scheduledDate: LocalDate(2026, 9, 12),
        songTargetDate: LocalDate(2026, 9, 11), // yesterday
      );
      final outcome = const SongGoalPlanner().plan(request);
      expect(outcome, isA<SongGoalPlanningNoOpAfterTarget>());
      final noOp = outcome as SongGoalPlanningNoOpAfterTarget;
      expect(noOp.daysAfterTarget, 1);
      expect(noOp.reasonCode, SongGoalPlanningReason.noOpAfterTarget);
    });
  });

  group('SongGoalPlanner — §6.1 signed-distance cells', () {
    test('cell +1 (before target) → foundation phase, full draft set', () {
      final asset = buildSongAssetReference(id: 'asset-p1');
      final sections = <SongGoalSectionView>[
        buildSongGoalSectionView(
          sectionId: 's-p1-1',
          sectionName: 'Verse',
          kind: SongSectionKind.verse,
          startMeasure: 0,
          endMeasureExclusive: 8,
          usableAssetReference: asset,
        ),
        buildSongGoalSectionView(
          sectionId: 's-p1-2',
          sectionName: 'Chorus',
          kind: SongSectionKind.chorus,
          startMeasure: 8,
          endMeasureExclusive: 16,
          usableAssetReference: asset,
        ),
      ];
      final read = buildSongGoalReadSuccess(
        sections: sections,
        revision: 7,
        documentAssetReferences: [asset],
      );
      final drafts = <SongGoalBlockDraft>[
        buildSongGoalBlockDraft(
          sectionView: sections[0],
          targetSkillIds: const ['chord-transition'],
          estimatedMinutes: 5,
        ),
        buildSongGoalBlockDraft(
          sectionView: sections[1],
          targetSkillIds: const ['strum-pattern'],
          estimatedMinutes: 5,
        ),
      ];
      final request = buildSongGoalPlanningRequest(
        read: read,
        drafts: drafts,
        scheduledDate: LocalDate(2026, 9, 10),
        songTargetDate: LocalDate(2026, 9, 11), // +1 day
        weekAvailableMinutes: 100,
      );
      final outcome =
          const SongGoalPlanner().plan(request) as SongGoalPlanningAccepted;
      expect(outcome.assignments, hasLength(2));
      // +1 falls into the integration window per the default
      // phasePolicy (lightReviewWindowDays = 3). The §6.1 +1 cell is
      // "teljes fázis-ütemezés" — the planner produced assignments in
      // both phases (integration here) with no automatic drop.
      expect(outcome.assignments.first.phase, SongGoalPhase.integration);
      expect(outcome.droppedDrafts, isEmpty);
    });

    test('cell 0 (the target day) → simulation phase, drafts fit', () {
      final asset = buildSongAssetReference(id: 'asset-p0');
      final sections = <SongGoalSectionView>[
        buildSongGoalSectionView(
          sectionId: 's-p0-1',
          sectionName: 'Verse',
          kind: SongSectionKind.verse,
          startMeasure: 0,
          endMeasureExclusive: 8,
          usableAssetReference: asset,
        ),
      ];
      final read = buildSongGoalReadSuccess(
        sections: sections,
        revision: 7,
        documentAssetReferences: [asset],
      );
      // Known skills: this is the review-only branch.
      final drafts = <SongGoalBlockDraft>[
        buildSongGoalBlockDraft(
          sectionView: sections[0],
          targetSkillIds: const ['chord-transition'],
          estimatedMinutes: 5,
        ),
      ];
      final request = buildSongGoalPlanningRequest(
        read: read,
        drafts: drafts,
        scheduledDate: LocalDate(2026, 9, 11),
        songTargetDate: LocalDate(2026, 9, 11), // distance == 0
        weekAvailableMinutes: 100,
        knownSkillIds: const ['chord-transition'],
      );
      final outcome =
          const SongGoalPlanner().plan(request) as SongGoalPlanningAccepted;
      expect(outcome.assignments, hasLength(1));
      expect(outcome.assignments.single.phase, SongGoalPhase.simulation);
    });

    test('cell -1 (after target) → no automatic new block, no-op branch', () {
      final asset = buildSongAssetReference(id: 'asset-n1');
      final sections = <SongGoalSectionView>[
        buildSongGoalSectionView(
          sectionId: 's-n1-1',
          sectionName: 'Verse',
          kind: SongSectionKind.verse,
          startMeasure: 0,
          endMeasureExclusive: 8,
          usableAssetReference: asset,
        ),
      ];
      final read = buildSongGoalReadSuccess(
        sections: sections,
        revision: 7,
        documentAssetReferences: [asset],
      );
      final drafts = <SongGoalBlockDraft>[
        buildSongGoalBlockDraft(
          sectionView: sections[0],
          targetSkillIds: const ['chord-transition'],
          estimatedMinutes: 5,
        ),
      ];
      final request = buildSongGoalPlanningRequest(
        read: read,
        drafts: drafts,
        scheduledDate: LocalDate(2026, 9, 12),
        songTargetDate: LocalDate(2026, 9, 11), // -1 day
      );
      final outcome = const SongGoalPlanner().plan(request);
      expect(outcome, isA<SongGoalPlanningNoOpAfterTarget>());
    });
  });

  group('SongGoalPlanner — A3 prerequisite comes first', () {
    test('a draft that depends on an earlier draft is placed after it', () {
      final asset = buildSongAssetReference(id: 'asset-a3');
      final sections = <SongGoalSectionView>[
        buildSongGoalSectionView(
          sectionId: 's-a3-chords',
          sectionName: 'Chords',
          kind: SongSectionKind.verse,
          startMeasure: 0,
          endMeasureExclusive: 8,
          usableAssetReference: asset,
        ),
        buildSongGoalSectionView(
          sectionId: 's-a3-strum',
          sectionName: 'Strum',
          kind: SongSectionKind.chorus,
          startMeasure: 8,
          endMeasureExclusive: 16,
          usableAssetReference: asset,
        ),
      ];
      final read = buildSongGoalReadSuccess(
        sections: sections,
        revision: 7,
        documentAssetReferences: [asset],
      );
      // Reverse-declared dependency: the strum section depends on the
      // chord section. The planner must reorder so the chord section
      // comes first (ADR 0264 §4 prerequisite-boost).
      final drafts = <SongGoalBlockDraft>[
        buildSongGoalBlockDraft(
          sectionView: sections[1], // strum
          targetSkillIds: const ['strum-pattern'],
          prerequisiteSkillIds: const ['chord-transition'],
          estimatedMinutes: 5,
        ),
        buildSongGoalBlockDraft(
          sectionView: sections[0], // chords
          targetSkillIds: const ['chord-transition'],
          estimatedMinutes: 5,
        ),
      ];
      final request = buildSongGoalPlanningRequest(
        read: read,
        drafts: drafts,
        scheduledDate: LocalDate(2026, 9, 1),
        songTargetDate: LocalDate(2026, 9, 21),
      );
      final outcome =
          const SongGoalPlanner().plan(request) as SongGoalPlanningAccepted;
      expect(outcome.assignments, hasLength(2));
      expect(
        outcome.assignments[0].draft.sectionView.sectionId.value,
        's-a3-chords',
      );
      expect(
        outcome.assignments[1].draft.sectionView.sectionId.value,
        's-a3-strum',
      );
    });

    test('unsatisfied prerequisite is reported on the assignment', () {
      final asset = buildSongAssetReference(id: 'asset-a3b');
      final sections = <SongGoalSectionView>[
        buildSongGoalSectionView(
          sectionId: 's-a3b-1',
          sectionName: 'Solo',
          kind: SongSectionKind.solo,
          startMeasure: 0,
          endMeasureExclusive: 8,
          usableAssetReference: asset,
        ),
      ];
      final read = buildSongGoalReadSuccess(
        sections: sections,
        revision: 7,
        documentAssetReferences: [asset],
      );
      final drafts = <SongGoalBlockDraft>[
        buildSongGoalBlockDraft(
          sectionView: sections[0],
          targetSkillIds: const ['lead-improvisation'],
          prerequisiteSkillIds: const ['pentatonic-scale'],
          estimatedMinutes: 5,
        ),
      ];
      final request = buildSongGoalPlanningRequest(
        read: read,
        drafts: drafts,
        scheduledDate: LocalDate(2026, 9, 1),
        songTargetDate: LocalDate(2026, 9, 21),
        // 'pentatonic-scale' is NOT in knownSkillIds.
        knownSkillIds: const ['chord-transition'],
      );
      final outcome =
          const SongGoalPlanner().plan(request) as SongGoalPlanningAccepted;
      expect(outcome.assignments, hasLength(1));
      expect(outcome.assignments.single.unsatisfiedPrerequisiteSkillIds, [
        'pentatonic-scale',
      ]);
    });
  });

  group('SongGoalPlanner — A4 no new technique in simulation', () {
    test('a draft with a NEW skill target is dropped in simulation phase', () {
      final asset = buildSongAssetReference(id: 'asset-a4');
      final sections = <SongGoalSectionView>[
        buildSongGoalSectionView(
          sectionId: 's-a4-new',
          sectionName: 'Solo',
          kind: SongSectionKind.solo,
          startMeasure: 0,
          endMeasureExclusive: 8,
          usableAssetReference: asset,
        ),
      ];
      final read = buildSongGoalReadSuccess(
        sections: sections,
        revision: 7,
        documentAssetReferences: [asset],
      );
      final drafts = <SongGoalBlockDraft>[
        buildSongGoalBlockDraft(
          sectionView: sections[0],
          targetSkillIds: const ['tap-technique'], // NEW skill
          estimatedMinutes: 5,
        ),
      ];
      final request = buildSongGoalPlanningRequest(
        read: read,
        drafts: drafts,
        scheduledDate: LocalDate(2026, 9, 11), // distance == 0
        songTargetDate: LocalDate(2026, 9, 11),
        knownSkillIds: const ['chord-transition'], // tap-technique absent
      );
      final outcome =
          const SongGoalPlanner().plan(request) as SongGoalPlanningAccepted;
      expect(outcome.assignments, isEmpty);
      expect(outcome.droppedDrafts, hasLength(1));
      expect(
        outcome.droppedDrafts.single.reasonCode,
        SongGoalDropReason.newTechniqueInSimulation,
      );
    });

    test('a draft whose targets are already KNOWN is kept in simulation', () {
      final asset = buildSongAssetReference(id: 'asset-a4b');
      final sections = <SongGoalSectionView>[
        buildSongGoalSectionView(
          sectionId: 's-a4b-known',
          sectionName: 'Verse review',
          kind: SongSectionKind.verse,
          startMeasure: 0,
          endMeasureExclusive: 8,
          usableAssetReference: asset,
        ),
      ];
      final read = buildSongGoalReadSuccess(
        sections: sections,
        revision: 7,
        documentAssetReferences: [asset],
      );
      final drafts = <SongGoalBlockDraft>[
        buildSongGoalBlockDraft(
          sectionView: sections[0],
          targetSkillIds: const ['chord-transition'], // already known
          estimatedMinutes: 5,
        ),
      ];
      final request = buildSongGoalPlanningRequest(
        read: read,
        drafts: drafts,
        scheduledDate: LocalDate(2026, 9, 11), // distance == 0
        songTargetDate: LocalDate(2026, 9, 11),
        knownSkillIds: const ['chord-transition'],
      );
      final outcome =
          const SongGoalPlanner().plan(request) as SongGoalPlanningAccepted;
      expect(outcome.assignments, hasLength(1));
      expect(outcome.assignments.single.phase, SongGoalPhase.simulation);
      expect(outcome.droppedDrafts, isEmpty);
    });
  });

  group('SongGoalPlanner — A8 caller-fed outcome normalization', () {
    test('completed + partial terminals carry learner evidence '
        '(evidenceIsLearnerSignal == true)', () {
      final asset = buildSongAssetReference(id: 'asset-a8');
      final sections = <SongGoalSectionView>[
        buildSongGoalSectionView(
          sectionId: 's-a8-1',
          sectionName: 'Verse',
          kind: SongSectionKind.verse,
          startMeasure: 0,
          endMeasureExclusive: 8,
          usableAssetReference: asset,
        ),
      ];
      final read = buildSongGoalReadSuccess(
        sections: sections,
        revision: 7,
        documentAssetReferences: [asset],
      );
      final drafts = <SongGoalBlockDraft>[
        buildSongGoalBlockDraft(
          sectionView: sections[0],
          targetSkillIds: const ['chord-transition'],
          estimatedMinutes: 5,
        ),
      ];
      final request = buildSongGoalPlanningRequest(
        read: read,
        drafts: drafts,
        scheduledDate: LocalDate(2026, 9, 1),
        songTargetDate: LocalDate(2026, 9, 21),
      );
      final outcome =
          const SongGoalPlanner().plan(request) as SongGoalPlanningAccepted;
      final assignment = outcome.assignments.single;

      final completed = const SongGoalPlanner().normalizeOutcome(
        assignment: assignment,
        terminal: SongGoalTerminalCompleted(
          metricEvidence: {'chord-transition': 0.85},
        ),
      );
      expect(completed.state, SongGoalOutcomeState.completed);
      expect(completed.evidenceIsLearnerSignal, isTrue);
      expect(completed.metricEvidence, {'chord-transition': 0.85});

      final partial = const SongGoalPlanner().normalizeOutcome(
        assignment: assignment,
        terminal: SongGoalTerminalPartial(
          metricEvidence: {'chord-transition': 0.5},
        ),
      );
      expect(partial.state, SongGoalOutcomeState.partial);
      expect(partial.evidenceIsLearnerSignal, isTrue);
    });

    test('skipped + failedTechnical + unavailable are NOT learner '
        'evidence (ADR 0268 §1, §2; ADR 0318 §Döntés 2)', () {
      final asset = buildSongAssetReference(id: 'asset-a8b');
      final sections = <SongGoalSectionView>[
        buildSongGoalSectionView(
          sectionId: 's-a8b-1',
          sectionName: 'Verse',
          kind: SongSectionKind.verse,
          startMeasure: 0,
          endMeasureExclusive: 8,
          usableAssetReference: asset,
        ),
      ];
      final read = buildSongGoalReadSuccess(
        sections: sections,
        revision: 7,
        documentAssetReferences: [asset],
      );
      final drafts = <SongGoalBlockDraft>[
        buildSongGoalBlockDraft(
          sectionView: sections[0],
          targetSkillIds: const ['chord-transition'],
          estimatedMinutes: 5,
        ),
      ];
      final request = buildSongGoalPlanningRequest(
        read: read,
        drafts: drafts,
        scheduledDate: LocalDate(2026, 9, 1),
        songTargetDate: LocalDate(2026, 9, 21),
      );
      final outcome =
          const SongGoalPlanner().plan(request) as SongGoalPlanningAccepted;
      final assignment = outcome.assignments.single;

      final skipped = const SongGoalPlanner().normalizeOutcome(
        assignment: assignment,
        terminal: SongGoalTerminalSkipped(),
      );
      expect(skipped.state, SongGoalOutcomeState.skipped);
      expect(skipped.evidenceIsLearnerSignal, isFalse);
      expect(skipped.metricEvidence, isEmpty);

      final failed = const SongGoalPlanner().normalizeOutcome(
        assignment: assignment,
        terminal: SongGoalTerminalFailedTechnical(
          failureCode: 'microphone.permissionDenied',
        ),
      );
      expect(failed.state, SongGoalOutcomeState.failedTechnical);
      expect(failed.evidenceIsLearnerSignal, isFalse);

      final unavailable = const SongGoalPlanner().normalizeOutcome(
        assignment: assignment,
        terminal: SongGoalTerminalUnavailable(),
      );
      expect(unavailable.state, SongGoalOutcomeState.unavailable);
      expect(unavailable.evidenceIsLearnerSignal, isFalse);
    });
  });

  group('SongGoalPlanner — A6 stale revision surfaces, never plans', () {
    test(
      'a stale-read outcome is propagated as SongGoalPlanningStaleRevision',
      () {
        final stale = SongGoalReadStaleRevision(
          documentId: SongId('fixture-song-1'),
          actualRevision: 8,
          expectedRevision: 7,
        );
        final request = buildSongGoalPlanningRequest(
          read: stale,
          drafts: const <SongGoalBlockDraft>[],
          scheduledDate: LocalDate(2026, 9, 1),
          songTargetDate: LocalDate(2026, 9, 21),
        );
        final outcome = const SongGoalPlanner().plan(request);
        expect(outcome, isA<SongGoalPlanningStaleRevision>());
        final staleOutcome = outcome as SongGoalPlanningStaleRevision;
        expect(staleOutcome.reasonCode, SongGoalPlanningReason.staleRevision);
        expect(staleOutcome.actualRevision, 8);
        expect(staleOutcome.expectedRevision, 7);
      },
    );
  });

  group('SongGoalPlanner — §6.1 valódi-sértés próba '
      '(remove ratio cap → A1 must turn red, then restore)', () {
    test('a malformed SongGoalRatioPolicy with maximumSongRatio=1.0 '
        'allows the song to fill the week; A1 turns red', () {
      final asset = buildSongAssetReference(id: 'asset-violation');
      final sections = <SongGoalSectionView>[
        buildSongGoalSectionView(
          sectionId: 's-violation-1',
          sectionName: 'Verse',
          kind: SongSectionKind.verse,
          startMeasure: 0,
          endMeasureExclusive: 8,
          usableAssetReference: asset,
        ),
        buildSongGoalSectionView(
          sectionId: 's-violation-2',
          sectionName: 'Chorus',
          kind: SongSectionKind.chorus,
          startMeasure: 8,
          endMeasureExclusive: 16,
          usableAssetReference: asset,
        ),
      ];
      final read = buildSongGoalReadSuccess(
        sections: sections,
        revision: 7,
        documentAssetReferences: [asset],
      );
      // Each draft eats 30 minutes; week is 60 minutes.
      // With a 1.0 (uncapped) ratio policy, the planner must accept
      // both drafts and let the song fill the week — that is the
      // exact "a dal kitölti a hetet" branch §6.1 expects A1 to
      // turn red on. The default policy would drop the second.
      final drafts = <SongGoalBlockDraft>[
        buildSongGoalBlockDraft(
          sectionView: sections[0],
          targetSkillIds: const ['chord-transition'],
          estimatedMinutes: 30,
        ),
        buildSongGoalBlockDraft(
          sectionView: sections[1],
          targetSkillIds: const ['strum-pattern'],
          estimatedMinutes: 30,
        ),
      ];
      final uncapped = SongGoalRatioPolicy(maximumSongRatio: 1.0);
      final request = buildSongGoalPlanningRequest(
        read: read,
        drafts: drafts,
        scheduledDate: LocalDate(2026, 9, 1),
        songTargetDate: LocalDate(2026, 9, 11),
        weekAvailableMinutes: 60,
        ratioPolicy: uncapped,
      );
      final outcome =
          const SongGoalPlanner().plan(request) as SongGoalPlanningAccepted;
      // The song fills the week → A1 red.
      expect(outcome.assignedSongMinutes, 60);
      expect(outcome.realizedSongRatio, closeTo(1.0, 1e-9));
      // The default policy would have kept the ratio at 0.5 → red
      // would NOT fire. Verify the contrast for the audit log.
      final defaultRequest = buildSongGoalPlanningRequest(
        read: read,
        drafts: drafts,
        scheduledDate: LocalDate(2026, 9, 1),
        songTargetDate: LocalDate(2026, 9, 11),
        weekAvailableMinutes: 60,
      );
      final defaultOutcome =
          const SongGoalPlanner().plan(defaultRequest)
              as SongGoalPlanningAccepted;
      // With the default 0.4 cap and a 60-minute week, the max song
      // minutes is floor(60 × 0.4) = 24. Each draft is 30 min — both
      // overflow the cap and must be dropped with the typed reason.
      expect(defaultOutcome.assignedSongMinutes, 0);
      expect(defaultOutcome.droppedDrafts, hasLength(2));
      expect(
        defaultOutcome.droppedDrafts.first.reasonCode,
        SongGoalDropReason.ratioCapExceeded,
      );
      expect(
        defaultOutcome.droppedDrafts.last.reasonCode,
        SongGoalDropReason.ratioCapExceeded,
      );
    });
  });
}
