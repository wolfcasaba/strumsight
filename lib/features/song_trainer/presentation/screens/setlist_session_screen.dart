import 'package:flutter/material.dart';

import '../../../../core/design_system/public.dart';
import '../../../../l10n/app_localizations.dart';
import '../../application/setlists/setlist_session_controller.dart';
import '../../domain/models/setlist_result.dart';
import '../../domain/models/song_setlist.dart';

typedef SetlistPracticeRunnerFactory = SetlistItemRunner Function();
typedef SetlistSessionCompleted = void Function(SetlistResult result);

final class SetlistSessionScreen extends StatefulWidget {
  const SetlistSessionScreen({
    super.key,
    required this.setlist,
    required this.mode,
    required this.availability,
    required this.performanceRunner,
    this.createPracticeRunner,
    this.onCompleted,
  });

  final SongSetlist setlist;
  final SetlistSessionMode mode;
  final SetlistAvailabilityResolver availability;
  final SetlistItemRunner performanceRunner;
  final SetlistPracticeRunnerFactory? createPracticeRunner;
  final SetlistSessionCompleted? onCompleted;

  @override
  State<SetlistSessionScreen> createState() => _SetlistSessionScreenState();
}

final class _SetlistSessionScreenState extends State<SetlistSessionScreen> {
  late final SetlistSessionController _controller;
  bool _isRunning = false;
  SetlistResult? _result;

  @override
  void initState() {
    super.initState();
    _controller = switch (widget.mode) {
      SetlistSessionMode.practice => SetlistSessionController(
        availability: widget.availability,
        practiceRunner: _practiceRunner(),
        performanceRunner: widget.performanceRunner,
      ),
      SetlistSessionMode.performance => SetlistSessionController(
        availability: widget.availability,
        practiceRunner: _unavailablePracticeRunner,
        performanceRunner: widget.performanceRunner,
      ),
    };
  }

  SetlistItemRunner _practiceRunner() {
    final factory = widget.createPracticeRunner;
    if (factory == null) {
      throw ArgumentError('Practice mode requires a scoring runner factory.');
    }
    return factory();
  }

  static Future<SetlistItemResult> _unavailablePracticeRunner(
    SongSetlistItem item,
  ) => throw StateError('Playback-only sessions cannot run scoring.');

  Future<void> _run() async {
    setState(() => _isRunning = true);
    final result = await _controller.run(
      setlist: widget.setlist,
      mode: widget.mode,
    );
    if (!mounted) return;
    setState(() {
      _isRunning = false;
      _result = result;
    });
    widget.onCompleted?.call(result);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).extension<SsColorScheme>()!;
    final typography = Theme.of(context).extension<SsTypography>()!;
    final isPractice = widget.mode == SetlistSessionMode.practice;
    final resultByItem = <String, SetlistItemResult>{
      for (final result in _result?.itemResults ?? const <SetlistItemResult>[])
        result.itemId: result,
    };
    // §5.4/A5 — every upcoming tuning/capo change is announced BEFORE the
    // run starts, not only once the affected song begins.
    final tuningChangesAhead = _tuningChangesAhead(widget.setlist.items);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          isPractice
              ? l10n.setlistSessionPracticeTitle
              : l10n.setlistSessionPerformanceTitle,
        ),
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(SsSpacing.space4),
              child: Semantics(
                liveRegion: true,
                label: isPractice
                    ? l10n.setlistSessionPracticeSemantics
                    : l10n.setlistSessionPerformanceSemantics,
                child: Text(
                  isPractice
                      ? l10n.setlistSessionPracticeDescription
                      : l10n.setlistSessionPerformanceDescription,
                  style: typography.bodyMedium.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ),
            if (tuningChangesAhead.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: SsSpacing.space4,
                ),
                child: Semantics(
                  key: const Key('setlist-session-tuning-ahead'),
                  container: true,
                  child: SsCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Icon(Icons.tune, color: colors.textPrimary),
                            const SizedBox(width: SsSpacing.space2),
                            Expanded(
                              child: Text(
                                l10n.setlistSessionTuningAheadTitle,
                                style: typography.labelLarge.copyWith(
                                  color: colors.textPrimary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        for (final item in tuningChangesAhead)
                          Text(
                            _reminderText(l10n, item),
                            style: typography.bodyMedium.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            Expanded(
              child: ListView.builder(
                key: const Key('setlist-session-window'),
                itemCount: widget.setlist.items.length,
                itemBuilder: (context, index) {
                  final item = widget.setlist.items[index];
                  final result = resultByItem[item.id];
                  return ListTile(
                    title: Text(item.songId.value),
                    subtitle: Text(_itemStatus(l10n, item, result)),
                    trailing: _reminder(l10n, item),
                  );
                },
              ),
            ),
            if (_result != null)
              Semantics(
                key: const Key('setlist-session-result'),
                liveRegion: true,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SsSpacing.space4,
                  ),
                  child: Text(
                    l10n.setlistSessionResult(
                      _result!.itemResults
                          .where(
                            (result) =>
                                result.status ==
                                SetlistItemResultStatus.completed,
                          )
                          .length,
                      _result!.itemResults.length,
                    ),
                    style: typography.bodyMedium.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ),
            // Stays a literal FilledButton.icon (not SsButton): the running
            // state swaps the icon for a bespoke inline spinner while
            // keeping the label text visible ("Running…") — SsButton's own
            // `loading` affordance instead hides the label under an
            // overlay spinner, which would change what is on screen during
            // a run (§5.1 bit-identical behaviour).
            Padding(
              padding: const EdgeInsets.all(SsSpacing.space4),
              child: FilledButton.icon(
                key: const Key('setlist-session-start'),
                onPressed: _isRunning ? null : _run,
                icon: _isRunning
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(
                  _isRunning
                      ? l10n.setlistSessionRunning
                      : isPractice
                      ? l10n.setlistSessionStartPractice
                      : l10n.setlistSessionStartPerformance,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _itemStatus(
  AppLocalizations l10n,
  SongSetlistItem item,
  SetlistItemResult? result,
) {
  if (result == null) {
    return switch (item.initialAvailability) {
      SetlistItemAvailability.ready => l10n.setlistSessionReady,
      _ => l10n.setlistSessionRepairRequired,
    };
  }
  return switch (result.status) {
    SetlistItemResultStatus.completed => l10n.setlistSessionCompleted,
    SetlistItemResultStatus.skipped => l10n.setlistSessionSkipped,
    SetlistItemResultStatus.failed => l10n.setlistSessionFailed,
  };
}

Widget? _reminder(AppLocalizations l10n, SongSetlistItem item) {
  final capo = item.overrides.capoOverride;
  final tuning = item.overrides.tuningOverrideCode;
  if (capo != null) return Text(l10n.setlistSessionCapo(capo));
  if (tuning != null) return Text(l10n.setlistSessionTuning(tuning));
  return null;
}

String _reminderText(AppLocalizations l10n, SongSetlistItem item) {
  final capo = item.overrides.capoOverride;
  final tuning = item.overrides.tuningOverrideCode;
  if (tuning != null) return l10n.setlistSessionTuning(tuning);
  if (capo != null) return l10n.setlistSessionCapo(capo);
  return item.songId.value;
}

/// Items whose tuning/capo override differs from the one before them — the
/// exact transitions a performer would otherwise only discover once the
/// affected song starts playing (§5.4/A5).
List<SongSetlistItem> _tuningChangesAhead(List<SongSetlistItem> items) {
  final changes = <SongSetlistItem>[];
  SetlistItemOverrides? previous;
  for (final item in items) {
    final overrides = item.overrides;
    if (previous != null &&
        (overrides.tuningOverrideCode != previous.tuningOverrideCode ||
            overrides.capoOverride != previous.capoOverride)) {
      changes.add(item);
    }
    previous = overrides;
  }
  return changes;
}
