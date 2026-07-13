import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../../core/theme/app_colors.dart';
import '../../../l10n/app_localizations.dart';
import '../../analyze/model/analyze_result.dart';
import '../../learn/audio/chord_audio.dart';
import '../../learn/audio/metronome.dart';
import '../../learn/lesson_timing.dart';
import '../../learn/model/lesson.dart';
import '../../learn/widgets/lesson_highway.dart';
import '../share_content.dart';
import '../share_service.dart';

/// A full-screen, looping, branded **replay** of a recording — chord + ↓/↑ arrows
/// flowing in tempo — made to be **screen-recorded** and shared (the "moat as
/// motion", RAG chunks 013/014). No encoder plugin, no mic: pure animation, so
/// it's buildable + testable now; a true MP4 export is a later option needing a
/// maintained video encoder.
class StrumReelScreen extends StatefulWidget {
  const StrumReelScreen({
    super.key,
    required this.result,
    this.capo = 0,
    this.shareService = const ShareService(),
    this.metronome,
    this.backing,
  });

  final AnalyzeResult result;
  final int capo;
  final ShareService shareService;

  /// Injectable click/pad sources (tests); defaults are created per screen.
  final Metronome? metronome;
  final Backing? backing;

  /// Downbeat "punch-in" (chunk 016b P7): a subtle scale kick on each bar
  /// downbeat, decaying over ~half a beat. Pure — testable and deterministic.
  /// Kicks on the LESSON's own bar (round 118 — a waltz punches every 3).
  static double punchScale(double playheadBeat, {int beatsPerBar = 4}) {
    final phase = playheadBeat % beatsPerBar; // beats into the bar
    return 1 + 0.05 * math.exp(-5 * phase);
  }

  /// Branded end-card opacity (chunk 016b P7): fades in over the loop's last
  /// 1.5 beats so every screen-recorded pass ends on the brand + install cue.
  static double endCardOpacity(double playheadBeat, double totalBeats) {
    if (totalBeats <= 3) return 0; // too short for an end-card
    final t = playheadBeat - (totalBeats - 1.5);
    return (t / 0.75).clamp(0.0, 1.0);
  }

  @override
  State<StrumReelScreen> createState() => _StrumReelScreenState();
}

class _StrumReelScreenState extends State<StrumReelScreen>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  late final Lesson _lesson;
  late final Metronome _metronome;
  late final Backing _backing;
  double _elapsed = 0;
  // Ticker elapsed restarts at zero on each start() — accumulate across
  // pauses so resume CONTINUES instead of jumping back to beat 0
  // (reviewer, round 82; same pattern as learn_screen's _accumSec).
  double _accumSec = 0;
  bool _playing = true;
  // The reel SOUNDS by default (round 162): the whole point is a
  // screen-recorded loop, and a silent recording is a broken share. The
  // toggle is for practising in quiet places.
  bool _soundOn = true;
  // Start one beat before 0 so the opening downbeat fires on the very first
  // frame — the audio and the highway leave from the same instant.
  double _prevBeat = -1.0;

  @override
  void initState() {
    super.initState();
    _lesson = Lessons.fromAnalyze(widget.result, name: 'reel');
    _metronome = widget.metronome ?? Metronome();
    _backing = widget.backing ?? Backing();
    _ticker = createTicker(_onTick)..start();
  }

  void _onTick(Duration d) {
    setState(() => _elapsed = _accumSec + d.inMicroseconds / 1e6);
    final now = _playhead;
    if (_soundOn) {
      // The clicks/pads ride the SAME playhead the highway draws, so what is
      // heard and what crosses the strike line stay locked together —
      // including the wrap, where beat 0's downbeat re-fires as the lane
      // jumps back (LessonTiming.beatsCrossedLooped).
      for (final beat in LessonTiming.beatsCrossedLooped(
          _prevBeat, now, _lesson.totalBeats.toDouble())) {
        final downbeat = beat % _lesson.beatsPerBar == 0;
        _metronome.tick(accent: downbeat);
        if (downbeat) _backing.playChord(_activeChord(beat.toDouble()));
      }
    }
    _prevBeat = now;
  }

  /// The chord sounding at [beat]: the most recent event chord at/before it
  /// (falling back to the first chord right at the loop head).
  String _activeChord(double beat) {
    var chord = '';
    for (final e in _lesson.events) {
      if (e.chord.isEmpty) continue;
      if (e.beat <= beat + 0.25) {
        chord = e.chord;
      } else {
        if (chord.isEmpty) chord = e.chord;
        break;
      }
    }
    return chord;
  }

  @override
  void dispose() {
    _ticker.dispose();
    // Screen-created players die with the screen; injected ones belong to
    // the caller (tests) — Metronome()/Backing() here are always our own
    // unless injected.
    if (widget.metronome == null) _metronome.dispose();
    if (widget.backing == null) _backing.dispose();
    super.dispose();
  }

  double get _playhead {
    final total = _lesson.totalBeats;
    if (total <= 0) return 0;
    final beat = _elapsed * _lesson.bpm / 60.0;
    return beat % total; // loop
  }

  void _toggle() {
    setState(() => _playing = !_playing);
    if (_playing) {
      _ticker.start();
    } else {
      _accumSec = _elapsed;
      _ticker.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final chords = ShareContent.chords(widget.result, capo: widget.capo);
    return Scaffold(
      backgroundColor: const Color(0xFF111013),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        gradient: AppColors.brandGradient,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Icon(Icons.graphic_eq,
                          size: 15, color: Colors.white),
                    ),
                    const SizedBox(width: 8),
                    const Text('StrumSight',
                        style: TextStyle(
                            fontFamily: 'Montserrat',
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: Color(0xFFE9E5DE))),
                  ]),
                  Row(children: [
                    // Sound on/off — a recorded reel should HAVE sound, so
                    // the default is on (round 162).
                    IconButton(
                      icon: Icon(
                          _soundOn ? Icons.volume_up : Icons.volume_off,
                          color: const Color(0xFFE9E5DE)),
                      tooltip: l10n.reelSoundToggle,
                      onPressed: () =>
                          setState(() => _soundOn = !_soundOn),
                    ),
                    // 1-tap share (chunk 016b P7): the caption + install link
                    // without leaving the reel.
                    IconButton(
                      icon: const Icon(Icons.ios_share,
                          color: Color(0xFFE9E5DE)),
                      tooltip: l10n.shareTextButton,
                      onPressed: () => widget.shareService
                          .shareText(widget.result, capo: widget.capo),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Color(0xFFE9E5DE)),
                      tooltip: l10n.commonClose,
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ]),
                ],
              ),
              const Spacer(),
              if (chords.isNotEmpty)
                Text(chords,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontFamily: 'Montserrat',
                        fontWeight: FontWeight.w800,
                        fontSize: 26,
                        color: Color(0xFFE9E5DE))),
              const SizedBox(height: 16),
              GestureDetector(
                onTap: _toggle,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Transform.scale(
                      scale: StrumReelScreen.punchScale(_playhead,
                          beatsPerBar: _lesson.beatsPerBar),
                      child: LessonHighway(
                        lesson: _lesson,
                        playheadBeat: _playhead,
                        height: 190,
                      ),
                    ),
                    // Branded end-card: every recorded loop ends on the brand.
                    // Only in the tree while visible (also keeps the base
                    // finders unique in tests).
                    if (StrumReelScreen.endCardOpacity(
                            _playhead, _lesson.totalBeats.toDouble()) >
                        0)
                      IgnorePointer(
                      child: Opacity(
                        opacity: StrumReelScreen.endCardOpacity(
                            _playhead, _lesson.totalBeats.toDouble()),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 22, vertical: 14),
                          decoration: BoxDecoration(
                            color: const Color(0xE6111013),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: AppColors.primary
                                    .withValues(alpha: 0.55)),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('↓↑',
                                  style: TextStyle(
                                      fontSize: 30,
                                      fontWeight: FontWeight.w800,
                                      color: AppColors.primary)),
                              const Text('StrumSight',
                                  style: TextStyle(
                                      fontFamily: 'Montserrat',
                                      fontWeight: FontWeight.w800,
                                      fontSize: 20,
                                      color: Color(0xFFE9E5DE))),
                              const SizedBox(height: 4),
                              Text('#StrumSightChallenge',
                                  style: TextStyle(
                                      fontSize: 12,
                                      color: const Color(0xFFE9E5DE)
                                          .withValues(alpha: 0.8))),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Text(
                '${l10n.reelHint}\n#StrumSightChallenge',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 12,
                    height: 1.4,
                    color: const Color(0xFFE9E5DE).withValues(alpha: 0.7)),
              ),
              const Spacer(),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('↓↑',
                      style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: AppColors.primary)),
                  const SizedBox(width: 8),
                  Text(l10n.reelTagline,
                      style: TextStyle(
                          fontSize: 12,
                          color: const Color(0xFFE9E5DE).withValues(alpha: 0.7))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
