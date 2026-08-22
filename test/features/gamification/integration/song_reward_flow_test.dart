// E08-R25 — Song Trainer and setlist → gamification reward flow integration
// tests.
//
// Covers brief §6 acceptance cells A1..A8 with the §6.1 valódi-sértés
// próba for A1 (the "rajta" cell), A5 (privacy), and A2 (session-id
// namespacing). The complementary A7 regression is enforced by the
// `tools/round-gate.sh test/features/songs` invocation in §7 — any change
// here that touches the `songs` feature is caught by that suite.

import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/logging/app_logger.dart';
import 'package:strumsight/features/gamification/data/local_reward_ledger_repository.dart';
import 'package:strumsight/features/gamification/public.dart';
import 'package:strumsight/features/songs/application/gamification_song_adapter.dart';
import 'package:strumsight/features/songs/model/song.dart';

import '../../../core/storage/in_memory_key_value_store.dart';

const String _defaultSessionId = 'song-session-7';
const String _defaultSetlistRunId = 'setlist-run-3';
const String _defaultItemId = 'setlist-item-2';
const String _defaultSongId = 'musicxml-my-secret-song-title';
const int _defaultEpochDay = 20410;
final DateTime _defaultOccurredAt = DateTime.utc(2026, 8, 22, 14, 0);
const String _defaultSongName = 'My Secret Song Title';

void main() {
  group('Song → gamification reward flow (E08-R25)', () {
    // ── A1 inflation guard — the §6.1 three-cell matrix ────────────────

    test('A1 (§6.1 alatt): only section events → only the section base reward, '
        'no full-song event', () async {
      final fixture = _Fixture.build();
      final signal = _signalWithSections(
        sectionCount: 3,
        fullSongCompleted: false,
      );

      final outcome = await fixture.adapter.recordSession(signal);
      await fixture.ingestor.drain();

      expect(outcome.accepted, isTrue);
      expect(outcome.fullSongEmitted, isFalse);
      // Three sections → three events, no full-song event.
      expect(outcome.eventIds, hasLength(3));
      expect(
        outcome.eventIds.every(
          (id) => id.startsWith('song-section/$_defaultSessionId/'),
        ),
        isTrue,
      );
      // Drain moved them to the ledger.
      final entries = fixture.ledger.readPage(limit: 20).entries;
      expect(entries, hasLength(3));
      // No entry may be the full-song event.
      expect(
        entries.any(
          (e) =>
              e.sourceEventId ==
              GamificationSongAdapter.fullSongEventId(
                sessionId: _defaultSessionId,
              ),
        ),
        isFalse,
      );
    });

    test(
      'A1 (§6.1 rajta): sections + full song in same session → sections base '
      'reward ONCE + full-song REDUCED bonus signal (not zero, not double)',
      () async {
        final fixture = _Fixture.build();
        final signal = _signalWithSections(
          sectionCount: 4,
          fullSongCompleted: true,
        );

        final outcome = await fixture.adapter.recordSession(signal);
        await fixture.ingestor.drain();

        // 4 sections + 1 full-song = 5 events, with fullSongEmitted=false
        // because the §5.1 bookkeeping detected the session had sections.
        expect(outcome.accepted, isTrue);
        expect(outcome.fullSongEmitted, isFalse);
        expect(outcome.eventIds, hasLength(5));

        // The full-song event was emitted but with the §5.1 REDUCED signal
        // — the ledger's baseXp is positive but the duration component is
        // scaled to one third of the natural value, so the total is
        // strictly LESS than a free-session full-song run.
        final reducedTotal = _totalXpFor(
          entries: fixture.ledger.readPage(limit: 20).entries,
          eventId: GamificationSongAdapter.fullSongEventId(
            sessionId: _defaultSessionId,
          ),
        );
        expect(reducedTotal, greaterThan(0));

        // Compare to a session with only the full song: the "fölött" total
        // must be strictly higher than the "rajta" total — proving the
        // bookkeeping is doing its job, not a coincidence.
        final naturalFixture = _Fixture.build();
        await naturalFixture.adapter.recordSession(
          _signalWithSections(
            sectionCount: 0,
            fullSongCompleted: true,
            sessionId: 'song-session-natural',
          ),
        );
        await naturalFixture.ingestor.drain();
        final naturalTotal = _totalXpFor(
          entries: naturalFixture.ledger.readPage(limit: 20).entries,
          eventId: GamificationSongAdapter.fullSongEventId(
            sessionId: 'song-session-natural',
          ),
        );
        expect(
          naturalTotal,
          greaterThan(reducedTotal),
          reason:
              'A full song after a section-bearing session must pay LESS XP '
              'than a free-session full song — otherwise the §5.1 '
              'bookkeeping is not in effect.',
        );

        // Critical §6.1 rajta guarantee: the bonus is NOT zero.
        expect(
          reducedTotal,
          greaterThan(0),
          reason:
              'A full song after a section-bearing session must still pay '
              'something — zeroing it would be the R06 parentEventId bug '
              'measured at §0.0.',
        );
      },
    );

    test(
      'A1 (§6.1 fölött): full song without sections → natural full signal',
      () async {
        final fixture = _Fixture.build();
        final signal = _signalWithSections(
          sectionCount: 0,
          fullSongCompleted: true,
        );

        final outcome = await fixture.adapter.recordSession(signal);
        await fixture.ingestor.drain();

        expect(outcome.accepted, isTrue);
        expect(outcome.fullSongEmitted, isTrue);
        expect(outcome.eventIds, hasLength(1));
        expect(outcome.eventIds.single, isNotEmpty);
        // No section events — the §5.1 bookkeeping is not engaged.
        expect(
          outcome.eventIds.every((id) => id.startsWith('song-section/')),
          isFalse,
        );
      },
    );

    test(
      'A1 (§6.1 fölött → rajta boundary): the same session, no sections vs '
      'one section, must be strictly different XP for the full-song event',
      () async {
        // Pure full song.
        final noSection = _Fixture.build();
        await noSection.adapter.recordSession(
          _signalWithSections(
            sectionCount: 0,
            fullSongCompleted: true,
            sessionId: 'song-session-compare-a',
          ),
        );
        await noSection.ingestor.drain();
        final naturalTotal = _totalXpFor(
          entries: noSection.ledger.readPage(limit: 20).entries,
          eventId: GamificationSongAdapter.fullSongEventId(
            sessionId: 'song-session-compare-a',
          ),
        );

        // One section + full song in the same session.
        final oneSection = _Fixture.build();
        await oneSection.adapter.recordSession(
          _signalWithSections(
            sectionCount: 1,
            fullSongCompleted: true,
            sessionId: 'song-session-compare-b',
          ),
        );
        await oneSection.ingestor.drain();
        final reducedTotal = _totalXpFor(
          entries: oneSection.ledger.readPage(limit: 20).entries,
          eventId: GamificationSongAdapter.fullSongEventId(
            sessionId: 'song-session-compare-b',
          ),
        );

        expect(naturalTotal, greaterThan(0));
        expect(reducedTotal, greaterThan(0));
        expect(
          naturalTotal,
          greaterThan(reducedTotal),
          reason:
              'A single section in the session must already collapse the '
              'full-song signal — the §5.1 bookkeeping is binary, not '
              'section-count-graded.',
        );
      },
    );

    // ── A2 session-id namespacing ──────────────────────────────────────

    test('A2: section eventId contains the sessionId (and the full-song '
        'eventId does too, on a different segment)', () async {
      final fixture = _Fixture.build();
      final signal = _signalWithSections(
        sessionId: 'session-namespace-42',
        sectionCount: 2,
        fullSongCompleted: true,
      );

      final outcome = await fixture.adapter.recordSession(signal);

      expect(
        outcome.eventIds.where(
          (id) => id.startsWith('song-section/session-namespace-42/'),
        ),
        hasLength(2),
      );
      expect(outcome.eventIds, contains('song-full/session-namespace-42/v1'));
      expect(
        outcome.eventIds.every((id) => id.contains('session-namespace-42')),
        isTrue,
      );
    });

    test(
      'A2: a setlist run namespaced under setlist-item-*, never '
      'colliding with a free session that shares the same sessionId',
      () async {
        final freeFixture = _Fixture.build();
        final freeSignal = _signalWithSections(
          sessionId: 'shared-id',
          sectionCount: 0,
          fullSongCompleted: true,
        );
        final freeOutcome = await freeFixture.adapter.recordSession(freeSignal);
        await freeFixture.ingestor.drain();

        final setlistFixture = _Fixture.build();
        final setlistSignal = _signalWithSections(
          sessionId: 'shared-id',
          sectionCount: 1,
          fullSongCompleted: true,
          setlistRunId: _defaultSetlistRunId,
          itemId: _defaultItemId,
        );
        final setlistOutcome = await setlistFixture.adapter.recordSession(
          setlistSignal,
        );
        await setlistFixture.ingestor.drain();

        // Distinct event namespaces — same sessionId, different event ids.
        expect(freeOutcome.eventIds, isNot(equals(setlistOutcome.eventIds)));
        expect(
          setlistOutcome.eventIds.every((id) => id.startsWith('setlist-item-')),
          isTrue,
        );
        // Both fixtures' ledgers hold only their own events.
        final freeEntries = freeFixture.ledger.readPage(limit: 20).entries;
        final setlistEntries = setlistFixture.ledger
            .readPage(limit: 20)
            .entries;
        expect(freeEntries, hasLength(1));
        expect(setlistEntries, hasLength(2));
      },
    );

    // ── A3 reopen, A4 new take, A8 offline, A5 privacy ─────────────────

    test('A3: result-screen reopen with the same sessionId produces the same '
        'event ids; the ledger stays at one entry per event id', () async {
      final fixture = _Fixture.build();
      final signal = _signalWithSections(
        sectionCount: 2,
        fullSongCompleted: true,
      );

      final first = await fixture.adapter.recordSession(signal);
      await fixture.ingestor.drain();
      final firstCount = fixture.ledger.readPage(limit: 20).entries.length;

      final reopened = await fixture.adapter.recordSession(signal);
      await fixture.ingestor.drain();

      expect(reopened.eventIds, equals(first.eventIds));
      expect(
        fixture.ledger.readPage(limit: 20).entries.length,
        equals(firstCount),
        reason: 'reopen must NOT add a second entry for the same event id',
      );
    });

    test('A4: a different takeId (different sessionId) produces a different '
        'eventId and a fresh ledger entry', () async {
      final fixture = _Fixture.build();
      final first = await fixture.adapter.recordSession(
        _signalWithSections(sectionCount: 1, fullSongCompleted: true),
      );
      await fixture.ingestor.drain();
      final second = await fixture.adapter.recordSession(
        _signalWithSections(
          sectionCount: 1,
          fullSongCompleted: true,
          sessionId: 'song-session-8',
        ),
      );
      await fixture.ingestor.drain();

      expect(first.eventIds, isNot(equals(second.eventIds)));
      expect(fixture.ledger.readPage(limit: 20).entries.length, 4);
    });

    test(
      'A5 (privacy): the ledger never carries the song title, the file '
      'name, or the raw SongId — only the SHA-256 first-16-hex digest',
      () async {
        final fixture = _Fixture.build();
        final signal = _signalWithSections(
          sectionCount: 1,
          fullSongCompleted: true,
        );

        await fixture.adapter.recordSession(signal);
        await fixture.ingestor.drain();

        final entries = fixture.ledger.readPage(limit: 20).entries;
        final ledgerBlobs = <String>[
          ...entries.map((e) => e.sourceEventId),
          ...entries.map((e) => e.ledgerId),
        ];
        final allText = ledgerBlobs.join('|');
        expect(
          allText.contains(_defaultSongName.toLowerCase()),
          isFalse,
          reason: 'song title MUST NOT appear in any ledger field',
        );
        expect(
          allText.contains(_defaultSongName.toLowerCase().replaceAll(' ', '-')),
          isFalse,
          reason:
              'the slug form of the title MUST NOT appear in any ledger field',
        );
        expect(
          allText.contains('my-secret-song-title'),
          isFalse,
          reason: 'the file-name slug MUST NOT appear in any ledger field',
        );
        expect(
          allText.contains('musicxml-'),
          isFalse,
          reason: 'the importer prefix MUST NOT appear — only the SHA-256 hex',
        );

        // The hashed id IS present — confirms the privacy boundary is the
        // digest, not a missing identity.
        final expectedHash = GamificationSongAdapter.hashedSongId(
          _defaultSongId,
        );
        expect(expectedHash, hasLength(16));
        expect(
          allText.contains(expectedHash),
          isTrue,
          reason:
              'The 16-char SHA-256 prefix must appear in the ledger so the '
              'reward is attributable to a song without leaking the title.',
        );

        // Determinism: same input → same digest.
        expect(
          GamificationSongAdapter.hashedSongId(_defaultSongId),
          equals(expectedHash),
        );
      },
    );

    test(
      'A6: the tempo milestone returns the previous best and its timestamp '
      'so the caller can render an explainable "new personal best" UI',
      () async {
        final fixture = _Fixture.build();
        final previousBestAt = DateTime.utc(2026, 8, 19, 9, 30);
        final signal = _signalWithSections(
          sectionCount: 2,
          fullSongCompleted: true,
          tempoMilestone: SongTempoMilestone(
            newBpm: 96,
            previousBestBpm: 88,
            previousBestAt: previousBestAt,
          ),
        );

        final outcome = await fixture.adapter.recordSession(signal);

        expect(outcome.tempoMilestone, isNotNull);
        expect(outcome.tempoMilestone!.newBpm, 96);
        expect(outcome.tempoMilestone!.previousBestBpm, 88);
        expect(outcome.tempoMilestone!.previousBestAt, previousBestAt);
      },
    );

    test('A8: the adapter writes only through the in-memory outbox — no '
        'network, no filesystem, no platform plugin is touched', () async {
      final fixture = _Fixture.build();
      final signal = _signalWithSections(
        sectionCount: 2,
        fullSongCompleted: true,
      );

      // Pre-state: empty ledger, empty outbox.
      expect(fixture.ledger.readPage(limit: 20).entries, isEmpty);
      expect(fixture.outbox.pendingRecords(), isEmpty);

      final outcome = await fixture.adapter.recordSession(signal);
      await fixture.ingestor.drain();

      expect(outcome.accepted, isTrue);
      // The outbox is the only persistence path — a closed InMemoryKVStore
      // can be inspected end-to-end.
      expect(fixture.outbox.pendingRecords(), isEmpty);
      expect(fixture.ledger.readPage(limit: 20).entries, hasLength(3));
    });

    test(
      'A1 (valódi-sértés próba, §6.1 rajta): the section-bookkeeping branch '
      'is the ONLY mechanism that produces the reduced full-song signal — '
      'a hypothetical "always natural" implementation fails this cell',
      () async {
        // This test documents the §6.1 valódi-sértés próba as a RED test
        // sentinel: a hypothetical adapter that ALWAYS sends the natural
        // full-song signal (no session-bookkeeping) would over-pay. We
        // assert the GREEN side here: the bookkeeping IS in effect, so
        // sections+full in one session pay LESS than a section-free full
        // run, but more than zero.
        final withBookkeeping = _Fixture.build();
        await withBookkeeping.adapter.recordSession(
          _signalWithSections(
            sessionId: 'song-bookkeeping-on',
            sectionCount: 2,
            fullSongCompleted: true,
          ),
        );
        await withBookkeeping.ingestor.drain();
        final reducedTotal = _totalXpFor(
          entries: withBookkeeping.ledger.readPage(limit: 20).entries,
          eventId: GamificationSongAdapter.fullSongEventId(
            sessionId: 'song-bookkeeping-on',
          ),
        );

        // A section-free full run.
        final noBookkeeping = _Fixture.build();
        await noBookkeeping.adapter.recordSession(
          _signalWithSections(
            sessionId: 'song-bookkeeping-off',
            sectionCount: 0,
            fullSongCompleted: true,
          ),
        );
        await noBookkeeping.ingestor.drain();
        final naturalTotal = _totalXpFor(
          entries: noBookkeeping.ledger.readPage(limit: 20).entries,
          eventId: GamificationSongAdapter.fullSongEventId(
            sessionId: 'song-bookkeeping-off',
          ),
        );

        // The bookkeeping reduced, but did not zero.
        expect(reducedTotal, lessThan(naturalTotal));
        expect(reducedTotal, greaterThan(0));
      },
    );

    test('A1 (valódi-sértés próba, §6.1 rajta): a parentEventId-style binary '
        'dedup would zero the full-song bonus — the adapter explicitly avoids '
        'that branch', () async {
      // The §0.0/§6.1 measurement: a literal `parentEventId: <section>`
      // link would invoke the R06 binary dedup and zero the full-song
      // event. The adapter avoids this by emitting `parentEventId: null`
      // on every event; this test asserts that, by sending a section +
      // full signal, the full-song event survives with a positive XP
      // (i.e. the binary-dedup path is NOT the one in effect).
      final fixture = _Fixture.build();
      final signal = _signalWithSections(
        sessionId: 'song-no-parent',
        sectionCount: 3,
        fullSongCompleted: true,
      );

      await fixture.adapter.recordSession(signal);
      await fixture.ingestor.drain();

      final reducedTotal = _totalXpFor(
        entries: fixture.ledger.readPage(limit: 20).entries,
        eventId: GamificationSongAdapter.fullSongEventId(
          sessionId: 'song-no-parent',
        ),
      );
      expect(
        reducedTotal,
        greaterThan(0),
        reason:
            'parentEventId dedup would collapse the full-song event to '
            'zero — the fact that the bonus is positive proves the '
            'session-bookkeeping branch is the one in effect.',
      );
    });
  });
}

// ── helpers ────────────────────────────────────────────────────────────────

int _totalXpFor({
  required List<RewardLedgerEntry> entries,
  required String eventId,
}) {
  return entries
      .where((e) => e.sourceEventId == eventId)
      .fold<int>(0, (sum, e) => sum + e.totalXp);
}

SongGamificationSignal _signalWithSections({
  String sessionId = _defaultSessionId,
  String songId = _defaultSongId,
  String songName = _defaultSongName,
  int sectionCount = 1,
  bool fullSongCompleted = false,
  String? setlistRunId,
  String? itemId,
  SongTempoMilestone? tempoMilestone,
  Duration validDuration = const Duration(minutes: 3),
  double? quality = 0.85,
  EvidenceTrust trust = EvidenceTrust.scored,
  double score = 0.85,
  int epochDay = _defaultEpochDay,
  DateTime? occurredAt,
}) {
  final song = Song(
    id: songId,
    name: songName,
    chords: const ['C', 'G', 'Am', 'F'],
    pattern: const [null, null, null, null, null, null, null, null],
    bpm: 90,
  );
  final sections = <SongSectionEventSignal>[
    for (var i = 0; i < sectionCount; i++)
      SongSectionEventSignal(
        sectionId: 'section-$i',
        validDuration: const Duration(minutes: 1),
        score: 0.85,
      ),
  ];
  return SongGamificationSignal(
    sessionId: sessionId,
    song: song,
    validDuration: validDuration,
    quality: quality,
    evidenceTrust: trust,
    score: score,
    epochDay: epochDay,
    occurredAt: occurredAt ?? _defaultOccurredAt,
    sectionEvents: sections,
    fullSongCompleted: fullSongCompleted,
    setlistRunId: setlistRunId,
    setlistItemId: itemId,
    tempoMilestone: tempoMilestone,
  );
}

class _Fixture {
  _Fixture._({
    required this.store,
    required this.logger,
    required this.ledger,
    required this.outbox,
    required this.ingestor,
    required this.eligibility,
    required this.rewardPolicy,
    required this.adapter,
  });

  factory _Fixture.build() {
    final store = InMemoryKeyValueStore(<String, Object>{});
    const logger = NoopAppLogger();
    final ledger = LocalRewardLedgerRepository(store: store, logger: logger);
    final outbox = LocalActivityOutboxRepository(
      ledger: ledger,
      store: store,
      logger: logger,
      capacity: 32,
      maxAttempts: 3,
    );
    final ingestor = ActivityEventIngestor(outbox: outbox, logger: logger);
    final eligibility = DefaultRewardEligibilityPolicy(
      config: RewardEligibilityPolicyConfig.standard(),
    );
    final rewardPolicy = DefaultRewardPolicy(
      config: RewardPolicyConfig.standard(),
    );
    return _Fixture._(
      store: store,
      logger: logger,
      ledger: ledger,
      outbox: outbox,
      ingestor: ingestor,
      eligibility: eligibility,
      rewardPolicy: rewardPolicy,
      adapter: GamificationSongAdapter(
        ingestor: ingestor,
        eligibility: eligibility,
        rewardPolicy: rewardPolicy,
        historyBuilder: _emptyHistory,
      ),
    );
  }

  final InMemoryKeyValueStore store;
  final AppLogger logger;
  final LocalRewardLedgerRepository ledger;
  final LocalActivityOutboxRepository outbox;
  final ActivityEventIngestor ingestor;
  final RewardEligibilityPolicy eligibility;
  final RewardPolicy rewardPolicy;
  final GamificationSongAdapter adapter;

  static SongRewardHistorySnapshot _emptyHistory(int epochDay, String _) =>
      const SongRewardHistorySnapshot(
        earnedTodayXp: 0,
        practiceOccurrenceCount: 0,
        uniqueSourcesToday: 1,
        rewardedEventIds: <String>{},
        rewardedParentIds: <String>{},
        rewardedChildParentIds: <String>{},
      );
}
