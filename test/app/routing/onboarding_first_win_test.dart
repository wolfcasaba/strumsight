import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/app/routing/app_route.dart';
import 'package:strumsight/app/routing/app_router.dart';
import 'package:strumsight/app/strumsight_app.dart';
import 'package:strumsight/core/storage/key_value_store.dart';
import 'package:strumsight/core/storage/storage_keys.dart';
import 'package:strumsight/core/storage/storage_providers.dart';
import 'package:strumsight/features/learn/public.dart';
import 'package:strumsight/features/live/providers/live_providers.dart';
import 'package:strumsight/features/onboarding/onboarding_provider.dart';
import 'package:strumsight/features/onboarding/screens/onboarding_screen.dart';

import '../../support/fake_audio.dart';
import '../../support/fake_engines.dart';
import '../../support/preference_store.dart';

class _DelayedBoolWriteStore implements KeyValueStore {
  _DelayedBoolWriteStore(this._delegate);

  final KeyValueStore _delegate;
  static const delay = Duration(seconds: 2);
  bool boolWriteCompleted = false;

  @override
  bool contains(String key) => _delegate.contains(key);

  @override
  bool? readBool(String key) => _delegate.readBool(key);

  @override
  double? readDouble(String key) => _delegate.readDouble(key);

  @override
  int? readInt(String key) => _delegate.readInt(key);

  @override
  String? readString(String key) => _delegate.readString(key);

  @override
  List<String>? readStringList(String key) => _delegate.readStringList(key);

  @override
  Future<void> remove(String key) => _delegate.remove(key);

  @override
  Future<void> writeBool(String key, bool value) async {
    await Future<void>.delayed(delay);
    await _delegate.writeBool(key, value);
    boolWriteCompleted = true;
  }

  @override
  Future<void> writeDouble(String key, double value) =>
      _delegate.writeDouble(key, value);

  @override
  Future<void> writeInt(String key, int value) =>
      _delegate.writeInt(key, value);

  @override
  Future<void> writeString(String key, String value) =>
      _delegate.writeString(key, value);

  @override
  Future<void> writeStringList(String key, List<String> value) =>
      _delegate.writeStringList(key, value);
}

void main() {
  testWidgets(
    'default first-win survives reactive redirect during delayed persistence',
    (tester) async {
      final memory = InMemoryKeyValueStore();
      final store = _DelayedBoolWriteStore(memory);
      final engine = FakeStrumEngine();
      final container = ProviderContainer(
        overrides: [
          keyValueStoreProvider.overrideWithValue(store),
          ...fakeAudioOverrides(),
          strumEngineProvider.overrideWithValue(engine),
          onboardingSeenProvider.overrideWith(
            () => OnboardingController(false),
          ),
        ],
      );
      final router = container.read(routerProvider);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        container.dispose();
        await engine.dispose();
      });

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const StrumSightApp(),
        ),
      );
      await tester.pumpAndSettle();
      expect(router.state.uri.path, AppRoutes.welcome);

      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Next'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Try your first win — 30 seconds'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(container.read(onboardingSeenProvider), isTrue);
      // E16-R06 (ADR 0508 D1/D2): `onboarding_screen.dart`'s
      // `_completeFirstWin` now navigates via `entryLocationFor(...)`, the
      // SAME source `app_router.dart` reads — with the adaptive shell on by
      // default this is /today both here (a reactive redirect fires as soon
      // as `onboardingSeenProvider` flips true, independent of
      // `_completeFirstWin` itself, which is still mid-persist) and once
      // settled below. The LearnScreen push (root-navigator, independent of
      // the current shell tab) is what actually delivers the first-win
      // lesson either way.
      expect(router.state.uri.path, AppRoutes.today);
      expect(find.byType(OnboardingScreen), findsNothing);
      expect(store.boolWriteCompleted, isFalse);
      expect(memory.readBool(StorageKeys.onboardingSeen), isNull);

      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(store.boolWriteCompleted, isTrue);
      // E16-R06 (ADR 0508 D2, A3): `_completeFirstWin`'s own `router.go`
      // call — deferred until here by the delayed persistence above — now
      // targets `entryLocationFor(true)` (/today) instead of the old
      // hardcoded `AppRoutes.live`, so the settled location matches the
      // entry point instead of drifting to legacyRedirects' /practice/live
      // target. The location and the push are asserted together: this is
      // the "pair" A3 requires, not just one or the other.
      expect(router.state.uri.path, AppRoutes.today);
      final learn = tester.widget<LearnScreen>(find.byType(LearnScreen));
      expect(learn.lesson.id, Lessons.firstWin.id);
    },
  );
}
