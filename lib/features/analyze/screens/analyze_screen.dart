import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../../live/widgets/strum_arrow.dart';
import '../model/analyze_result.dart';
import '../providers/analyze_providers.dart';

/// Record a clip → get a timeline of its chords and strum directions.
class AnalyzeScreen extends ConsumerStatefulWidget {
  const AnalyzeScreen({super.key});

  @override
  ConsumerState<AnalyzeScreen> createState() => _AnalyzeScreenState();
}

class _AnalyzeScreenState extends ConsumerState<AnalyzeScreen> {
  Timer? _ticker;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _syncTicker(AnalyzePhase phase) {
    final recording = phase == AnalyzePhase.recording;
    if (recording && _ticker == null) {
      _ticker = Timer.periodic(
        const Duration(milliseconds: 200),
        (_) => setState(() {}),
      );
    } else if (!recording && _ticker != null) {
      _ticker!.cancel();
      _ticker = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;
    final state = ref.watch(analyzeControllerProvider);
    final controller = ref.read(analyzeControllerProvider.notifier);
    _syncTicker(state.phase);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 24, 20, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.navAnalyze,
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontWeight: FontWeight.w800,
                fontSize: 30,
                color: palette.ink,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(child: _body(context, l10n, state, controller)),
            const SizedBox(height: 12),
            _controls(context, l10n, state, controller),
          ],
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    AppLocalizations l10n,
    AnalyzeState state,
    AnalyzeController controller,
  ) {
    final palette = context.palette;
    switch (state.phase) {
      case AnalyzePhase.idle:
      case AnalyzePhase.micDenied:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.multitrack_audio, size: 56, color: palette.muted),
              const SizedBox(height: 16),
              Text(
                state.phase == AnalyzePhase.micDenied
                    ? l10n.micPermissionBody
                    : l10n.analyzeIntro,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  height: 1.45,
                  color: palette.muted,
                ),
              ),
              if (state.phase == AnalyzePhase.micDenied) ...[
                const SizedBox(height: 12),
                TextButton(
                  onPressed: openAppSettings,
                  child: Text(l10n.micPermissionAction),
                ),
              ],
            ],
          ),
        );
      case AnalyzePhase.recording:
        final elapsed = controller.recorder.elapsedSec;
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _RecordingDot(),
              const SizedBox(height: 20),
              Text(
                _fmt(elapsed),
                style: TextStyle(
                  fontFamily: 'Montserrat',
                  fontWeight: FontWeight.w800,
                  fontSize: 44,
                  color: palette.ink,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                l10n.analyzeRecordingHint,
                style: TextStyle(color: palette.muted, fontFamily: 'Poppins'),
              ),
            ],
          ),
        );
      case AnalyzePhase.analyzing:
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                l10n.analyzeAnalyzing,
                style: TextStyle(color: palette.muted, fontFamily: 'Poppins'),
              ),
            ],
          ),
        );
      case AnalyzePhase.done:
        final result = state.result ?? AnalyzeResult.empty;
        if (result.chords.isEmpty && result.strums.isEmpty) {
          return Center(
            child: Text(
              l10n.analyzeNoChords,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.muted, fontFamily: 'Poppins'),
            ),
          );
        }
        return _Timeline(result: result);
    }
  }

  Widget _controls(
    BuildContext context,
    AppLocalizations l10n,
    AnalyzeState state,
    AnalyzeController controller,
  ) {
    switch (state.phase) {
      case AnalyzePhase.idle:
      case AnalyzePhase.micDenied:
        return _BigButton(
          label: l10n.analyzeRecord,
          icon: Icons.fiber_manual_record,
          color: AppColors.primary,
          onTap: controller.startRecording,
        );
      case AnalyzePhase.recording:
        return _BigButton(
          label: l10n.analyzeStop,
          icon: Icons.stop,
          color: AppColors.primary,
          onTap: controller.stopAndAnalyze,
        );
      case AnalyzePhase.analyzing:
        return const SizedBox(height: 52);
      case AnalyzePhase.done:
        return _BigButton(
          label: l10n.analyzeNewRecording,
          icon: Icons.refresh,
          color: AppColors.primary,
          onTap: controller.reset,
        );
    }
  }

  static String _fmt(double seconds) {
    final s = seconds.floor();
    final m = s ~/ 60;
    final rem = s % 60;
    return '${m.toString().padLeft(1, '0')}:${rem.toString().padLeft(2, '0')}';
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.result});

  final AnalyzeResult result;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = context.palette;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Summary chips.
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Chip(text: _AnalyzeScreenState._fmt(result.durationSec)),
            if (result.bpm > 0) _Chip(text: '${result.bpm.round()} BPM'),
            _Chip(text: l10n.analyzeStrumsSummary(result.downCount, result.upCount)),
          ],
        ),
        const SizedBox(height: 16),
        Expanded(
          child: result.chords.isEmpty
              ? Center(
                  child: Text(
                    l10n.analyzeStrumsSummary(
                        result.downCount, result.upCount),
                    style: TextStyle(color: palette.muted),
                  ),
                )
              : ListView.separated(
                  itemCount: result.chords.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, i) =>
                      _ChordRow(chord: result.chords[i], strums: result.strums),
                ),
        ),
      ],
    );
  }
}

class _ChordRow extends StatelessWidget {
  const _ChordRow({required this.chord, required this.strums});

  final TimelineChord chord;
  final List<TimelineStrum> strums;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final inSegment = strums
        .where((s) => s.timeSec >= chord.startSec && s.timeSec < chord.endSec)
        .toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 56,
            child: Text(
              chord.label,
              style: TextStyle(
                fontFamily: 'Montserrat',
                fontWeight: FontWeight.w800,
                fontSize: 24,
                color: palette.ink,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_AnalyzeScreenState._fmt(chord.startSec)} – '
                  '${_AnalyzeScreenState._fmt(chord.endSec)}',
                  style: TextStyle(
                    fontFamily: 'Poppins',
                    fontSize: 12,
                    color: palette.muted,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (inSegment.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    children: [
                      for (final s in inSegment)
                        StrumArrow(
                          direction: s.direction,
                          confidence: s.confidence,
                          size: 16,
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.border),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w600,
          fontSize: 12,
          color: palette.ink,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _RecordingDot extends StatefulWidget {
  @override
  State<_RecordingDot> createState() => _RecordingDotState();
}

class _RecordingDotState extends State<_RecordingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween(begin: 0.35, end: 1.0).animate(_c),
      child: Container(
        width: 22,
        height: 22,
        decoration: const BoxDecoration(
          color: AppColors.primary,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _BigButton extends StatelessWidget {
  const _BigButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onTap,
      icon: Icon(icon),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: const Color(0xFF1A1206),
        minimumSize: const Size.fromHeight(52),
        textStyle: const TextStyle(
          fontFamily: 'Poppins',
          fontWeight: FontWeight.w600,
          fontSize: 15,
        ),
      ),
    );
  }
}
