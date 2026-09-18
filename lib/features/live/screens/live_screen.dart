import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/config/app_config.dart';
import '../../../app/routing/app_route.dart';
import '../../../core/audio/audio_providers.dart';
import '../../../core/audio/lifecycle/audio_session_lease.dart';
import '../../../core/design_system/public.dart';
import '../../../core/platform/app_lifecycle.dart';
import '../../../core/platform/platform_providers.dart';
import '../../../core/platform/screen_wakelock.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/mic_error_banner.dart';
import '../../../core/widgets/mic_permission_banner.dart';
import '../../../core/widgets/strum_burst_overlay.dart';
import '../../../l10n/app_localizations.dart';
import '../../settings/public.dart';
import '../engine/strum_engine.dart';
import '../model/live_frame.dart';
import '../providers/chord_timeline_provider.dart';
import '../providers/live_providers.dart';
import '../widgets/beat_counter.dart';
import '../widgets/chord_timeline.dart';
import '../widgets/live_lab_panel.dart';
import '../widgets/live_status_bar.dart';
import '../widgets/live_summary_dialog.dart';
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
  // Guards [_openCovered] against a second tap landing while the first is
  // still handing the microphone over: the second call would see "already
  // paused", push a second copy of the route, and then never resume.
  bool _covering = false;
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
    // Defence in depth (r146): free-play must never inherit a lesson's
    // expected-chord bias — clear it explicitly instead of trusting the nav
    // invariant that LearnScreen was disposed first (chunk 016 residual).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(strumEngineProvider).setExpectedChord(null);
    });
  }

  /// Backgrounded: release the screen wakelock and show the session as paused.
  /// The microphone itself is stopped by the AudioLifecycleGuard — resuming
  /// must NOT restart it behind the user's back (§9.4).
  void _onAppLifecycle(AppLifecycleState state) {
    if (!isBackgroundLifecycleState(state) || !mounted || _paused) return;
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
    // actually played). Uses the captured notifier — safe after unmount. The
    // write is deferred one microtask: Riverpod forbids modifying a provider
    // inside a widget life-cycle (dispose included), and this dispose runs
    // inside the unmount frame when the route is left (measured in CI).
    //
    // The deferral means the write lands AFTER this element is gone, so the
    // provider refresh it triggers needs a live binding to ride: a harness
    // that lets the tree be torn down by teardown instead of unmounting it
    // itself leaves that refresh as a pending timer. Every Live harness
    // therefore unmounts inside the test body — see live_summary_test.dart.
    final log = _log;
    final sessionStart = _sessionStart;
    if (log != null && sessionStart != null && _strokeCount > 0) {
      final entry = PracticeEntry(
        day: StreakLogic.epochDayOf(DateTime.now()),
        source: PracticeSource.live,
        seconds: DateTime.now().difference(sessionStart).inSeconds,
        strokes: _strokeCount,
      );
      scheduleMicrotask(() => unawaited(log.record(entry)));
    }
    super.dispose();
  }

  void _togglePause() => unawaited(_setPaused(!_paused));

  /// Pauses or resumes the session.
  ///
  /// The returned future is the HANDOVER: on pause it completes only once the
  /// engine has given the exclusive microphone lease back to the
  /// [AudioSessionCoordinator] — `StrumEngine.stop()` is not done releasing it
  /// until its own future completes (the platform stream close is a real
  /// round-trip). Anything that hands the microphone to another screen must
  /// therefore AWAIT this; the Pause button itself does not care and drops it.
  Future<void> _setPaused(bool paused) {
    // Tactile confirmation the mic toggled on/off (no-op off-device/in tests).
    try {
      HapticFeedback.mediumImpact();
    } catch (_) {}
    final engine = ref.read(strumEngineProvider);
    // Freeze the last frame BEFORE stopping, so a paused screen keeps showing
    // what was actually heard last.
    final frozen = paused ? ref.read(liveFrameProvider).asData?.value : null;
    // Actually stop detection (timer, and the real mic/DSP), not just the
    // display — a battery/privacy concern once the FFI engine is wired.
    final settled = paused ? engine.stop() : Future<void>.value();
    unawaited(paused ? _wakelock.disable() : _wakelock.enable());
    setState(() {
      _paused = paused;
      _frozen = frozen;
    });
    if (!paused) {
      // Invalidate (not just start()) so a prior mic AsyncError is cleared
      // and the engine restarts through the provider's own lifecycle —
      // otherwise a stale error banner lingers until the next frame.
      ref.invalidate(liveFrameProvider);
    }
    return settled;
  }

  /// Ends the session and leaves the route (ADR 0276 decision 4 — the Finish
  /// action the pre-migration `_ActionBar` never had). Stops the mic/wakelock
  /// immediately; the actual navigation is deferred one short beat so the
  /// `finishing` transport state gets a visible frame.
  ///
  /// A session in which the learner actually strummed first gets a recap
  /// ([LiveSummaryDialog]: strums, distinct chords, time, one next step) —
  /// Finish used to jump straight back to the hub with no feedback at all.
  /// A session with zero strums (nothing to summarise) leaves immediately,
  /// exactly as before.
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
      if (_strokeCount > 0) {
        unawaited(_showSummaryThenLeave());
        return;
      }
      _leave();
    });
  }

  Future<void> _showSummaryThenLeave() async {
    final timeline = ref.read(chordTimelineProvider);
    final chords = <String>{for (final event in timeline) event.chord.label};
    final start = _sessionStart;
    final seconds = start == null
        ? 0
        : DateTime.now().difference(start).inSeconds;
    final openCourse = await showDialog<bool>(
      context: context,
      builder: (_) => LiveSummaryDialog(
        strums: _strokeCount,
        chords: chords.length,
        seconds: seconds,
      ),
    );
    if (!mounted) return;
    if (openCourse ?? false) {
      final adaptive = ref.read(appConfigProvider).flags.adaptiveShellEnabled;
      context.go(adaptive ? AppRoutes.practiceLearn : AppRoutes.learn);
      return;
    }
    _leave();
  }

  void _leave() {
    if (context.canPop()) {
      context.pop();
      return;
    }
    final entryLocation = ref.read(appConfigProvider).flags.adaptiveShellEnabled
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
  }

  /// Opens [location] ON TOP of Live (`context.push`), which leaves this
  /// screen MOUNTED: `liveFrameProvider` stays watched, so the engine — and
  /// with it the exclusive microphone lease (E01-R09) — would keep running
  /// underneath, and the Tuner's own capture would come back as
  /// audioSessionBusy for as long as the shortcut is open.
  ///
  /// So hand the session over first, through the very path the Pause button
  /// takes (mic stopped, wakelock released, the UI honestly showing "paused"),
  /// and take it back when the pushed route pops.
  ///
  /// BOTH handovers are AWAITED, because neither engine's teardown is
  /// instantaneous and the per-engine lifecycle queue only orders one engine
  /// against itself — Live and the covered screen are two engines sharing one
  /// [AudioSessionCoordinator]:
  ///
  /// * going in, `_setPaused(true)` completes only when Live's lease is back
  ///   with the coordinator; pushing before that lands the covered screen's
  ///   own `MicCapture.start` on a still-held lease (audioSessionBusy);
  /// * coming back, the covered screen hands the microphone over through an
  ///   UN-AWAITED `ref.onDispose(engine.stop)` of its own, so resuming in the
  ///   same turn would race that teardown into the mic-error banner.
  ///
  /// [coveredOwner] is the microphone owner behind [location], or `null` when
  /// the covered screen takes no microphone at all (the Metronome, row 13 of
  /// `docs/backlog-ux-polish.md`: it is a pure synth + ticker). With an owner,
  /// Live gives up what Live itself holds and then reclaims the session from
  /// THAT owner only: a blanket [AudioSessionCoordinator.revokeActive] would
  /// also stop a different owner that legitimately took the microphone while
  /// the shortcut was open (latency calibration, diagnostics). With `null`
  /// there is nothing to reclaim FROM — the return path is simply "resume
  /// Live", and reclaiming anyway would steal the session from whoever did
  /// legitimately take it meanwhile. The going-in half is identical either
  /// way: the defect this fixes is the battery/privacy one (a covered Live
  /// left listening with the wakelock held), not only the lease conflict.
  ///
  /// DISCLOSED DEVIATION (round 2, needs tech-lead sign-off): the brief asked
  /// for `revokeActive()` to be REPLACED by "releasing what Live itself
  /// holds". Measured, dropping it outright fails `live_mic_release` case (8)
  /// with `audioSessionBusy`: the covered screen hands its own lease back
  /// through an UN-AWAITED, cross-engine `ref.onDispose(engine.stop)`, and a
  /// per-engine lifecycle queue cannot order two engines against each other.
  /// `revokeActive` is the one handle that awaits the holder's own teardown
  /// before freeing the lease, so it is kept — narrowed to [coveredOwner],
  /// which removes the bluntness the review objected to.
  Future<void> _openCovered(String location, {AudioOwner? coveredOwner}) async {
    if (_covering) return;
    _covering = true;
    try {
      final wasAlreadyPaused = _paused;
      if (!wasAlreadyPaused) {
        // Deliberately NOT guarded by a `catchError`: `StrumEngine.stop()`
        // runs through the engine's own lifecycle queue, which already catches
        // a throwing platform teardown AND logs it, so this future cannot
        // complete with an error any more — and a bare `catchError((_) {})`
        // would be exactly the silent swallow §10 forbids.
        await _setPaused(true);
      }
      if (!mounted) return;
      await context.push<void>(location);
      // Left Live entirely while the shortcut was open, or the user paused it
      // themselves underneath — either way there is nothing to resume.
      if (!mounted || wasAlreadyPaused || !_paused) return;
      // Release whatever LIVE still holds first (idempotent; the engine's own
      // lifecycle queue orders the resume behind it)…
      await ref.read(strumEngineProvider).stop();
      if (!mounted) return;
      // …then, if the covered screen was a microphone owner at all, take the
      // session back from the screen Live handed it to, and from nobody else.
      // `revokeActive` is the one handle that awaits the holder's own teardown
      // (its engine's `onRevoke`) before freeing the lease; the guard keeps it
      // off any OTHER owner, and off a session that the covered screen has
      // already given back (then it is simply free).
      if (coveredOwner != null) {
        final coordinator = ref.read(audioSessionCoordinatorProvider);
        if (coordinator.activeOwner == coveredOwner) {
          await coordinator.revokeActive();
        }
        if (!mounted) return;
      }
      await _setPaused(false);
    } finally {
      _covering = false;
    }
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
    // Discrete beat index off the engine clock — a new value fires ONE finite
    // hero pulse (see ChordTimeline.beat). No free-running metronome, so widget
    // tests still settle. Guards keep it 0 (disabled) when there's no clock/BPM.
    final beat = (frame.bpm > 0 && frame.engineTimeSec >= 0)
        ? (frame.engineTimeSec * frame.bpm / 60).floor()
        : 0;

    final micGranted = ref.watch(micPermissionProvider).asData?.value ?? true;
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
        frame.engineTimeSec >= 0) {
      final micros = (frame.engineTimeSec * 1e6).round();
      _liveRegion.report(
        frame.current!.transposed(-capo).label,
        at: Duration(microseconds: micros),
      );
    }

    // ---- Derived Stage state (§0.0/R8 — LiveFrame carries no state enum;
    // every state below is derived from a measured input). ----
    final isLoading = !_paused && liveAsync.isLoading;
    // The heuristic weak-signal warning is the "no decision" fallback (ADR
    // 0520 D5): once the merged recognizer HAS a reject reason, the banner
    // below is the one place that states why, and this generic warning steps
    // aside (D4) rather than doubling up on the same failure.
    final isWeakSignal =
        !_paused &&
        frame.listening &&
        frame.chordRejectReason == null &&
        frame.inputLevel < SsSignalQualityIndicator.defaultWeakThreshold;
    final hasChord = frame.current != null;

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

    final latestStrum = frame.latestStrum;
    final chordLabel = hasChord ? frame.current!.transposed(-capo).label : null;
    final confColor = AppColors.confidence(frame.confidence, brightness);
    final confTier = AppColors.confidenceTier(frame.confidence);

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
          if (!micGranted) const MicPermissionBanner(),
          if (micGranted && micError)
            MicErrorBanner(onRetry: () => ref.invalidate(liveFrameProvider)),
        ],
      ),
      // Before any chord is heard, a giant placeholder glyph is worse UX
      // than no hero at all — the timeline slot's own "Play a chord…" prompt
      // already carries that message (§5.2, kept as a separate state).
      // Every NEW strum throws a spark over the ↓/↑ glyph — the Learn
      // highway's strike-line juice (chunk 016b P0) on the moat's own screen.
      // The wrapper renders the bare hero until a strum lands and stops its
      // own ticker afterwards, so an idle Live still settles in tests.
      hero: hasChord
          ? Column(
              // NOT `stretch`: `SsChordHero` is a shrink-wrapping Row and
              // `StrumBurstOverlay.trailingGlyphCenter` derives the spark
              // origin from the laid-out width, so forcing the hero to full
              // width would move the sparks to the screen edge. The strings
              // band below asks for the full width on its own instead.
              mainAxisSize: MainAxisSize.min,
              children: [
                StrumBurstOverlay(
                  strumSeq: frame.strumSeq,
                  onsetSeq: frame.onsetSeq,
                  isDown: latestStrum?.isDown,
                  strength: latestStrum?.confidence ?? 0.0,
                  child: SsChordHero(
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
                  ),
                ),
                const SizedBox(height: 8),
                // Onset-first feedback: the band rings the moment an onset is
                // CONFIRMED (`onsetSeq`, ~70 ms ahead of the verdict) and only
                // then takes the direction colour from `strumSeq`. Same colour
                // pair as the burst overlay — copper down, confidence green up
                // — so one strum reads as one event across both widgets. It
                // reads the frame the screen already rebuilt on; no extra watch.
                SsStrumStrings(
                  onsetSeq: frame.onsetSeq,
                  strumSeq: frame.strumSeq,
                  isDown: latestStrum?.isDown,
                  strength: latestStrum?.confidence ?? 0.0,
                  height: 72,
                  downColor: AppColors.primary,
                  upColor: AppColors.confidenceHigh,
                  stringColor: palette.muted,
                  semanticLabel: l10n.liveStringsSemantics,
                ),
              ],
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
      feedback: Column(
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
          if (frame.chordRejectReason != null)
            UncertaintyReasonBanner(reason: frame.chordRejectReason!),
        ],
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
          ),
          if (frame.bar.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: BeatCounter(
                bar: frame.bar,
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
        onTuner: () => unawaited(
          _openCovered(AppRoutes.tuner, coveredOwner: AudioOwner.tuner),
        ),
        // Row 13 of docs/backlog-ux-polish.md: the Metronome goes through the
        // same covered hand-over as the Tuner. It takes NO microphone, so
        // `coveredOwner` is null — Live still pauses (mic released, wakelock
        // dropped, the UI honestly "paused") and the return path is a plain
        // resume, with no session to reclaim from anybody.
        onMetronome: () => unawaited(_openCovered(AppRoutes.metronome)),
      ),
    );
  }

  int? _activeSlot(LiveFrame frame) {
    final latest = frame.latestStrum;
    if (latest == null) return null;
    for (var i = frame.bar.length - 1; i >= 0; i--) {
      if (identical(frame.bar[i].strum, latest)) return i;
    }
    return null;
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
