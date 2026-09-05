import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../live/public.dart';
import 'first_win_engine.dart';

/// The round-local success threshold (ADR 0281 §2 Döntés-pont 2; P1
/// measured). Deliberately NOT `confidenceThresholdProvider`
/// (`lib/features/settings/**` is out of this round's allowed paths, and its
/// 0.45 default would make the "below threshold" acceptance cell
/// unreachable). The boundary is inclusive.
const double kFirstWinConfidenceThreshold = 0.60;

/// Whether [confidence] counts as a first win — the boundary itself succeeds.
bool isFirstWinSuccess(double confidence) =>
    confidence >= kFirstWinConfidenceThreshold;

/// Builds the engine for one first-win attempt. The shipped default builds
/// the production [LiveFirstWinEngine] over the shared `strumEngineProvider`
/// (ADR 0534 D3, cross-feature access via `live/public.dart`, precedent
/// `lib/features/practice/data/practice_observation_gateway_provider.dart:31`).
/// Overridden in tests/preview with a controllable
/// [FakeOnboardingFirstWinEngine] instance.
final onboardingFirstWinEngineFactoryProvider =
    Provider<OnboardingFirstWinEngine Function()>(
      (ref) =>
          () => LiveFirstWinEngine(ref.watch(strumEngineProvider)),
    );

/// One engine per mount of the first-win Stage. `ref.onDispose(engine.stop)`
/// mirrors `strumEngineProvider`/`liveFrameProvider`
/// (`lib/features/live/providers/live_providers.dart:11-24`) — the merge
/// precedent P2 requires following: the engine releases when nothing watches
/// this provider any more, i.e. when the Stage screen is left (A5).
final onboardingFirstWinEngineProvider =
    Provider.autoDispose<OnboardingFirstWinEngine>((ref) {
      final engine = ref.watch(onboardingFirstWinEngineFactoryProvider)();
      engine.start();
      ref.onDispose(engine.stop);
      return engine;
    });

/// The live confidence stream for the mounted Stage.
final onboardingFirstWinConfidenceProvider = StreamProvider.autoDispose<double>(
  (ref) => ref.watch(onboardingFirstWinEngineProvider).confidence,
);
