import 'package:flutter/material.dart';

import '../foundations/ss_breakpoints.dart';
import '../foundations/ss_spacing.dart';

/// The Stage layout shared by every active-session mode (Live, Practice,
/// Song, Tuner, Metronome, Vision) — five slots in build order (Ch13 §9.9):
/// [statusHeader], [hero], [feedback], [timeline], [bottomAction].
///
/// Presentation-only (ADR 0276): it starts no microphone, camera, or
/// recording, and owns no such resource. Screen-awake and the unsaved-session
/// back gate are both request/notify callbacks — the caller decides what, if
/// anything, they do; this widget never reaches a platform channel itself.
final class SsStageScaffold extends StatefulWidget {
  const SsStageScaffold({
    super.key,
    required this.statusHeader,
    required this.hero,
    required this.feedback,
    required this.timeline,
    required this.bottomAction,
    this.hasUnsavedSession = false,
    this.onUnsavedSessionBackAttempt,
    this.onRequestScreenAwake,
    this.onReleaseScreenAwake,
  });

  /// Top status slot (e.g. connection or mode indicator).
  final Widget statusHeader;

  /// Primary focal slot (e.g. chord name, tuner needle).
  final Widget hero;

  /// Secondary feedback slot (e.g. confidence, signal quality).
  final Widget feedback;

  /// Timeline/beat visualization slot.
  final Widget timeline;

  /// Bottom action slot — typically an `SsSessionTransport`.
  final Widget bottomAction;

  /// True while the active session holds data a system back would discard.
  final bool hasUnsavedSession;

  /// Fires on a blocked back attempt while [hasUnsavedSession] is true —
  /// exactly once per attempt. The scaffold does not decide the copy and
  /// does not save anything; the caller confirms (or not) and pops the
  /// route itself.
  final VoidCallback? onUnsavedSessionBackAttempt;

  /// Requested exactly once, from [initState] — never a direct wakelock
  /// plugin call from this widget.
  final VoidCallback? onRequestScreenAwake;

  /// Released exactly once, from [dispose].
  final VoidCallback? onReleaseScreenAwake;

  @override
  State<SsStageScaffold> createState() => _SsStageScaffoldState();
}

class _SsStageScaffoldState extends State<SsStageScaffold> {
  @override
  void initState() {
    super.initState();
    widget.onRequestScreenAwake?.call();
  }

  @override
  void dispose() {
    widget.onReleaseScreenAwake?.call();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final orientation = MediaQuery.orientationOf(context);
    final isWide =
        orientation == Orientation.landscape ||
        size.width >= SsBreakpoints.expandedMin;

    return PopScope(
      canPop: !widget.hasUnsavedSession,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) widget.onUnsavedSessionBackAttempt?.call();
      },
      child: Scaffold(
        body: SafeArea(
          child: isWide
              ? _WideStage(
                  statusHeader: widget.statusHeader,
                  hero: widget.hero,
                  feedback: widget.feedback,
                  timeline: widget.timeline,
                  bottomAction: widget.bottomAction,
                )
              : _CompactStage(
                  statusHeader: widget.statusHeader,
                  hero: widget.hero,
                  feedback: widget.feedback,
                  timeline: widget.timeline,
                  bottomAction: widget.bottomAction,
                ),
        ),
      ),
    );
  }
}

/// Portrait strategy: header pinned top, hero/feedback/timeline scroll in
/// the middle, the action slot pinned bottom (ADR 0276 decision 4 — Pause
/// and Finish must never end up below a fold).
class _CompactStage extends StatelessWidget {
  const _CompactStage({
    required this.statusHeader,
    required this.hero,
    required this.feedback,
    required this.timeline,
    required this.bottomAction,
  });

  final Widget statusHeader;
  final Widget hero;
  final Widget feedback;
  final Widget timeline;
  final Widget bottomAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            SsSpacing.space4,
            SsSpacing.space4,
            SsSpacing.space4,
            SsSpacing.space2,
          ),
          child: statusHeader,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: SsSpacing.space4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                hero,
                const SizedBox(height: SsSpacing.space4),
                feedback,
                const SizedBox(height: SsSpacing.space4),
                timeline,
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(SsSpacing.space4),
          child: bottomAction,
        ),
      ],
    );
  }
}

/// Landscape/expanded strategy: a two-column split gives the action slot its
/// own pinned column instead of a shrinking bottom strip — the layout most
/// prone to hiding Pause/Finish under fixed-height content (ADR 0276).
class _WideStage extends StatelessWidget {
  const _WideStage({
    required this.statusHeader,
    required this.hero,
    required this.feedback,
    required this.timeline,
    required this.bottomAction,
  });

  final Widget statusHeader;
  final Widget hero;
  final Widget feedback;
  final Widget timeline;
  final Widget bottomAction;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  SsSpacing.space4,
                  SsSpacing.space4,
                  SsSpacing.space2,
                  SsSpacing.space2,
                ),
                child: statusHeader,
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SsSpacing.space4,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      hero,
                      const SizedBox(height: SsSpacing.space4),
                      feedback,
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          flex: 2,
          child: Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(SsSpacing.space4),
                  child: timeline,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(SsSpacing.space4),
                child: bottomAction,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
