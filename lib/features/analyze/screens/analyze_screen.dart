import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/design_system/public.dart';
import '../../../l10n/app_localizations.dart';
import '../../library/public.dart';
import '../../diagnostics/public.dart';
import '../../learn/public.dart';
import '../../settings/public.dart';
import '../../share/public.dart';
import '../model/analyze_result.dart';
import '../providers/analyze_providers.dart';
import '../widgets/analyze_skeleton.dart';
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

  /// Captured in initState — `ref` is unsafe inside dispose (Riverpod rule).
  AnalyzeController? _controller;

  @override
  void initState() {
    super.initState();
    final controller = ref.read(analyzeControllerProvider.notifier);
    controller.screenAttached();
    _controller = controller;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    // The shell disposes this screen on tab switch, but the controller (a
    // non-autoDispose provider — finished results survive tab switches)
    // would keep the RECORDER running invisibly. Detaching releases a live
    // take (deferred — the tree is finalizing) AND lets the controller abort
    // a start still awaiting the mic handshake when it lands (round 102 +
    // round 114; the old `_lastPhase == recording` gate missed the latter).
    _controller?.screenDetached();
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
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(l10n.analyzeSaved)));
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
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    final state = ref.watch(analyzeControllerProvider);
    final controller = ref.read(analyzeControllerProvider.notifier);
    _syncTicker(state.phase);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          SsSpacing.space5,
          SsSpacing.space6,
          SsSpacing.space5,
          SsSpacing.space4,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.navAnalyze,
              style: typography.headlineLarge.copyWith(
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: SsSpacing.space4),
            Expanded(child: _body(context, l10n, state, controller)),
            const SizedBox(height: SsSpacing.space3),
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
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    switch (state.phase) {
      case AnalyzePhase.idle:
        // The bottom control bar (`_controls`, below) already offers the
        // one real next step for this phase — start recording. SsEmptyState
        // requires its own actionLabel/onAction, which would only ever be
        // able to duplicate that same button (review M4 — a fabricated
        // second "Record" CTA, §0.0.A/R12 forbids forcing a fake action).
        // Token-styled local widget instead, same shape as the micError
        // branch below; no title, so it does not repeat the screen header
        // above (review m1). Scrolls instead of overflowing at large
        // textScaler on a short viewport (A3).
        return SingleChildScrollView(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(SsSpacing.space6),
              child: Column(
                key: const Key('analyze-idle-empty'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.multitrack_audio,
                    size: 40,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(height: SsSpacing.space4),
                  Text(
                    l10n.analyzeIntro,
                    textAlign: TextAlign.center,
                    style: typography.bodyMedium.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      case AnalyzePhase.micDenied:
        // A real, single action (open the OS settings) maps cleanly onto
        // SsEmptyState's required actionLabel/onAction (§0.0.A/R12) — unlike
        // the bespoke Column this replaces, SsEmptyState models it natively.
        // Title reuses the existing microphone-permission title from the
        // audio_analysis feature instead of `navAnalyze`, which would repeat
        // the screen header above (review m1) — no new ARB key needed.
        return SingleChildScrollView(
          child: SsEmptyState(
            key: const Key('analyze-mic-denied'),
            icon: Icons.multitrack_audio,
            title: l10n.analysisRecordingPermissionDeniedTitle,
            message: l10n.micPermissionBody,
            actionLabel: l10n.micPermissionAction,
            onAction: openAppSettings,
          ),
        );
      case AnalyzePhase.recording:
        final elapsed = controller.recorder.elapsedSec;
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _RecordingDot(),
              const SizedBox(height: SsSpacing.space5),
              Text(
                _fmt(elapsed),
                style: typography.metricLarge.copyWith(
                  color: colors.textPrimary,
                  fontSize: 44,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: SsSpacing.space2),
              Text(
                l10n.analyzeRecordingHint,
                style: typography.bodyMedium.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        );
      case AnalyzePhase.micError:
        // A busy mic is NOT a permission problem: no settings deep-link,
        // just the failure copy — Retry lives in the big control below
        // (parity with Live r13 / Tuner r68). No AppFailure/action belongs
        // to this widget, so it stays a token-styled local widget rather
        // than a forced SsEmptyState/SsFailureState (§0.0.A/R12 exception
        // class).
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.mic_off_outlined,
                size: 56,
                color: colors.textSecondary,
              ),
              const SizedBox(height: SsSpacing.space4),
              Text(
                l10n.micErrorBody,
                textAlign: TextAlign.center,
                style: typography.bodyMedium.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        );
      case AnalyzePhase.analyzing:
        // A shimmer skeleton that previews the result-timeline shape (chips +
        // chord-row cards + strum lane) so the multi-second DSP wait feels
        // productive instead of frozen behind a bare spinner. The
        // "Analyzing…" copy rides along as the semantics label.
        return AnalyzeSkeleton(label: l10n.analyzeAnalyzing);
      case AnalyzePhase.done:
        final result = state.result ?? AnalyzeResult.empty;
        if (result.chords.isEmpty && result.strums.isEmpty) {
          return Center(
            child: Text(
              l10n.analyzeNoChords,
              textAlign: TextAlign.center,
              style: typography.bodyMedium.copyWith(
                color: colors.textSecondary,
              ),
            ),
          );
        }
        final timeline = TimelineView(
          result: result,
          capo: ref.watch(capoProvider),
        );
        // Lab mode (r198): show the ML-vs-DSP diagnostics panel below the
        // timeline when diagnostics were collected.
        final showDiag =
            ref.watch(labModeProvider) && result.diagnostics != null;
        if (!showDiag) return timeline;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 2, child: timeline),
            Flexible(
              child: SingleChildScrollView(
                child: DiagnosticsPanel(result: result),
              ),
            ),
          ],
        );
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
        return SizedBox(
          width: double.infinity,
          height: 52,
          child: SsButton(
            label: l10n.analyzeRecord,
            icon: Icons.fiber_manual_record,
            onPressed: () {
              _saved = false;
              controller.startRecording();
            },
          ),
        );
      case AnalyzePhase.micError:
        return SizedBox(
          width: double.infinity,
          height: 52,
          child: SsButton(
            label: l10n.micErrorAction,
            icon: Icons.refresh,
            onPressed: () {
              _saved = false;
              controller.startRecording();
            },
          ),
        );
      case AnalyzePhase.recording:
        return SizedBox(
          width: double.infinity,
          height: 52,
          child: SsButton(
            label: l10n.analyzeStop,
            icon: Icons.stop,
            onPressed: controller.stopAndAnalyze,
          ),
        );
      case AnalyzePhase.analyzing:
        return const SizedBox(height: 52);
      case AnalyzePhase.done:
        final result = state.result ?? AnalyzeResult.empty;
        final hasContent = result.chords.isNotEmpty || result.strums.isNotEmpty;
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
              style: IconButton.styleFrom(minimumSize: const Size.square(52)),
            ),
            const SizedBox(width: SsSpacing.space2),
            IconButton.filledTonal(
              onPressed: result.strums.isNotEmpty
                  ? () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => LearnScreen(
                          lesson: Lessons.fromAnalyze(
                            result,
                            name: l10n.analyzeMyRecording,
                          ),
                        ),
                      ),
                    )
                  : null,
              icon: const Icon(Icons.school_outlined),
              tooltip: l10n.learnPracticeThis,
              style: IconButton.styleFrom(minimumSize: const Size.square(52)),
            ),
            const SizedBox(width: SsSpacing.space3),
            Expanded(
              child: SizedBox(
                height: 52,
                child: SsButton(
                  variant: SsButtonVariant.secondary,
                  icon: _saved ? Icons.check : Icons.bookmark_add_outlined,
                  label: _saved ? l10n.analyzeSaved : l10n.analyzeSave,
                  onPressed: canSave ? () => _save(result) : null,
                ),
              ),
            ),
            const SizedBox(width: SsSpacing.space3),
            Expanded(
              child: SizedBox(
                height: 52,
                child: SsButton(
                  label: l10n.analyzeNewRecording,
                  icon: Icons.refresh,
                  onPressed: () {
                    setState(() => _saved = false);
                    controller.reset();
                  },
                ),
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
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    return FadeTransition(
      opacity: Tween(begin: 0.35, end: 1.0).animate(_c),
      child: Container(
        width: 22,
        height: 22,
        decoration: BoxDecoration(color: colors.brand, shape: BoxShape.circle),
      ),
    );
  }
}
