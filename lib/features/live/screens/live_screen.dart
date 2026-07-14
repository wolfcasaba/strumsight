import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/mic_error_banner.dart';
import '../../../core/widgets/mic_permission_banner.dart';
import '../../../l10n/app_localizations.dart';
import '../../settings/providers/capo_provider.dart';
import '../../settings/providers/tuning_reference_provider.dart';
import '../model/live_frame.dart';
import '../providers/chord_timeline_provider.dart';
import '../providers/live_providers.dart';
import '../widgets/beat_counter.dart';
import '../widgets/chord_timeline.dart';
import '../widgets/live_status_bar.dart';
import '../../progress/model/practice_entry.dart';
import '../../progress/providers/practice_log_provider.dart';
import '../../streak/providers/streak_provider.dart';
import '../../streak/streak_logic.dart';
import '../../streak/widgets/streak_badge.dart';

/// The Live "mirror": the hero screen. A horizontal chord timeline (newest
/// chord large, previously recognised chords receding left, each with its ↓/↑
/// strum direction) + rolling beat counter, glanceable while both hands play.
class LiveScreen extends ConsumerStatefulWidget {
  const LiveScreen({super.key});

  @override
  ConsumerState<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends ConsumerState<LiveScreen> {
  bool _paused = false;
  LiveFrame? _frozen;
  bool _practiceRecorded = false; // one streak credit per Live visit

  // Progress-log session tracking (real listening time + distinct strums).
  DateTime? _sessionStart;
  int _lastStrumSeq = 0;
  int _strokeCount = 0;
  // Captured in build so dispose never has to touch `ref` (unsafe post-unmount).
  PracticeLogController? _log;

  @override
  void initState() {
    super.initState();
    // Keep the screen awake during a session (best-effort; no-op in tests).
    WakelockPlus.enable().catchError((_) {});
    // Defence in depth (r146): free-play must never inherit a lesson's
    // expected-chord bias — clear it explicitly instead of trusting the nav
    // invariant that LearnScreen was disposed first (chunk 016 residual).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(strumEngineProvider).setExpectedChord(null);
    });
  }

  @override
  void dispose() {
    WakelockPlus.disable().catchError((_) {});
    // Log the finished Live session for the Progress dashboard (only if the user
    // actually played). Uses the captured notifier — safe after unmount.
    if (_sessionStart != null && _strokeCount > 0) {
      _log?.record(PracticeEntry(
        day: StreakLogic.epochDayOf(DateTime.now()),
        source: PracticeSource.live,
        seconds: DateTime.now().difference(_sessionStart!).inSeconds,
        strokes: _strokeCount,
      ));
    }
    super.dispose();
  }

  void _togglePause() {
    final engine = ref.read(strumEngineProvider);
    setState(() {
      _paused = !_paused;
      if (_paused) {
        // Actually stop detection (timer, and the real mic/DSP), not just the
        // display — a battery/privacy concern once the FFI engine is wired.
        _frozen = ref.read(liveFrameProvider).asData?.value;
        engine.stop();
      } else {
        _frozen = null;
        // Invalidate (not just start()) so a prior mic AsyncError is cleared
        // and the engine restarts through the provider's own lifecycle —
        // otherwise a stale error banner lingers until the next frame.
        ref.invalidate(liveFrameProvider);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _log = ref.read(practiceLogProvider.notifier);
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
        if (!_practiceRecorded) {
          _practiceRecorded = true;
          ref.read(streakProvider.notifier).recordPracticeToday();
        }
      }
    });
    final liveAsync = ref.watch(liveFrameProvider);
    final live = liveAsync.asData?.value ?? LiveFrame.empty;
    // While paused the engine is stopped, so reflect "not listening" honestly.
    final frame =
        _paused ? (_frozen ?? live).copyWith(listening: false) : live;
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

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Column(
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
              if (!micGranted) const MicPermissionBanner(),
              if (micGranted && micError)
                MicErrorBanner(
                  onRetry: () => ref.invalidate(liveFrameProvider),
                ),
              Expanded(
                // The chord-timeline filmstrip: newest chord big on the right,
                // previously recognised chords receding left, each with its
                // own ↓/↑ strum direction. Subsumes the old big-chord + arrow +
                // confidence-pill hero and the fingering overlay.
                child: ChordTimeline(
                  events: timeline,
                  next: frame.next,
                  capo: capo,
                  listening: !_paused && frame.listening,
                  beat: beat,
                ),
              ),
              if (frame.bar.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: BeatCounter(
                    bar: frame.bar,
                    activeIndex: _activeSlot(frame),
                  ),
                ),
              _ActionBar(
                paused: _paused,
                onTuner: () => context.push('/tuner'),
                onMetronome: () => context.push('/metronome'),
                onPauseToggle: _togglePause,
              ),
            ],
          ),
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

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.paused,
    required this.onTuner,
    required this.onMetronome,
    required this.onPauseToggle,
  });

  final bool paused;
  final VoidCallback onTuner;
  final VoidCallback onMetronome;
  final VoidCallback onPauseToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _ActionButton(
            icon: Icons.graphic_eq,
            label: l10n.liveTuner,
            onTap: onTuner,
          ),
          _ActionButton(
            icon: paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
            label: paused ? l10n.liveResume : l10n.livePause,
            onTap: onPauseToggle,
            primary: true,
          ),
          _ActionButton(
            icon: Icons.av_timer,
            label: l10n.metronomeTitle,
            onTap: onMetronome,
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final fg = primary ? const Color(0xFF1A1206) : palette.ink;
    final bg = primary ? AppColors.primary : palette.surface;
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
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: bg,
                  shape: BoxShape.circle,
                  border: primary
                      ? null
                      : Border.all(color: palette.border, width: 1),
                ),
                child: Icon(icon, color: fg, size: 26),
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
