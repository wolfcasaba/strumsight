import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/chords/public.dart';
import 'package:strumsight/features/learn/audio/chord_audition.dart';
import 'package:strumsight/features/learn/providers/chord_audition_provider.dart';

/// Records what would have reached the speaker, without a platform channel —
/// the same seam [WavPlayback] gives `SynthChordAudition`.
final class _RecordingWavPlayback implements WavPlayback {
  final List<Uint8List> played = [];
  var stopCalls = 0;
  var disposeCalls = 0;

  @override
  Future<void> play(Uint8List wav) async => played.add(wav);

  @override
  Future<void> stop() async => stopCalls++;

  @override
  Future<void> dispose() async => disposeCalls++;
}

/// A minimal [ChordAudition] fake for the provider's autodispose contract.
final class _FakeAudition implements ChordAudition {
  var disposed = false;

  @override
  Future<void> strum(
    String label, {
    StrumDirection direction = StrumDirection.down,
  }) async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async => disposed = true;
}

void main() {
  group('SynthChordAudition.resolve', () {
    test('a label with a fingering resolves to its diagram', () {
      final voicing = SynthChordAudition.resolve('C');
      expect(voicing.source, AuditionSource.fingering);
      expect(voicing.freqs, hasLength(5));
      expect(voicing.freqs.first, closeTo(130.81, 0.5)); // C3
      expect(voicing.isPlayable, isTrue);
    });

    test('junk input resolves to nothing playable', () {
      final voicing = SynthChordAudition.resolve('Zz9');
      expect(voicing.source, AuditionSource.none);
      expect(voicing.isPlayable, isFalse);
      expect(voicing.freqs, isEmpty);
    });

    test('a parseable label without a diagram falls back to chord tones', () {
      // 'Ebm' is not in ChordShapes (no fingering diagram for it) but IS
      // parseable by ChordAudio's root+quality parser.
      expect(ChordShapes.has('Ebm'), isFalse);
      final voicing = SynthChordAudition.resolve('Ebm');
      expect(voicing.source, AuditionSource.chordTones);
      expect(voicing.freqs, hasLength(3));
      expect(voicing.isPlayable, isTrue);
    });

    test('a known root with an UNKNOWN quality is silence, not a major', () {
      // ADR 0535 D1 / review F8: "Cdim" must not sound as C major.
      for (final label in ['Cdim', 'C5', 'Cm6', 'Cwhatever']) {
        final voicing = SynthChordAudition.resolve(label);
        expect(voicing.source, AuditionSource.none, reason: label);
        expect(voicing.isPlayable, isFalse, reason: label);
      }
    });

    test('an empty label resolves to nothing playable', () {
      final voicing = SynthChordAudition.resolve('');
      expect(voicing.source, AuditionSource.none);
      expect(voicing.isPlayable, isFalse);
    });
  });

  group('SynthChordAudition', () {
    test('strumming a playable chord reaches the playback once', () async {
      final playback = _RecordingWavPlayback();
      final audition = SynthChordAudition(playback: playback);
      await audition.strum('C');
      expect(playback.played, hasLength(1));
    });

    test('strumming junk reaches the playback zero times', () async {
      final playback = _RecordingWavPlayback();
      final audition = SynthChordAudition(playback: playback);
      await audition.strum('Zz9');
      expect(playback.played, isEmpty);
    });

    test('the same stroke twice is one cache entry', () async {
      final playback = _RecordingWavPlayback();
      final audition = SynthChordAudition(playback: playback);
      await audition.strum('C');
      await audition.strum('C');
      expect(audition.cacheSize, 1);
      expect(playback.played, hasLength(2));
    });

    test('opposite directions are cached apart and sound different', () async {
      final playback = _RecordingWavPlayback();
      final audition = SynthChordAudition(playback: playback);
      await audition.strum('C');
      await audition.strum('C', direction: StrumDirection.up);
      expect(audition.cacheSize, 2);
      expect(playback.played, hasLength(2));
      expect(playback.played[0], isNot(equals(playback.played[1])));
    });

    test('the LRU cache never grows past maxCachedStrokes', () async {
      final playback = _RecordingWavPlayback();
      final audition = SynthChordAudition(playback: playback);
      for (final label in ChordShapes.allLabels) {
        for (final direction in StrumDirection.values) {
          await audition.strum(label, direction: direction);
        }
      }
      // ChordShapes.allLabels has well over 12 entries, so
      // (labels * 2 directions) comfortably exceeds the 24-entry bound.
      expect(
        ChordShapes.allLabels.length * StrumDirection.values.length,
        greaterThan(SynthChordAudition.maxCachedStrokes),
      );
      expect(audition.cacheSize, SynthChordAudition.maxCachedStrokes);
    });

    test('a cache HIT refreshes recency — the LRU is not a FIFO', () async {
      final playback = _RecordingWavPlayback();
      final audition = SynthChordAudition(playback: playback);
      await audition.strum('C');
      await audition.strum('G');
      await audition.strum('Am');
      await audition.strum('C'); // hit — C becomes the newest again
      expect(audition.debugCacheKeys, ['G:down', 'Am:down', 'C:down']);
    });

    test('stop forwards to the playback', () async {
      final playback = _RecordingWavPlayback();
      final audition = SynthChordAudition(playback: playback);
      await audition.stop();
      expect(playback.stopCalls, 1);
    });

    test('dispose forwards to the playback and clears the cache', () async {
      final playback = _RecordingWavPlayback();
      final audition = SynthChordAudition(playback: playback);
      await audition.strum('C');
      expect(audition.cacheSize, 1);
      await audition.dispose();
      expect(playback.disposeCalls, 1);
      expect(audition.cacheSize, 0);
    });
  });

  group('chordAuditionProvider', () {
    test('resolves to a SynthChordAudition', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(chordAuditionProvider), isA<SynthChordAudition>());
    });

    test('tearing down the container disposes the audition (autoDispose)', () {
      final fake = _FakeAudition();
      final container = ProviderContainer(
        overrides: [
          chordAuditionProvider.overrideWith((ref) {
            ref.onDispose(fake.dispose);
            return fake;
          }),
        ],
      );
      container.listen(chordAuditionProvider, (_, _) {});
      expect(fake.disposed, isFalse);

      container.dispose();

      expect(fake.disposed, isTrue);
    });
  });
}
