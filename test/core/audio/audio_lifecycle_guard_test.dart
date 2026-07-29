import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/core/audio/lifecycle/audio_lifecycle_guard.dart';
import 'package:strumsight/core/audio/lifecycle/audio_session_coordinator.dart';
import 'package:strumsight/core/audio/lifecycle/audio_session_lease.dart';

import '../../support/fake_audio.dart';

/// E01-R09 §9.4 — the microphone dies when the app leaves the foreground, and
/// coming back does NOT turn it on again.
void main() {
  ({
    AudioSessionCoordinator coordinator,
    FakeAppLifecycleEvents lifecycle,
    AudioLifecycleGuard guard,
  })
  rig() {
    final coordinator = AudioSessionCoordinator();
    final lifecycle = FakeAppLifecycleEvents();
    final guard = AudioLifecycleGuard(
      coordinator: coordinator,
      events: lifecycle,
    );
    addTearDown(guard.dispose);
    return (coordinator: coordinator, lifecycle: lifecycle, guard: guard);
  }

  test('backgrounding stops the active owner', () async {
    final r = rig();
    var teardowns = 0;
    await r.coordinator.acquire(
      AudioOwner.live,
      onRevoke: () async => teardowns++,
    );

    r.lifecycle.emit(AppLifecycleState.paused);
    await Future<void>.delayed(Duration.zero);

    expect(teardowns, 1);
    expect(r.coordinator.activeOwner, isNull);
  });

  test('resuming does NOT restart the microphone', () async {
    final r = rig();
    var teardowns = 0;
    await r.coordinator.acquire(
      AudioOwner.live,
      onRevoke: () async => teardowns++,
    );

    r.lifecycle.emit(AppLifecycleState.paused);
    await Future<void>.delayed(Duration.zero);
    r.lifecycle.emit(AppLifecycleState.resumed);
    await Future<void>.delayed(Duration.zero);

    expect(teardowns, 1);
    expect(
      r.coordinator.activeOwner,
      isNull,
      reason:
          'a mic that turns itself back on unseen is exactly what §9.4 bans',
    );
  });

  test('a transient inactive (notification shade) keeps the session', () async {
    final r = rig();
    var teardowns = 0;
    await r.coordinator.acquire(
      AudioOwner.live,
      onRevoke: () async => teardowns++,
    );

    r.lifecycle.emit(AppLifecycleState.inactive);
    await Future<void>.delayed(Duration.zero);

    expect(teardowns, 0);
    expect(r.coordinator.activeOwner, AudioOwner.live);
  });

  test('a disposed guard stops listening', () async {
    final r = rig();
    var teardowns = 0;
    await r.coordinator.acquire(
      AudioOwner.tuner,
      onRevoke: () async => teardowns++,
    );

    r.guard.dispose();
    r.lifecycle.emit(AppLifecycleState.paused);
    await Future<void>.delayed(Duration.zero);

    expect(teardowns, 0);
    expect(r.lifecycle.listeners, isEmpty);
  });
}
