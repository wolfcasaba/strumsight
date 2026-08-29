import 'package:flutter_test/flutter_test.dart';

import 'fake_practice_session_clock.dart';
import 'fake_practice_tick_source.dart';

/// The e2e harness's single time source (E12-R11, ADR 0472 D3).
///
/// [FakePracticeSessionClock] is a synchronous snapshot and
/// [FakePracticeTickSource] is the async delivery mechanism the controller's
/// `ClockAdvanced` input rides on. A caller that advances one without driving
/// the other leaves the async side observing a stale `now` relative to what
/// the sync clock already reports — the exact divergence
/// [L122](../../docs/LESSONS.md#l122) catalogued. [HarnessClock.tick] closes
/// that gap: it is the ONLY way this harness advances time, and it always
/// advances the clock, fires the tick, and pumps the widget tree by the same
/// duration in one call, so the two can never disagree.
///
/// No ambient wall clock, no ambient RNG — every advance is caller-driven.
final class HarnessClock {
  HarnessClock()
    : clock = FakePracticeSessionClock(),
      tickSource = FakePracticeTickSource();

  /// The synchronous snapshot the practice session controller reads.
  final FakePracticeSessionClock clock;

  /// The async delivery mechanism the controller's tick-driven transitions
  /// (count-in completion, timeline completion, finishing → completed) ride
  /// on.
  final FakePracticeTickSource tickSource;

  /// Advances [clock] by [by], fires exactly one tick on [tickSource], and
  /// pumps [tester] by the same duration so the widget tree, the clock, and
  /// the tick stream all agree on how much time just passed.
  Future<void> tick(WidgetTester tester, Duration by) async {
    clock.advance(by);
    tickSource.emitTick();
    await tester.pump(by);
  }
}
