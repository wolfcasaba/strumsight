import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_palette.dart';
import '../../../l10n/app_localizations.dart';
import '../../library/model/analyzed_session.dart';
import '../../library/providers/library_providers.dart';
import '../../learn/model/lesson.dart';
import '../../learn/screens/learn_screen.dart';
import '../../settings/providers/capo_provider.dart';
import '../../share/screens/share_preview_screen.dart';
import '../model/analyze_result.dart';
import '../providers/analyze_providers.dart';
import '../widgets/timeline_view.dart';

// (chord/strum timeline rendering lives in widgets/timeline_view.dart)

/// Record a clip → get a timeline of its chords and strum directions.
class AnalyzeScreen extends ConsumerStatefulWidget {
  const AnalyzeScreen({super.key});

  @override
  ConsumerState<AnalyzeScreen> createState() => _AnalyzeScreenState();
}

class _AnalyzeScreenState extends ConsumerState<AnalyzeScreen> {
  Timer? _ticker;
  bool _saved = false;

  /// Captured in build — `ref` is unsafe inside dispose (Riverpod rule).
  AnalyzeController? _controller;
  AnalyzePhase _lastPhase = AnalyzePhase.idle;

  @override
  void dispose() {
    _ticker?.cancel();
    // The shell disposes this screen on tab switch, but the controller (a
    // non-autoDispose provider — finished results survive tab switches)
    // would keep the RECORDER running invisibly. Release the mic (round 102).
    // Deferred (provider state must not change while the tree is finalizing)
    // and scheduled ONLY when a take was live, so no stray timer otherwise.
    final controller = _controller;
    if (controller != null && _lastPhase == AnalyzePhase.recording) {
      Future(controller.cancelRecording);
    }
    super.dispose();
  }

  Future<void> _save(AnalyzeResult result) async {
    final l10n = AppLocalizations.of(context);
    final now = DateTime.now();
    final summary = result.chordSummary;
    final session = AnalyzedSession(
      id: now.microsecondsSinceEpoch.toString(),
      createdAt: now,
      title: summary.isNotEmpty ? summary : l10n.analyzeNewRecording,
      result: result,
    );
    await ref.read(libraryProvider.notifier).add(session);
    if (!mounted) return;
    setState(() => _saved = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.analyzeSaved)),
    );
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
    _controller = controller; // for dispose, where ref is unsafe
    _lastPhase = state.phase;
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
      case AnalyzePhase.micError:
        // A busy mic is NOT a permission problem: no settings deep-link,
        // just the failure copy — Retry lives in the big control below
        // (parity with Live r13 / Tuner r68).
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.mic_off_outlined, size: 56, color: palette.muted),
              const SizedBox(height: 16),
              Text(
                l10n.micErrorBody,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Poppins',
                  fontSize: 14,
                  height: 1.45,
                  color: palette.muted,
                ),
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
        return TimelineView(result: result, capo: ref.watch(capoProvider));
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
          onTap: () {
            _saved = false;
            controller.startRecording();
          },
        );
      case AnalyzePhase.micError:
        return _BigButton(
          label: l10n.micErrorAction,
          icon: Icons.refresh,
          color: AppColors.primary,
          onTap: () {
            _saved = false;
            controller.startRecording();
          },
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
        final result = state.result ?? AnalyzeResult.empty;
        final hasContent =
            result.chords.isNotEmpty || result.strums.isNotEmpty;
        final canSave = !_saved && hasContent;
        return Row(
          children: [
            IconButton.filledTonal(
              onPressed: hasContent
                  ? () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => SharePreviewScreen(
                            result: result,
                            capo: ref.read(capoProvider),
                          ),
                        ),
                      )
                  : null,
              icon: const Icon(Icons.ios_share),
              tooltip: l10n.actionShare,
              style: IconButton.styleFrom(
                minimumSize: const Size.square(52),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              onPressed: result.strums.isNotEmpty
                  ? () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => LearnScreen(
                            lesson: Lessons.fromAnalyze(result,
                                name: l10n.analyzeMyRecording),
                          ),
                        ),
                      )
                  : null,
              icon: const Icon(Icons.school_outlined),
              tooltip: l10n.learnPracticeThis,
              style: IconButton.styleFrom(
                minimumSize: const Size.square(52),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: canSave ? () => _save(result) : null,
                icon: Icon(
                  _saved ? Icons.check : Icons.bookmark_add_outlined,
                  size: 18,
                ),
                label: Text(_saved ? l10n.analyzeSaved : l10n.analyzeSave),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _BigButton(
                label: l10n.analyzeNewRecording,
                icon: Icons.refresh,
                color: AppColors.primary,
                onTap: () {
                  setState(() => _saved = false);
                  controller.reset();
                },
              ),
            ),
          ],
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
