import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/config/app_config.dart';
import '../../../app/routing/app_route.dart';
import '../../../core/design_system/public.dart';
import '../../../core/platform/app_lifecycle.dart';
import '../../../core/platform/platform_providers.dart';
import '../../../core/platform/screen_wakelock.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/mic_error_banner.dart';
import '../../../core/widgets/mic_permission_banner.dart';
import '../../../l10n/app_localizations.dart';
import '../../settings/public.dart';
import '../domain/recognition/recognition_decision.dart';
import '../engine/strum_engine.dart';
import '../model/live_frame.dart';
import '../providers/chord_timeline_provider.dart';
import '../providers/live_providers.dart';
import '../providers/live_stage_mode.dart';
import '../widgets/beat_counter.dart';
import '../widgets/chord_timeline.dart';
import '../widgets/guided_target_card.dart';
import '../widgets/live_lab_panel.dart';
import '../widgets/live_status_bar.dart';
import '../widgets/recognition_state_chip.dart';
import '../widgets/uncertainty_reason_banner.dart';
import '../../progress/public.dart';
import '../../streak/public.dart';

/// The Live "mirror": the hero screen. Migrated onto [SsStageScaffold]
/// (Ch13 §9.9, ADR 0276): a glanceable current-chord hero, a signal-quality
/// feedback strip, the rolling chord-timeline + beat grid, and a bottom
/// action bar carrying the mandatory Pause/Finish transport (ADR 0276
/// decision 4) alongside Tuner/Metronome shortcuts.
///
/// Resource ownership is UNCHANGED by the migration (ADR 0276 §1): the
/// wakelock and the microphone lease are still owned and released here, not
/// by the scaffold — see [initState]/[dispose]/[_onAppLifecycle].
class LiveScreen extends ConsumerStatefulWidget {
  const LiveScreen({super.key});

  @override
  ConsumerState<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends ConsumerState<LiveScreen> {
  bool _paused = false;
  bool _finishing = false;
  LiveFrame? _frozen;
  bool _practiceRecorded = false; // one streak credit per Live visit

  // Progress-log session tracking (real listening time + distinct strums).
  DateTime? _sessionStart;
  int _lastStrumSeq = 0;
  int _strokeCount = 0;
  // Captured in build so dispose never has to touch `ref` (unsafe post-unmount).
  PracticeLogController? _log;
  // The engine, captured in build so dispose can turn Lab capture off without
  // touching `ref` after unmount (r199).
  StrumEngine? _engine;
  // Captured in initState so dispose/background never touch `ref`.
  late final ScreenWakelock _wakelock;
  late final AppLifecycleEvents _lifecycle;

  // The throttled announcer for the recognised-chord narration (ADR 0280
  // §2) — a plain field, not scaffold-owned (ADR 0276 §1): the visual
  // widgets update every frame, only this narration is rate-limited.
  final SsLiveRegion _liveRegion = SsLiveRegion();

  // Gives the "finishing" transport state one visible frame before the
  // route is actually left (§0.0/R8) — cancelled on dispose so a delayed
  // callback never touches `ref`/`context` after unmount.
  Timer? _finishTimer;

  @override
  void initState() {
    super.initState();
    // Keep the screen awake during a session (best-effort; no-op in tests).
    _wakelock = ref.read(screenWakelockProvider);
    unawaited(_wakelock.enable());
    // Backgrounding stops the mic (the coordinator revokes the session); the
    // screen has to agree with that — otherwise the UI keeps claiming it is
    // listening while nothing is (E01-R09 §9.4).
    _lifecycle = ref.read(appLifecycleEventsProvider);
    _lifecycle.addListener(_onAppLifecycle);
    // Free-play must never inherit a lesson's expected-chord bias. Since
    // E14-R30 (ADR 0544) that is a MACHINE guarantee, not a convention: the
    // shared engine is constructed in `RecognitionMode.free`
    // (`liveRecognitionModeProvider`), and `ExpectedChordHint.forMode`
    // returns `null` for that regime, so a label handed to
    // `setExpectedChord` cannot reach the decoder at all. This explicit
    // clear is kept as the belt to that braces (r146): it costs nothing, it
    // is the ONLY `setExpectedChord` call this screen ever makes, and it
    // always passes `null` — pinned by
    // `test/features/live/screens/live_stage_mode_test.dart`.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(strumEngineProvider).setExpectedChord(null);
      // Opening Live IS the user intent to listen, so this is where the
      // system dialog may be shown — once per app run, and never as a side
      // effect of a rebuild (L6). Reading `micPermissionProvider` itself only
      // ever checks.
      unawaited(ref.read(micPermissionProvider.notifier).requestOnce());
    });
  }

  /// Backgrounded: release the screen wakelock and show the session as paused.
  /// The microphone itself is stopped by the AudioLifecycleGuard — resuming
  /// must NOT restart it behind the user's back (§9.4).
  ///
  /// Resumed: re-read the microphone permission (L5). The banner's "Open
  /// settings" leaves the app, so a grant made there lands while we are
  /// backgrounded — without this re-read the screen went on claiming there is
  /// no microphone until the app was restarted. The read is a CHECK: it never
  /// shows a dialog and never restarts the mic.
  void _onAppLifecycle(AppLifecycleState state) {
    if (!mounted) return;
    if (state == AppLifecycleState.resumed) {
      unawaited(ref.read(micPermissionProvider.notifier).refresh());
      return;
    }
    if (!isBackgroundLifecycleState(state) || _paused) return;
    unawaited(_wakelock.disable());
    setState(() {
      _frozen = ref.read(liveFrameProvider).asData?.value;
      _paused = true;
    });
    unawaited(ref.read(strumEngineProvider).stop());
  }

  @override
  void dispose() {
    _lifecycle.removeListener(_onAppLifecycle);
    _finishTimer?.cancel();
    _liveRegion.dispose();
    unawaited(_wakelock.disable());
    // Stop the Lab-mode rolling capture when leaving Live (r199) — no buffering
    // once the screen is gone. Safe after unmount (touches no provider state).
    _engine?.setDiagnosticsCapture(false);
    // Log the finished Live session for the Progress dashboard (only if the user
    // actually played). Uses the captured notifier — safe after unmount.
    if (_sessionStart != null && _strokeCount > 0) {
      _log?.record(
        PracticeEntry(
          day: StreakLogic.epochDayOf(DateTime.now()),
          source: PracticeSource.live,
          seconds: DateTime.now().difference(_sessionStart!).inSeconds,
          strokes: _strokeCount,
        ),
      );
    }
    super.dispose();
  }

  void _togglePause() {
    // Tactile confirmation the mic toggled on/off (no-op off-device/in tests).
    try {
      HapticFeedback.mediumImpact();
    } catch (_) {}
    final engine = ref.read(strumEngineProvider);
    setState(() {
      _paused = !_paused;
      if (_paused) {
        // Actually stop detection (timer, and the real mic/DSP), not just the
        // display — a battery/privacy concern once the FFI engine is wired.
        _frozen = ref.read(liveFrameProvider).asData?.value;
        engine.stop();
        unawaited(_wakelock.disable());
      } else {
        _frozen = null;
        unawaited(_wakelock.enable());
        // Invalidate (not just start()) so a prior mic AsyncError is cleared
        // and the engine restarts through the provider's own lifecycle —
        // otherwise a stale error banner lingers until the next frame.
        ref.invalidate(liveFrameProvider);
      }
    });
  }

  /// Ends the session and leaves the route (ADR 0276 decision 4 — the Finish
  /// action the pre-migration `_ActionBar` never had). Stops the mic/wakelock
  /// immediately; the actual navigation is deferred one short beat so the
  /// `finishing` transport state gets a visible frame.
  ///
  /// The fallback target (when there's nothing to pop to) is the app's own
  /// entry route, mirroring the router's own choice (`adaptiveShellEnabled
  /// ? today : live` — read here via the same public [appConfigProvider]
  /// other features already use, since `lib/app/routing/**` is out of scope
  /// for this round). When that entry route IS `/live` — the default,
  /// adaptive-shell-off configuration — Finish has nowhere to go: the
  /// session just ends in place, same as a manual Pause (review MINOR-2).
  void _finish() {
    if (_finishing) return;
    setState(() => _finishing = true);
    unawaited(ref.read(strumEngineProvider).stop());
    unawaited(_wakelock.disable());
    _finishTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      if (context.canPop()) {
        context.pop();
        return;
      }
      final entryLocation =
          ref.read(appConfigProvider).flags.adaptiveShellEnabled
          ? AppRoutes.today
          : AppRoutes.live;
      if (entryLocation != AppRoutes.live) {
        context.go(entryLocation);
        return;
      }
      setState(() {
        _finishing = false;
        _paused = true;
        _frozen = ref.read(liveFrameProvider).asData?.value;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    _log = ref.read(practiceLogProvider.notifier);
    // Lab mode (r199): enable the engine's rolling mic-PCM capture so the Live
    // Lab panel can re-analyze external guitar audio. Off → the engine buffers
    // nothing (zero overhead on the default Live path). Idempotent bool set.
    final labMode = ref.watch(labModeProvider);
    final engine = ref.read(strumEngineProvider);
    engine.setDiagnosticsCapture(labMode);
    _engine = engine;
    // Real playing detected → credit today's practice streak (once per visit;
    // the record call is itself idempotent per calendar day). RAG chunk 013.
    ref.listen(liveFrameProvider, (_, next) {
      final f = next.asData?.value;
      if (f != null && f.latestStrum != null) {
        _sessionStart ??= DateTime.now();
        // strumSeq bumps per NEW strum → count distinct strokes this session.
        if (f.strumSeq != _lastStrumSeq && f.strumSeq > 0) {
          _lastStrumSeq = f.strumSeq;
          _strokeCount++;
        }
        // Require ≥2 distinct strums this session so a single stray transient
        // (e.g. a bump or a spoken word) never credits the practice streak.
        if (!_practiceRecorded && _strokeCount >= 2) {
          _practiceRecorded = true;
          ref.read(streakProvider.notifier).recordPracticeToday();
        }
      }
    });
    final liveAsync = ref.watch(liveFrameProvider);
    final live = liveAsync.asData?.value ?? LiveFrame.empty;
    // While paused the engine is stopped, so reflect "not listening" honestly.
    final frame = _paused ? (_frozen ?? live).copyWith(listening: false) : live;
    // The rolling chord-timeline history (newest last), folded from the same
    // live frames in [chordTimelineProvider].
    final timeline = ref.watch(chordTimelineProvider);
    // Capo: the detector hears concert pitch; show the fretted shape (−capo).
    final capo = ref.watch(capoProvider);
    // The stage's PRODUCT mode (ADR 0550 D2) — derived from the on-screen
    // target, so "guided" and "there is a target" can never disagree.
    final stageMode = ref.watch(liveStageModeProvider);
    final guidedTarget = ref.watch(liveGuidedTargetProvider);
    // Discrete beat index off the engine clock — a new value fires ONE finite
    // hero pulse (see ChordTimeline.beat). No free-running metronome, so widget
    // tests still settle. Guards keep it 0 (disabled) when there's no clock/BPM.
    final beat = (frame.hasMeasuredTempo && frame.engineTimeSec >= 0)
        ? (frame.engineTimeSec * frame.bpm / 60).floor()
        : 0;

    // Fail-closed (L7): ONLY a confirmed grant counts. A read that is still
    // in flight or came back as an error is "not granted" — the previous
    // `?? true` turned every unknown into consent and rendered a screen that
    // claimed to be listening on a microphone it had never been given.
    //
    // But "not granted" is TWO states, not one (audit F1). The permission is
    // an `AsyncNotifier` whose first frame is `AsyncLoading`, so treating the
    // in-flight read like a measured denial flashed the settings banner on
    // every Live mount — and in a test that pumps a single frame it never
    // went away. While the answer is unknown the screen says nothing at all:
    // no banner, no "Starting…", no "play a chord" invitation — only the
    // level meter, which honestly reads `listening: false`. Actions stay
    // fail-closed (the transport below is disabled until the grant lands).
    final micPermission = ref.watch(micPermissionProvider);
    final micGranted = micPermission.value?.isGranted ?? false;
    final micUnknown = !micPermission.hasValue && !micPermission.hasError;
    // The mic failed to start (busy / platform error) — surface it, never a
    // silent no-op. Not shown while paused (the engine is intentionally off).
    final micError = liveAsync.hasError && !_paused;

    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final brightness = Theme.of(context).brightness;

    // ---- Accessible announcement, throttled independently of the visual
    // frame rate (ADR 0280 §2, §0.0/R8). ----
    if (!_paused &&
        frame.listening &&
        frame.current != null &&
        _decisionClaimsChord(frame.chordDecision) &&
        frame.engineTimeSec >= 0) {
      final micros = (frame.engineTimeSec * 1e6).round();
      _liveRegion.report(
        frame.current!.transposed(-capo).label,
        at: Duration(microseconds: micros),
      );
    }

    // ---- Derived Stage state (§0.0/R8 — LiveFrame carries no state enum;
    // every state below is derived from a measured input). ----
    // "Starting…" is only true while a mic we are ALLOWED to open is coming
    // up. Without the permission nothing is starting, and showing both that
    // and the permission banner told the user two contradictory things at
    // once.
    final isLoading = !_paused && liveAsync.isLoading && micGranted;
    // The heuristic weak-signal warning is the "no decision" fallback (ADR
    // 0520 D5): once the merged recognizer HAS a reject reason, the banner
    // below is the one place that states why, and this generic warning steps
    // aside (D4) rather than doubling up on the same failure.
    final isWeakSignal =
        !_paused &&
        frame.listening &&
        frame.chordRejectReason == null &&
        frame.inputLevel < SsSignalQualityIndicator.defaultWeakThreshold;
    // ADR 0550 D1: a chord reaches the DETECTION hero only under a decision
    // that actually claims one. `LivePipeline` already only fills `current`
    // on a `confirmed` verdict (`showChord == chordLatched && hasMatch`), so
    // on today's production path this changes nothing — it turns that
    // producer-side coincidence into a screen-side machine guard that also
    // holds for the stabilizer, the adapter and any future producer.
    final claimsChord = _decisionClaimsChord(frame.chordDecision);
    final hasChord = frame.current != null && claimsChord;

    // The transport only distinguishes disabled/finishing/paused/active — a
    // session autostarts on mount (no `countIn`, no separate "not yet
    // started" moment to gate on), so idle/starting/listening/weak-signal/
    // no-chord all read as `active` here and are told apart by the hero,
    // feedback and timeline slots instead. Gating this on `isLoading` would
    // flicker Pause away on every resume (invalidating the stream re-enters
    // loading until the next frame arrives) — measured while writing this
    // round's tests.
    final transportStatus = !micGranted || (micError && !_paused)
        ? SsSessionTransportStatus.disabled
        : _finishing
        ? SsSessionTransportStatus.finishing
        : _paused
        ? SsSessionTransportStatus.paused
        : SsSessionTransportStatus.active;

    // `displayStrum`, not `latestStrum`: an indicator EXPIRES without a fresh
    // detection (L11) and is never shown next to a stated "the signal is
    // unusable" — a stale ↑ under a "too quiet" banner is a confident claim
    // the engine is not making (AGENTS.md §5).
    final latestStrum = frame.displayStrum;
    final chordLabel = hasChord ? frame.current!.transposed(-capo).label : null;
    final shownConfidence = latestStrum?.confidence ?? 0;
    final confColor = AppColors.confidence(shownConfidence, brightness);
    final confTier = AppColors.confidenceTier(shownConfidence);

    return SsStageScaffold(
      // Live is free-play with no session artifact to save — no unsaved-data
      // back-gate, and the wakelock stays owned by this State (ADR 0276 §1)
      // rather than the scaffold's request/notify hooks, since it already
      // has to track the app-lifecycle/background path those hooks don't
      // cover.
      statusHeader: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: LiveStatusBar(
                  frame: frame,
                  a4: ref.watch(tuningReferenceProvider),
                  capo: capo,
                ),
              ),
              const SizedBox(width: 8),
              const StreakBadge(),
            ],
          ),
          if (isLoading)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                l10n.liveStarting,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  color: palette.muted,
                ),
              ),
            ),
          // Only a RESOLVED "not granted" earns the banner — see `micUnknown`
          // above.
          if (!micGranted && !micUnknown) const MicPermissionBanner(),
          // Shown REGARDLESS of the permission read: gating it on `micGranted`
          // meant that whenever the permission was (wrongly) read as missing,
          // the one message explaining why the engine is dead disappeared too.
          if (micError)
            MicErrorBanner(onRetry: () => ref.invalidate(liveFrameProvider)),
        ],
      ),
      // Before any chord is heard, a giant placeholder glyph is worse UX
      // than no hero at all — the timeline slot's own "Play a chord…" prompt
      // already carries that message (§5.2, kept as a separate state).
      //
      // U6 — the stage's middle region packs hero/feedback/timeline against
      // the header, so the screen's middle third reads as empty while the
      // content crowds top and bottom. Until `SsStageScaffold._CompactStage`
      // centres that region itself (proposed patch in the round report), the
      // screen distributes the spare height with token spacing of its own.
      // Slot contract, keys and semantics are unchanged.
      hero: Padding(
        padding: const EdgeInsets.only(top: SsSpacing.space8),
        child: hasChord
            ? SsChordHero(
                chordLabel: chordLabel,
                textColor: palette.ink,
                direction: latestStrum == null
                    ? null
                    : (latestStrum.isDown
                          ? SsStrumDirection.down
                          : SsStrumDirection.up),
                glyphColor: confColor,
                confidenceTier: confTier,
                directionSemanticLabel: latestStrum == null
                    ? null
                    : '${latestStrum.isDown ? l10n.strumDown : l10n.strumUp} '
                          '${(latestStrum.confidence * 100).round()}%',
              )
            : SizedBox(
                height: 64,
                child: Center(
                  child: Icon(
                    Icons.music_note_outlined,
                    size: 32,
                    color: palette.muted,
                  ),
                ),
              ),
      ),
      feedback: Padding(
        padding: const EdgeInsets.symmetric(vertical: SsSpacing.space4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SsLiveRegionAnnouncer(controller: _liveRegion),
            SsSignalQualityIndicator(
              level: frame.inputLevel,
              listening: !_paused && frame.listening,
              activeColor: AppColors.primary,
              trackColor: palette.track,
              warningColor: AppColors.danger,
              levelSemanticLabel: l10n.liveInputLevel,
              weakLabel: isWeakSignal ? l10n.liveWeakSignal : null,
            ),
            // The stage's mode and — in Guided only — the target. The target
            // lives HERE, in the feedback slot, never in `hero`: the hero is
            // the detection slot, and a target rendered there would read as a
            // recognition result (ADR 0550 D3).
            //
            // A `Column` of centred rows rather than a `Wrap`: `Wrap` hands
            // its children UNBOUNDED main-axis constraints, under which the
            // chips' `Flexible` text would throw instead of shrinking — and
            // the whole point of these rows is that they survive 360 px and
            // textScale 2.0. `Align` passes bounded, loose constraints, so
            // each pill keeps its intrinsic size until it has to shrink.
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Align(child: _StageModeChip(mode: stageMode)),
                  if (guidedTarget != null) ...[
                    const SizedBox(height: 6),
                    Align(child: GuidedTargetCard(chordLabel: guidedTarget)),
                  ],
                  // The recognizer's own decision state, whenever a producer
                  // supplies one. An absent decision is not a state, so the
                  // chip is simply not rendered for it.
                  if (frame.chordDecision != null) ...[
                    const SizedBox(height: 6),
                    Align(
                      child: RecognitionStateChip(
                        decision: frame.chordDecision!,
                        chordLabel: frame.current?.transposed(-capo).label,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (frame.chordRejectReason != null)
              UncertaintyReasonBanner(reason: frame.chordRejectReason!),
          ],
        ),
      ),
      timeline: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ChordTimeline(
            events: timeline,
            next: frame.next,
            capo: capo,
            listening: !_paused && frame.listening,
            beat: beat,
            idlePromptEnabled: micGranted && !micError,
          ),
          if (frame.bar.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              // `displayBar`: the grid keeps its "1 & 2 &" labels, but the
              // strum marks expire with the arrow above (L11).
              child: BeatCounter(
                bar: frame.displayBar,
                activeIndex: _activeSlot(frame),
              ),
            ),
          if (labMode)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: LiveLabPanel(),
            ),
        ],
      ),
      bottomAction: _ActionBar(
        transportStatus: transportStatus,
        pauseLabel: l10n.livePause,
        resumeLabel: l10n.liveResume,
        finishLabel: l10n.liveFinish,
        idleLabel: null,
        onPause: _togglePause,
        onResume: _togglePause,
        onFinish: _finish,
        tunerLabel: l10n.liveTuner,
        metronomeLabel: l10n.metronomeTitle,
        onTuner: () => context.push(AppRoutes.tuner),
        onMetronome: () => context.push(AppRoutes.metronome),
      ),
    );
  }

  /// Whether [decision] lets the stage present a chord as RECOGNISED
  /// (ADR 0550 D1). Exhaustive, no `default`: a seventh decision state is a
  /// compile error here rather than a silent "yes".
  ///
  /// `null` — a producer that supplies no typed decision at all (mocks, the
  /// onboarding first-win engine, the `LiveFrameAdapter` boundary) — keeps
  /// the pre-E14-R37 behaviour: those producers gate the chord themselves and
  /// this round does not invent a verdict for them.
  static bool _decisionClaimsChord(RecognitionDecision? decision) =>
      switch (decision) {
        RecognitionDecision.confirmed => true,
        RecognitionDecision.candidate ||
        RecognitionDecision.provisional ||
        RecognitionDecision.uncertain ||
        RecognitionDecision.rejected ||
        RecognitionDecision.expired => false,
        null => true,
      };

  int? _activeSlot(LiveFrame frame) {
    final latest = frame.displayStrum;
    if (latest == null) return null;
    for (var i = frame.bar.length - 1; i >= 0; i--) {
      if (identical(frame.bar[i].strum, latest)) return i;
    }
    return null;
  }
}

/// Names the stage's product mode in words (ADR 0550 D2). Free play and
/// Guided are told apart by TEXT plus an icon, never by colour alone — the
/// E14-R39 audit measured the confidence tokens as a single grey under full
/// colour loss, so a hue-only mode cue would be no cue at all.
class _StageModeChip extends StatelessWidget {
  const _StageModeChip({required this.mode});

  final LiveStageMode mode;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final (label, icon) = switch (mode) {
      LiveStageMode.freePlay => (l10n.liveModeFreePlay, Icons.graphic_eq),
      LiveStageMode.guided => (l10n.liveModeGuided, Icons.flag_outlined),
    };
    return Semantics(
      label: label,
      excludeSemantics: true,
      child: Container(
        key: ValueKey('live-stage-mode-${mode.name}'),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: palette.border, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: palette.muted),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                label,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: palette.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The Stage bottom-action slot: the mandatory Pause/Finish transport
/// (ADR 0276 decision 4) plus the Tuner/Metronome shortcuts the pre-existing
/// `_ActionBar` carried.
class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.transportStatus,
    required this.pauseLabel,
    required this.resumeLabel,
    required this.finishLabel,
    required this.idleLabel,
    required this.onPause,
    required this.onResume,
    required this.onFinish,
    required this.tunerLabel,
    required this.metronomeLabel,
    required this.onTuner,
    required this.onMetronome,
  });

  final SsSessionTransportStatus transportStatus;
  final String pauseLabel;
  final String resumeLabel;
  final String finishLabel;
  final String? idleLabel;
  final VoidCallback onPause;
  final VoidCallback onResume;
  final VoidCallback onFinish;
  final String tunerLabel;
  final String metronomeLabel;
  final VoidCallback onTuner;
  final VoidCallback onMetronome;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SsSessionTransport(
          status: transportStatus,
          pauseLabel: pauseLabel,
          resumeLabel: resumeLabel,
          finishLabel: finishLabel,
          idleLabel: idleLabel,
          onPause: onPause,
          onResume: onResume,
          onFinish: onFinish,
        ),
        const SizedBox(height: 6),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            Expanded(
              child: _ActionButton(
                icon: Icons.graphic_eq,
                label: tunerLabel,
                onTap: onTuner,
              ),
            ),
            Expanded(
              child: _ActionButton(
                icon: Icons.av_timer,
                label: metronomeLabel,
                onTap: onMetronome,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Semantics(
      button: true,
      label: label,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(32),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: palette.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: palette.border, width: 1),
                ),
                child: Icon(icon, color: palette.ink, size: 24),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 11,
                  letterSpacing: 0.4,
                  color: palette.muted,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
