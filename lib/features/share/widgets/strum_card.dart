import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../analyze/model/analyze_result.dart';
import '../../live/model/strum.dart';
import '../share_content.dart';

/// The shareable "Strum Card" — a self-contained, brand-styled artifact that
/// showcases StrumSight's moat (the DOWN ↓ / UP ↑ pattern) plus the chords,
/// tempo and stroke counts of a clip. Rendered offline; captured to PNG by the
/// share service. Fixed logical size (4:5 portrait) for a consistent export.
class StrumCard extends StatelessWidget {
  const StrumCard({
    super.key,
    required this.result,
    this.capo = 0,
    this.title,
  });

  final AnalyzeResult result;
  final int capo;

  /// Optional session title (falls back to the chord progression).
  final String? title;

  /// Logical export size — **9:16** (Stories / Reels / TikTok fit with no
  /// cropping, the format behind Spotify Wrapped's share loop, chunk 013).
  /// Captured at a higher pixel ratio → ~1080×1920.
  static const double width = 360;
  static const double height = 640;

  static const _ground = Color(0xFF111013);
  static const _ink = Color(0xFFE9E5DE);

  @override
  Widget build(BuildContext context) {
    final chords = ShareContent.chords(result, capo: capo);
    final dirs = ShareContent.strumDirections(result);
    return SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF17151A), _ground],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 20, 22, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _wordmark(),
              const SizedBox(height: 6),
              Text(
                'Chord & strum-direction detector',
                style: TextStyle(
                    fontSize: 11.5, color: _ink.withValues(alpha: 0.6)),
              ),
              const Spacer(),
              _label('CHORDS'),
              const SizedBox(height: 6),
              Text(
                chords.isEmpty ? 'My riff' : chords,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Montserrat',
                  fontWeight: FontWeight.w800,
                  fontSize: 30,
                  height: 1.1,
                  color: _ink,
                ),
              ),
              const SizedBox(height: 20),
              _label('YOUR STRUM PATTERN'),
              const SizedBox(height: 8),
              _StrumArrows(dirs: dirs, truncated: result.strums.length > 16),
              const Spacer(),
              _stats(),
              const SizedBox(height: 14),
              _footer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _wordmark() => Row(
        children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              gradient: AppColors.brandGradient,
              borderRadius: BorderRadius.circular(7),
            ),
            child: const Icon(Icons.graphic_eq, size: 16, color: Colors.white),
          ),
          const SizedBox(width: 9),
          const Text(
            'StrumSight',
            style: TextStyle(
              fontFamily: 'Montserrat',
              fontWeight: FontWeight.w700,
              fontSize: 17,
              color: _ink,
              letterSpacing: 0.2,
            ),
          ),
        ],
      );

  Widget _label(String text) => Text(
        text,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 11,
          letterSpacing: 1.4,
          color: AppColors.primary,
        ),
      );

  Widget _stats() {
    final chips = <Widget>[
      if (result.bpm > 0) _chip('${result.bpm.round()}', 'BPM'),
      _chip('${result.downCount}', 'DOWN ↓'),
      _chip('${result.upCount}', 'UP ↑'),
      _chip(_dur(result.durationSec), 'LENGTH'),
    ];
    return Row(
      children: [
        for (var i = 0; i < chips.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: chips[i]),
        ],
      ],
    );
  }

  Widget _chip(String value, String label) => Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(
                fontFamily: 'Montserrat',
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: _ink,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 8.5,
                letterSpacing: 0.6,
                color: _ink.withValues(alpha: 0.6),
              ),
            ),
          ],
        ),
      );

  Widget _footer() => Row(
        children: [
          const Text(
            '↓↑',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              'The only app that sees your down/up strokes',
              style: TextStyle(
                fontSize: 10,
                color: _ink.withValues(alpha: 0.7),
              ),
            ),
          ),
        ],
      );

  static String _dur(double seconds) {
    final s = seconds.round();
    final m = s ~/ 60;
    final r = s % 60;
    return m > 0 ? '$m:${r.toString().padLeft(2, '0')}' : '${r}s';
  }
}

/// The arrow row — down strokes in copper, up strokes in the confidence green,
/// so the pattern reads at a glance (the whole point of the card).
class _StrumArrows extends StatelessWidget {
  const _StrumArrows({required this.dirs, required this.truncated});

  final List<StrumDirection> dirs;
  final bool truncated;

  @override
  Widget build(BuildContext context) {
    if (dirs.isEmpty) {
      return Text(
        'No strums detected',
        style: TextStyle(
            fontSize: 12, color: const Color(0xFFE9E5DE).withValues(alpha: 0.5)),
      );
    }
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final d in dirs)
          Icon(
            d == StrumDirection.down ? Icons.arrow_downward : Icons.arrow_upward,
            size: 26,
            color: d == StrumDirection.down
                ? AppColors.primary
                : AppColors.confidenceHigh,
          ),
        if (truncated)
          const Text('…',
              style: TextStyle(fontSize: 18, color: Color(0xFFE9E5DE))),
      ],
    );
  }
}
