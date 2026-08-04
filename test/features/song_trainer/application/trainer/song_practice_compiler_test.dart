import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/chord.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/practice/public.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_practice_compiler.dart';
import 'package:strumsight/features/song_trainer/application/trainer/song_result_mapper.dart';
import 'package:strumsight/features/song_trainer/domain/models/loop_config.dart';
import 'package:strumsight/features/song_trainer/domain/models/meter_map.dart'
    as song_meter;
import 'package:strumsight/features/song_trainer/domain/models/song_document.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_event_reference.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_event.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_id.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_instrument.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_measure.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_metadata.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_section.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_source.dart';
import 'package:strumsight/features/song_trainer/domain/models/song_track.dart';
import 'package:strumsight/features/song_trainer/domain/models/tempo_map.dart'
    as song_time;
import 'package:strumsight/features/song_trainer/domain/models/trainer_config.dart';
import 'package:strumsight/features/song_trainer/domain/models/trainer_range.dart';
import 'package:strumsight/features/song_trainer/domain/services/song_time_map.dart';

void main() {
  test('compiles a legacy 4/4 range with multiple canonical chord targets', () {
    final compilation = SongPracticeCompiler.compile(
      document: _document(
        track: ChordTrack(
          id: SongTrackId('chords'),
          name: 'Chords',
          instrument: _guitar,
          events: <SongChordEvent>[
            SongChordEvent(
              id: SongEventId('chord-c'),
              start: Duration.zero,
              duration: const Duration(milliseconds: 500),
              symbol: Chord('C'),
            ),
            SongChordEvent(
              id: SongEventId('chord-g'),
              start: const Duration(milliseconds: 500),
              duration: const Duration(milliseconds: 500),
              symbol: Chord('G'),
            ),
          ],
        ),
      ),
      config: _config(
        trackId: SongTrackId('chords'),
        mode: TrainerMode.chord,
        range: MeasureRange(start: 0, endExclusive: 1),
      ),
    );
    final definition = compilation.definition!;

    expect(definition.meter, const Meter(beatsPerBar: 4));
    expect(
      definition.totalBeats,
      BeatPosition.fromTicks(4 * BeatPosition.ticksPerBeat),
    );
    expect(definition.events.map((event) => event.chord), <String?>['C', 'G']);
    expect(definition.events.map((event) => event.position), <BeatPosition>[
      BeatPosition.fromTicks(0),
      BeatPosition.fromTicks(BeatPosition.ticksPerBeat),
    ]);
    expect(
      definition.scoringProfile.weights,
      const <PracticeScoreDimension, int>{
        PracticeScoreDimension.chord: 60,
        PracticeScoreDimension.rhythm: 40,
      },
    );
    expect(
      compilation.eventReferences.values.every(
        (reference) =>
            reference.measureIndex == 0 &&
            reference.sectionId == SongSectionId('verse'),
      ),
      isTrue,
    );
  });

  test(
    'normalizes a tempo and meter changing range onto its start tempo with independent SongTimeMap onset timing',
    () {
      final tempoMap = song_time.TempoMap(<song_time.TempoChange>[
        song_time.TempoChange(
          at: song_time.BeatPosition.zero,
          bpm: song_time.Tempo(120),
        ),
        song_time.TempoChange(
          at: song_time.BeatPosition.fromBeats(4),
          bpm: song_time.Tempo(60),
        ),
      ]);
      final timeMap = SongTimeMap.fromTempoMap(tempoMap);
      final document = _document(
        tempoMap: tempoMap,
        meterMap: song_meter.MeterMap(<song_meter.MeterChange>[
          song_meter.MeterChange(atMeasure: 0, meter: song_meter.Meter(4, 4)),
          song_meter.MeterChange(atMeasure: 1, meter: song_meter.Meter(3, 4)),
        ]),
        track: StrumTrack(
          id: SongTrackId('strums'),
          name: 'Strums',
          instrument: _guitar,
          events: <SongStrumEvent>[
            SongStrumEvent(
              id: SongEventId('strum-5'),
              at: timeMap.timeAt(song_time.BeatPosition.fromBeats(5)),
              direction: StrumDirection.down,
            ),
            SongStrumEvent(
              id: SongEventId('strum-6'),
              at: timeMap.timeAt(song_time.BeatPosition.fromBeats(6)),
              direction: StrumDirection.up,
            ),
          ],
        ),
      );
      final config = _config(
        trackId: SongTrackId('strums'),
        range: MeasureRange(start: 1, endExclusive: 2),
        mode: TrainerMode.rhythm,
        targetSpeed: 0.5,
      );

      final compilation = SongPracticeCompiler.compile(
        document: document,
        config: config,
      );
      final definition = compilation.definition!;

      final rangeStart = timeMap.timeAt(song_time.BeatPosition.fromBeats(4));
      final independentOnset =
          timeMap.timeAt(song_time.BeatPosition.fromBeats(5)) - rangeStart;
      final independentTicks =
          (independentOnset.inMicroseconds *
                  60 *
                  BeatPosition.ticksPerBeat /
                  Duration.microsecondsPerMinute)
              .round();

      expect(definition.defaultTempo, const Tempo(60));
      expect(definition.meter, const Meter(beatsPerBar: 3));
      expect(definition.events.first.position.ticks, independentTicks);
      expect(definition.events.first.position, BeatPosition.fromTicks(480));
      expect(definition.totalBeats, BeatPosition.fromTicks(1440));
      expect(compilation.practiceConfig!.effectiveTempo, const Tempo(30));
      expect(
        compilation.eventReferences[definition.events.first.id],
        isA<SongEventReference>()
            .having((reference) => reference.songRevision, 'revision', 7)
            .having(
              (reference) => reference.trackId,
              'track',
              SongTrackId('strums'),
            )
            .having(
              (reference) => reference.eventId,
              'event',
              SongEventId('strum-5'),
            )
            .having((reference) => reference.measureIndex, 'measure', 1)
            .having(
              (reference) => reference.sectionId,
              'section',
              SongSectionId('chorus'),
            ),
      );
      expect(definition.validate(), isEmpty);
    },
  );

  test(
    'encodes every chord and rhythm capability profile without pitch scoring',
    () {
      final chord = SongPracticeCompiler.compile(
        document: _document(
          track: ChordTrack(
            id: SongTrackId('chords'),
            name: 'Chords',
            instrument: _guitar,
            events: <SongChordEvent>[
              SongChordEvent(
                id: SongEventId('chord'),
                start: Duration.zero,
                duration: const Duration(seconds: 1),
                symbol: Chord('C'),
              ),
            ],
          ),
        ),
        config: _config(
          trackId: SongTrackId('chords'),
          mode: TrainerMode.chord,
        ),
      );
      expect(chord.definition!.mode, PracticeMode.chordChanges);
      expect(
        chord.definition!.scoringProfile,
        ScoringProfile.chordChangeDefault,
      );
      expect(chord.definition!.events.single.chord, 'C');
      expect(chord.definition!.events.single.direction, isNull);

      final chordAndDirection = SongPracticeCompiler.compile(
        document: _document(
          extraTracks: <SongTrack>[
            ChordTrack(
              id: SongTrackId('chords'),
              name: 'Chords',
              instrument: _guitar,
              events: <SongChordEvent>[
                SongChordEvent(
                  id: SongEventId('chord'),
                  start: Duration.zero,
                  duration: const Duration(seconds: 1),
                  symbol: Chord('C'),
                ),
              ],
            ),
          ],
          track: StrumTrack(
            id: SongTrackId('strums'),
            name: 'Strums',
            instrument: _guitar,
            events: <SongStrumEvent>[
              SongStrumEvent(
                id: SongEventId('strum'),
                at: Duration.zero,
                direction: StrumDirection.down,
                targetChordId: SongEventId('chord'),
              ),
            ],
          ),
        ),
        config: _config(
          trackId: SongTrackId('strums'),
          mode: TrainerMode.rhythm,
        ),
      );
      expect(chordAndDirection.definition!.mode, PracticeMode.chordProgression);
      expect(
        chordAndDirection.definition!.scoringProfile,
        ScoringProfile.chordProgressionDefault,
      );
      expect(chordAndDirection.definition!.events.single.chord, 'C');
      expect(
        chordAndDirection.definition!.events.single.direction,
        StrumDirection.down,
      );
      expect(
        chordAndDirection.definition!.scoringProfile.weights.keys,
        containsAll(<PracticeScoreDimension>[
          PracticeScoreDimension.chord,
          PracticeScoreDimension.rhythm,
          PracticeScoreDimension.direction,
        ]),
      );

      final unknownDirection = SongPracticeCompiler.compile(
        document: _document(
          extraTracks: <SongTrack>[
            ChordTrack(
              id: SongTrackId('chords'),
              name: 'Chords',
              instrument: _guitar,
              events: <SongChordEvent>[
                SongChordEvent(
                  id: SongEventId('chord'),
                  start: Duration.zero,
                  duration: const Duration(seconds: 1),
                  symbol: Chord('C'),
                ),
              ],
            ),
          ],
          track: StrumTrack(
            id: SongTrackId('strums'),
            name: 'Strums',
            instrument: _guitar,
            events: <SongStrumEvent>[
              SongStrumEvent(
                id: SongEventId('strum'),
                at: Duration.zero,
                direction: null,
                targetChordId: SongEventId('chord'),
              ),
            ],
          ),
        ),
        config: _config(
          trackId: SongTrackId('strums'),
          mode: TrainerMode.rhythm,
        ),
      );
      expect(unknownDirection.definition!.mode, PracticeMode.chordChanges);
      expect(unknownDirection.definition!.events.single.direction, isNull);
      expect(unknownDirection.definition!.events.single.chord, 'C');
      expect(
        unknownDirection.definition!.scoringProfile.weights,
        const <PracticeScoreDimension, int>{
          PracticeScoreDimension.chord: 60,
          PracticeScoreDimension.rhythm: 40,
        },
      );

      final strumOnly = SongPracticeCompiler.compile(
        document: _document(
          track: StrumTrack(
            id: SongTrackId('strums'),
            name: 'Strums',
            instrument: _guitar,
            events: <SongStrumEvent>[
              SongStrumEvent(
                id: SongEventId('strum'),
                at: Duration.zero,
                direction: StrumDirection.up,
              ),
            ],
          ),
        ),
        config: _config(
          trackId: SongTrackId('strums'),
          mode: TrainerMode.rhythm,
        ),
      );
      expect(strumOnly.definition!.mode, PracticeMode.strumPattern);
      expect(
        strumOnly.definition!.scoringProfile,
        ScoringProfile.legacyLearnParity,
      );

      final rhythmOnly = SongPracticeCompiler.compile(
        document: _document(
          track: NoteTrack(
            id: SongTrackId('notes'),
            name: 'Notes',
            instrument: _guitar,
            events: <SongNoteEvent>[
              SongNoteEvent(
                id: SongEventId('note'),
                start: Duration.zero,
                duration: const Duration(seconds: 1),
                midiPitch: 60,
              ),
            ],
          ),
        ),
        config: _config(
          trackId: SongTrackId('notes'),
          mode: TrainerMode.rhythm,
        ),
      );
      expect(rhythmOnly.definition!.mode, PracticeMode.rhythmOnly);
      expect(
        rhythmOnly.definition!.scoringProfile,
        ScoringProfile.rhythmOnlyDefault,
      );
      expect(
        rhythmOnly.definition!.events.single.direction,
        StrumDirection.down,
      );
      expect(rhythmOnly.definition!.events.single.chord, isNull);
      expect(
        rhythmOnly.definition!.scoringProfile.weights,
        const <PracticeScoreDimension, int>{PracticeScoreDimension.rhythm: 100},
      );

      final playbackOnly = SongPracticeCompiler.compile(
        document: _document(
          track: NoteTrack(
            id: SongTrackId('notes'),
            name: 'Notes',
            instrument: _guitar,
            events: <SongNoteEvent>[
              SongNoteEvent(
                id: SongEventId('note'),
                start: Duration.zero,
                duration: const Duration(seconds: 1),
                midiPitch: 60,
              ),
            ],
          ),
        ),
        config: _config(trackId: SongTrackId('notes'), mode: TrainerMode.pitch),
      );
      expect(playbackOnly.isPlaybackOnly, isTrue);
      expect(playbackOnly.definition, isNull);
      expect(playbackOnly.practiceConfig, isNull);
    },
  );

  test(
    'maps every final-practice verdict back to measure and section aggregates',
    () {
      final compilation = SongPracticeCompiler.compile(
        document: _document(
          track: StrumTrack(
            id: SongTrackId('strums'),
            name: 'Strums',
            instrument: _guitar,
            events: <SongStrumEvent>[
              SongStrumEvent(
                id: SongEventId('strum'),
                at: Duration.zero,
                direction: StrumDirection.down,
              ),
            ],
          ),
        ),
        config: _config(
          trackId: SongTrackId('strums'),
          mode: TrainerMode.rhythm,
        ),
      );
      final targetId = '${compilation.definition!.events.single.id}@0';
      final result = PracticeSessionResult(
        id: 'practice-1',
        activeDuration: const Duration(seconds: 1),
        pausedDuration: Duration.zero,
        finishReason: PracticeFinishReason.completedAllTargets,
        highestStableTempo: const Tempo(120),
        coachingSummary: const <String>[],
        attempts: <PracticeAttemptResult>[
          PracticeAttemptResult(
            index: 0,
            tempo: const Tempo(120),
            metrics: _metrics,
            outcome: PracticeAttemptOutcome.passed,
            verdicts: <PracticeVerdict>[
              PracticeVerdict(
                targetEventId: targetId,
                matchedObservationSequence: 1,
                targetAt: Duration.zero,
                observedAt: Duration.zero,
                timingOffset: Duration.zero,
                timingGrade: TimingGrade.perfect,
                expectedDirection: StrumDirection.down,
                observedDirection: StrumDirection.down,
                directionOutcome: DirectionOutcome.correct,
                expectedChord: null,
                observedChord: null,
                chordOutcome: ChordOutcome.notApplicable,
                eventScore: 1,
                missReasonCode: null,
                coachingCode: null,
              ),
            ],
          ),
        ],
      );

      final mapped = SongResultMapper.map(
        sessionResult: result,
        references: compilation.eventReferences,
      );

      expect(mapped.verdicts, hasLength(1));
      expect(mapped.verdicts.single.reference.eventId, SongEventId('strum'));
      expect(mapped.measureResults.single.measureIndex, 0);
      expect(mapped.measureResults.single.averageEventScore, 1);
      expect(mapped.sectionResults.single.sectionId, SongSectionId('verse'));
    },
  );
}

final SongInstrument _guitar = SongInstrument(name: 'Guitar');

const PracticeMetrics _metrics = PracticeMetrics(
  completion: MetricAvailable(1),
  rhythm: MetricAvailable(1),
  direction: MetricAvailable(1),
  chord: MetricNotApplicable(),
  overall: MetricAvailable(1),
  totalTargets: 1,
  resolvedTargets: 1,
  maxCombo: 1,
  scorePoints: 100,
  meanAbsoluteOffset: Duration.zero,
  timingBias: Duration.zero,
);

SongDocument _document({
  required SongTrack track,
  song_time.TempoMap? tempoMap,
  song_meter.MeterMap? meterMap,
  List<SongTrack> extraTracks = const <SongTrack>[],
}) {
  final now = DateTime.utc(2026, 8, 4);
  return SongDocument(
    schemaVersion: songDocumentSchemaVersion,
    id: SongId('song'),
    revision: 7,
    metadata: SongMetadata(title: 'Reference song'),
    source: SongSource(
      type: SongSourceType.createdInApp,
      originalFileName: 'reference.song',
      sha256: 'a' * 64,
      importedAt: now,
      importerVersion: 'test@1',
    ),
    createdAt: now,
    updatedAt: now,
    sections: <SongSection>[
      SongSection(
        id: SongSectionId('verse'),
        name: 'Verse',
        startMeasure: 0,
        endMeasureExclusive: 1,
      ),
      SongSection(
        id: SongSectionId('chorus'),
        name: 'Chorus',
        startMeasure: 1,
        endMeasureExclusive: 2,
      ),
    ],
    measures: <SongMeasure>[
      SongMeasure(index: 0, durationBeats: song_time.BeatPosition.fromBeats(4)),
      SongMeasure(index: 1, durationBeats: song_time.BeatPosition.fromBeats(3)),
    ],
    tempoMap: tempoMap ?? song_time.TempoMap.constant(song_time.Tempo(120)),
    meterMap: meterMap ?? song_meter.MeterMap.constant(song_meter.Meter(4, 4)),
    tracks: <SongTrack>[track, ...extraTracks],
  );
}

TrainerConfig _config({
  required SongTrackId trackId,
  required TrainerMode mode,
  MeasureRange? range,
  double targetSpeed = 1,
}) {
  final resolvedRange = range ?? MeasureRange(start: 0, endExclusive: 2);
  return TrainerConfig(
    songId: SongId('song'),
    songRevision: 7,
    trackId: trackId,
    selection: resolvedRange,
    range: resolvedRange,
    mode: mode,
    targetSpeed: targetSpeed,
    countInBars: 1,
    metronomeEnabled: true,
    loopConfig: LoopConfig(range: resolvedRange),
    tuningReminder: null,
    capo: 0,
    capoReminder: false,
  );
}
