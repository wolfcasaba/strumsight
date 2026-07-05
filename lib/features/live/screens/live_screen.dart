import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../model/live_frame.dart';
import '../model/strum.dart';
import '../providers/live_providers.dart';
import '../widgets/beat_counter.dart';
import '../widgets/chord_display.dart';
import '../widgets/confidence_pill.dart';
import '../widgets/live_status_bar.dart';
import '../widgets/strum_arrow.dart';

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

  @override
  void initState() {
    super.initState();
    // Keep the screen awake during a session (best-effort; no-op in tests).
    WakelockPlus.enable().catchError((_) {});
  }

  @override
  void dispose() {
    WakelockPlus.disable().catchError((_) {});
    super.dispose();
  }

  void _togglePause() {
    setState(() {
      _paused = !_paused;
      _frozen = _paused ? ref.read(liveFrameProvider).asData?.value : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final live = ref.watch(liveFrameProvider).asData?.value ?? LiveFrame.empty;
    final frame = _paused ? (_frozen ?? live) : live;
    final latest = frame.latestStrum;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Column(
            children: [
              LiveStatusBar(frame: frame),
              Expanded(
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ChordDisplay(current: frame.current, next: frame.next),
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

  String _arrowLabel(AppLocalizations l10n, Strum s) {
    final dir = s.isDown ? l10n.strumDown : l10n.strumUp;
    return '$dir ${(s.confidence * 100).round()}%';
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.paused,
    required this.onTuner,
    required this.onPauseToggle,
  });

  final bool paused;
  final VoidCallback onTuner;
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
