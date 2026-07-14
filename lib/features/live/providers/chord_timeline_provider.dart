import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/chord_event.dart';
import '../model/live_frame.dart';
import 'live_providers.dart';

/// Fold a live engine [frame] into the rolling chord-timeline [buffer].
///
/// A **pure** function: it never mutates [buffer] and always returns a new
/// list, so it is directly unit-/property-testable without a ProviderContainer.
///
/// Rules (in order):
///  1. `frame.current == null` (idle) → return the buffer unchanged.
///  2. Same chord as the last card (consecutive dedupe): if a strum just
///     landed, update the last card's direction/confidence in place; otherwise
///     leave the buffer unchanged. Never append — re-detecting the same chord
///     must NOT spawn a new card.
///  3. Changed/new chord (A→B, or A→B→A which IS a new card) → append a fresh
///     [ChordEvent], then trim from the FRONT so `length ≤ cap`. Newest last.
List<ChordEvent> reduceChordTimeline(
  List<ChordEvent> buffer,
  LiveFrame frame, {
  int cap = 6,
}) {
  final current = frame.current;
  // Rule 1 — idle frame, nothing to push.
  if (current == null) return buffer;

  final strum = frame.latestStrum;

  // Rule 2 — same chord still sounding: dedupe, but reflect the latest strum.
  if (buffer.isNotEmpty && buffer.last.chord.label == current.label) {
    if (strum == null) return buffer;
    final last = buffer.last;
    // `latestStrum` is STICKY (the most recent strum, not a per-frame event),
    // so this branch runs on every frame while a chord holds. Return the SAME
    // list reference when nothing actually changed — otherwise the notifier
    // emits an equal-but-new list ~15 fps and needlessly rebuilds the timeline.
    if (last.direction == strum.direction && last.confidence == strum.confidence) {
      return buffer;
    }
    final updated = last.copyWith(
      direction: strum.direction,
      confidence: strum.confidence,
    );
    return [
      ...buffer.sublist(0, buffer.length - 1),
      updated,
    ];
  }

  // Rule 3 — changed/new chord: append a new card.
  final event = ChordEvent(
    chord: current,
    direction: strum?.direction,
    confidence: strum?.confidence ?? frame.confidence,
    seq: buffer.isEmpty ? 0 : buffer.last.seq + 1,
    timeSec:
        frame.latestStrumTime >= 0 ? frame.latestStrumTime : frame.engineTimeSec,
  );
  final appended = [...buffer, event];
  // Trim from the front so the newest cards are always kept (newest last).
  if (appended.length > cap) {
    return appended.sublist(appended.length - cap);
  }
  return appended;
}

/// Rolling history of recognised chords, folded from [liveFrameProvider].
///
/// The reduction lives in the pure [reduceChordTimeline] so the controller is
/// a thin Riverpod wrapper — all logic stays testable without widgets.
///
/// **autoDispose is load-bearing:** [liveFrameProvider] is itself autoDispose —
/// it `engine.start()`s on first listen and `engine.stop()`s (releasing the
/// mic) when its last listener goes away. A non-autoDispose provider here would
/// hold a permanent `ref.listen` on it, pinning the mic/DSP on for the app's
/// whole lifetime even after the user leaves Live. Being autoDispose, this
/// controller dies with the Live screen, its listen unsubscribes, and the mic
/// stops. It also gives each Live visit a fresh, empty history.
class ChordTimelineController extends Notifier<List<ChordEvent>> {
  @override
  List<ChordEvent> build() {
    ref.listen(liveFrameProvider, (prev, next) {
      final frame = next.value;
      if (frame != null) {
        state = reduceChordTimeline(state, frame);
      }
    });
    return const [];
  }
}

/// The Live chord-timeline history buffer (newest last, capped ring buffer).
final chordTimelineProvider =
    NotifierProvider.autoDispose<ChordTimelineController, List<ChordEvent>>(
  ChordTimelineController.new,
);
