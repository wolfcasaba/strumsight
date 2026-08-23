import 'package:flutter/material.dart';

/// The six Stage transport states (Ch13 §9.9). Only [countIn], [active],
/// [paused], and [finishing] are an active session (ADR 0276 decision 4):
/// Pause and Finish are guaranteed visible exactly for those four.
enum SsSessionTransportStatus {
  idle,
  countIn,
  active,
  paused,
  finishing,
  disabled,
}

/// The Pause/Finish action bar for an active Stage session.
///
/// Data-only: every label and callback arrives from the caller. Pause and
/// Finish are never moved into an overflow menu — that is the exact
/// weakening ADR 0276 rules out.
final class SsSessionTransport extends StatelessWidget {
  const SsSessionTransport({
    super.key,
    required this.status,
    required this.pauseLabel,
    required this.resumeLabel,
    required this.finishLabel,
    this.idleLabel,
    this.disabledLabel,
    this.onPause,
    this.onResume,
    this.onFinish,
  });

  final SsSessionTransportStatus status;
  final String pauseLabel;
  final String resumeLabel;
  final String finishLabel;
  final String? idleLabel;
  final String? disabledLabel;
  final VoidCallback? onPause;
  final VoidCallback? onResume;
  final VoidCallback? onFinish;

  static const _activeStatuses = {
    SsSessionTransportStatus.countIn,
    SsSessionTransportStatus.active,
    SsSessionTransportStatus.paused,
    SsSessionTransportStatus.finishing,
  };

  @override
  Widget build(BuildContext context) {
    if (!_activeStatuses.contains(status)) {
      return _RestIndicator(
        status: status,
        label: status == SsSessionTransportStatus.disabled
            ? disabledLabel
            : idleLabel,
      );
    }

    final isPaused = status == SsSessionTransportStatus.paused;
    final canTogglePause =
        status == SsSessionTransportStatus.active || isPaused;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        IconButton(
          key: const ValueKey('ss-session-transport-pause'),
          tooltip: isPaused ? resumeLabel : pauseLabel,
          onPressed: canTogglePause ? (isPaused ? onResume : onPause) : null,
          icon: Icon(
            isPaused ? Icons.play_arrow_outlined : Icons.pause_outlined,
          ),
        ),
        if (status == SsSessionTransportStatus.countIn)
          const Icon(
            Icons.timer_outlined,
            key: ValueKey('ss-session-transport-count-in-marker'),
          ),
        if (status == SsSessionTransportStatus.finishing)
          const SizedBox(
            key: ValueKey('ss-session-transport-finishing-marker'),
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        IconButton(
          key: const ValueKey('ss-session-transport-finish'),
          tooltip: finishLabel,
          onPressed: onFinish,
          icon: const Icon(Icons.stop_outlined),
        ),
      ],
    );
  }
}

/// The non-session rest states — [SsSessionTransportStatus.idle] and
/// [SsSessionTransportStatus.disabled]. Distinguished from each other, and
/// from every active-session state, purely by icon and the absence of the
/// pause/finish action keys.
class _RestIndicator extends StatelessWidget {
  const _RestIndicator({required this.status, required this.label});

  final SsSessionTransportStatus status;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final isDisabled = status == SsSessionTransportStatus.disabled;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          isDisabled ? Icons.block : Icons.radio_button_unchecked,
          key: ValueKey('ss-session-transport-rest-${status.name}'),
        ),
        if (label != null) ...[
          const SizedBox(width: 8),
          Flexible(child: Text(label!, softWrap: true)),
        ],
      ],
    );
  }
}
