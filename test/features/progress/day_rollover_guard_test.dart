import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/day_rollover_guard.dart';
import 'package:strumsight/core/platform/platform_providers.dart';
import 'package:strumsight/features/gamification/providers/gamification_providers.dart';
import 'package:strumsight/features/progress_v2/application/progress_providers.dart';

import '../../support/fake_audio.dart' show FakeAppLifecycleEvents;

/// ADR 0583 — `todayEpochDayProvider` and `progressNowProvider` are plain
/// cached `Provider`s, so an app left in the background across midnight kept
/// evaluating the streak against YESTERDAY until a cold restart. Coming back
/// to the foreground is the moment the user can see the answer, so it is the
/// moment to recompute it.
void main() {
  late FakeAppLifecycleEvents lifecycle;
  late int dayTicks;
  late int nowTicks;

  ProviderContainer container() {
    final c = ProviderContainer(
      overrides: [
        appLifecycleEventsProvider.overrideWithValue(lifecycle),
        // Each build answers a new value, so "did it rebuild?" is observable
        // without waiting for a real midnight.
        todayEpochDayProvider.overrideWith((_) => dayTicks++),
        progressNowProvider.overrideWith(
          (_) => DateTime.utc(2026, 9, 18).add(Duration(days: nowTicks++)),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    lifecycle = FakeAppLifecycleEvents();
    dayTicks = 0;
    nowTicks = 0;
  });

  test('resuming recomputes today and now', () {
    final c = container();
    c.read(dayRolloverGuardProvider);
    expect(c.read(todayEpochDayProvider), 0);
    expect(c.read(progressNowProvider), DateTime.utc(2026, 9, 18));

    lifecycle.emit(AppLifecycleState.resumed);

    expect(c.read(todayEpochDayProvider), 1);
    expect(c.read(progressNowProvider), DateTime.utc(2026, 9, 19));
  });

  test('backgrounding alone does not recompute anything', () {
    final c = container();
    c.read(dayRolloverGuardProvider);
    expect(c.read(todayEpochDayProvider), 0);

    lifecycle.emit(AppLifecycleState.inactive);
    lifecycle.emit(AppLifecycleState.paused);
    lifecycle.emit(AppLifecycleState.hidden);

    expect(
      c.read(todayEpochDayProvider),
      0,
      reason: 'the day cannot have rolled over while the app was not shown',
    );
  });

  test('the listener is released with the container', () {
    final c = ProviderContainer(
      overrides: [appLifecycleEventsProvider.overrideWithValue(lifecycle)],
    );
    c.read(dayRolloverGuardProvider);
    expect(lifecycle.listeners, hasLength(1));

    c.dispose();

    expect(
      lifecycle.listeners,
      isEmpty,
      reason: 'AGENTS.md §7 — every lifecycle resource is released',
    );
  });
}
