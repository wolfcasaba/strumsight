import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/music/strum.dart';
import 'package:strumsight/features/learn/public.dart' show ChordAudition;
import 'package:strumsight/features/songs/application/song_preview_player.dart';

/// The default gentle pattern SongBuilderScreen seeds new songs with:
/// downs on every beat.
const _defaultPattern = <StrumDirection?>[
  StrumDirection.down, null, StrumDirection.down, null, //
  StrumDirection.down, null, StrumDirection.down, null,
];

/// Records what the preview asked to be strummed, and how many times it was
/// told to stop — no platform channel involved.
final class _RecordingAudition implements ChordAudition {
  final List<String> strummed = [];
  final List<StrumDirection> directions = [];
  var stopCalls = 0;

  @override
  Future<void> strum(
    String label, {
    StrumDirection direction = StrumDirection.down,
  }) async {
    strummed.add(label);
    directions.add(direction);
  }

  @override
  Future<void> stop() async => stopCalls++;

  @override
  Future<void> dispose() async {}
}

void main() {
  group('previewSchedule', () {
    test('4/4, the default pattern, 90 bpm: 8 strums across two bars', () {
      final schedule = previewSchedule(
        chords: const ['C', 'G'],
        pattern: _defaultPattern,
        bpm: 90,
        beatsPerBar: 4,
      );
      expect(schedule, hasLength(8));

      final bar0 = schedule.where((s) => s.bar == 0).toList();
      expect(bar0.map((s) => s.timeSec).toList(), [
        closeTo(0, 1e-6),
        closeTo(0.666667, 1e-6),
        closeTo(1.333333, 1e-6),
        closeTo(2.0, 1e-6),
      ]);
      expect(bar0.every((s) => s.chord == 'C'), isTrue);
      expect(bar0.every((s) => s.direction == StrumDirection.down), isTrue);

      final bar1 = schedule.where((s) => s.bar == 1).toList();
      expect(bar1.first.timeSec, closeTo(2.666667, 1e-6));
      expect(bar1.every((s) => s.chord == 'G'), isTrue);
    });

    test('3/4, a full 6-slot down/up pattern, 120 bpm', () {
      final schedule = previewSchedule(
        chords: const ['C', 'G'],
        pattern: const [
          StrumDirection.down,
          StrumDirection.up,
          StrumDirection.down,
          StrumDirection.up,
          StrumDirection.down,
          StrumDirection.up,
        ],
        bpm: 120,
        beatsPerBar: 3,
      );

      final bar0 = schedule.where((s) => s.bar == 0).toList();
      expect(bar0.map((s) => s.timeSec).toList(), [
        closeTo(0, 1e-6),
        closeTo(0.25, 1e-6),
        closeTo(0.5, 1e-6),
        closeTo(0.75, 1e-6),
        closeTo(1.0, 1e-6),
        closeTo(1.25, 1e-6),
      ]);
      expect(bar0.map((s) => s.direction).toList(), [
        StrumDirection.down,
        StrumDirection.up,
        StrumDirection.down,
        StrumDirection.up,
        StrumDirection.down,
        StrumDirection.up,
      ]);

      final bar1 = schedule.where((s) => s.bar == 1).toList();
      expect(bar1.first.timeSec, closeTo(1.5, 1e-6));
    });

    test('a non-positive tempo yields nothing', () {
      expect(
        previewSchedule(
          chords: const ['C'],
          pattern: _defaultPattern,
          bpm: 0,
          beatsPerBar: 4,
        ),
        isEmpty,
      );
    });

    test('an empty progression yields nothing', () {
      expect(
        previewSchedule(
          chords: const [],
          pattern: _defaultPattern,
          bpm: 90,
          beatsPerBar: 4,
        ),
        isEmpty,
      );
    });

    test('a pattern longer than beatsPerBar*2 is truncated, not spilled', () {
      final schedule = previewSchedule(
        chords: const ['C'],
        pattern: List<StrumDirection?>.filled(10, StrumDirection.down),
        bpm: 60,
        beatsPerBar: 4,
      );
      // Only 8 slots exist in one 4/4 bar; the trailing 2 pattern entries
      // are never read.
      expect(schedule, hasLength(8));
      expect(schedule.every((s) => s.bar == 0), isTrue);
      expect(schedule.last.timeSec, closeTo(3.5, 1e-6));
    });

    test('a pattern shorter than the bar is rest-padded, not repeated', () {
      final schedule = previewSchedule(
        chords: const ['C'],
        pattern: const [StrumDirection.down, null],
        bpm: 60,
        beatsPerBar: 4,
      );
      expect(schedule, hasLength(1));
      expect(schedule.single.timeSec, closeTo(0, 1e-6));
    });
  });

  group('SongPreviewController', () {
    testWidgets('start strums immediately, reports bar 0, and is playing', (
      tester,
    ) async {
      final audition = _RecordingAudition();
      final controller = SongPreviewController(audition);
      addTearDown(controller.dispose);

      controller.start(
        chords: const ['C', 'G'],
        pattern: _defaultPattern,
        bpm: 90,
        beatsPerBar: 4,
      );

      expect(audition.strummed, ['C']);
      expect(controller.currentBar, 0);
      expect(controller.isPlaying, isTrue);
    });

    testWidgets(
      'the bar advances and the next chord sounds, then playback ends and '
      'stops on its own',
      (tester) async {
        final audition = _RecordingAudition();
        final controller = SongPreviewController(audition);
        addTearDown(controller.dispose);
        var notifications = 0;
        controller.addListener(() => notifications++);

        controller.start(
          chords: const ['C', 'G'],
          pattern: _defaultPattern,
          bpm: 90,
          beatsPerBar: 4,
        );
        await tester.pump();

        await tester.pump(const Duration(milliseconds: 2700));
        expect(controller.currentBar, 1);
        expect(audition.strummed, contains('G'));

        // Total schedule length is 2 bars * 4 beats * 60/90 s ≈ 5.333 s;
        // 2.7 s already elapsed, so a further 3 s clears the end + margin.
        await tester.pump(const Duration(seconds: 3));

        expect(controller.isPlaying, isFalse);
        expect(controller.currentBar, isNull);
        expect(audition.stopCalls, greaterThanOrEqualTo(1));
        // start (bar 0), bar change (bar 1), stop.
        expect(notifications, greaterThanOrEqualTo(3));
      },
    );

    testWidgets('stop() mid-way cancels the timer chain — no further strums', (
      tester,
    ) async {
      final audition = _RecordingAudition();
      final controller = SongPreviewController(audition);
      addTearDown(controller.dispose);

      controller.start(
        chords: const ['C', 'G'],
        pattern: _defaultPattern,
        bpm: 90,
        beatsPerBar: 4,
      );
      await tester.pump(const Duration(milliseconds: 700));
      final strummedAtStop = List<String>.of(audition.strummed);

      controller.stop();
      expect(controller.isPlaying, isFalse);

      await tester.pump(const Duration(seconds: 10));
      expect(audition.strummed, strummedAtStop);
    });

    testWidgets('dispose() mid-way stops the audition without throwing', (
      tester,
    ) async {
      final audition = _RecordingAudition();
      final controller = SongPreviewController(audition);

      controller.start(
        chords: const ['C', 'G'],
        pattern: _defaultPattern,
        bpm: 90,
        beatsPerBar: 4,
      );
      await tester.pump(const Duration(milliseconds: 500));

      controller.dispose();
      expect(audition.stopCalls, greaterThanOrEqualTo(1));

      // Any pending timer must be cancelled by dispose — pumping further
      // must not throw (a disposed ChangeNotifier asserts on
      // notifyListeners) and must not resume strumming.
      final strummedAtDispose = List<String>.of(audition.strummed);
      await tester.pump(const Duration(seconds: 10));
      expect(audition.strummed, strummedAtDispose);
      expect(tester.takeException(), isNull);
    });

    testWidgets('starting with an empty progression never starts playing', (
      tester,
    ) async {
      final audition = _RecordingAudition();
      final controller = SongPreviewController(audition);
      addTearDown(controller.dispose);

      controller.start(
        chords: const [],
        pattern: _defaultPattern,
        bpm: 90,
        beatsPerBar: 4,
      );

      expect(controller.isPlaying, isFalse);
      expect(controller.currentBar, isNull);
      expect(audition.strummed, isEmpty);
    });
  });
}
