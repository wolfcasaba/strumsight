import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/widgets/mic_error_banner.dart';
import '../../../core/widgets/mic_permission_banner.dart';
import '../../../l10n/app_localizations.dart';
import '../../chords/widgets/chord_diagram.dart';
import '../../settings/providers/capo_provider.dart';
import '../../settings/providers/tuning_reference_provider.dart';
import '../model/live_frame.dart';
import '../model/strum.dart';
import '../providers/live_providers.dart';
import '../widgets/beat_counter.dart';
import '../widgets/chord_display.dart';
import '../widgets/confidence_pill.dart';
import '../widgets/live_status_bar.dart';
import '../widgets/strum_arrow.dart';
import '../../progress/model/practice_entry.dart';
import '../../progress/providers/practice_log_provider.dart';
import '../../streak/providers/streak_provider.dart';
import '../../streak/streak_logic.dart';
import '../../streak/widgets/streak_badge.dart';

/// The Live "mirror": the hero screen. Big current chord + strum arrow +
/// confidence + rolling beat counter, glanceable while both hands play.
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
    final l10n = AppLocalizations.of(context);
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
    final latest = frame.latestStrum;
    // Capo: the detector hears concert pitch; show the fretted shape (−capo).
    final capo = ref.watch(capoProvider);

    final micGranted = ref.watch(micPermissionProvider).asData?.value ?? true;
    // The mic failed to start (busy / platform error) — surface it, never a
    // silent no-op. Not shown while paused (the engine is intentionally off).
    final micError = liveAsync.hasError && !_paused;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Stack(
          children: [
            Column(
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
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ChordDisplay(
                        current: frame.current?.transposed(-capo),
                        next: frame.next?.transposed(-capo),
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        height: 116,
                        child: Center(
                          child: latest == null
                              ? null
                              : StrumArrow(
                                  direction: latest.direction,
                                  confidence: latest.confidence,
                                  size: 84,
                                  glow: true,
                                  semanticLabel: _arrowLabel(l10n, latest),
                                ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      ConfidencePill(strum: latest),
                    ],
                  ),
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
            // The current chord's fretting, as a small non-intrusive overlay
            // (top-left) so it never disturbs the tight hero layout.
            if (!_paused && frame.current != null)
              Positioned(
                top: 40,
                left: 0,
                child: ChordDiagram(
                  label: frame.current!.transposed(-capo).label,
                  size: 60,
                  showLabel: false,
                ),
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

  String _arrowLabel(AppLocalizations l10n, Strum s) {
    final dir = s.isDown ? l10n.strumDown : l10n.strumUp;
    return '$dir ${(s.confidence * 100).round()}%';
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
