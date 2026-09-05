/// Public surface for the onboarding feature (ADR 0519 §0.0/R2 — the
/// feature's first `public.dart`; hand-written and additive. There is no
/// `lib/features/onboarding/public/` fragment directory yet, so the
/// generated-barrel freshness guard (`tool/check_architecture.dart:804`)
/// does not run against this file — it only checks features that use the
/// fragment-based generator.
library;

export 'audio_setup/audio_profile.dart';
export 'audio_setup/audio_profile_store.dart';
export 'audio_setup/audio_setup_controller.dart';
export 'audio_setup/audio_setup_step.dart';
