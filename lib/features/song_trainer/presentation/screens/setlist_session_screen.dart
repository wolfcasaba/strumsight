import 'package:flutter/material.dart';

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
    final isPractice = widget.mode == SetlistSessionMode.practice;
    final resultByItem = <String, SetlistItemResult>{
      for (final result in _result?.itemResults ?? const <SetlistItemResult>[])
        result.itemId: result,
    };
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
              padding: const EdgeInsets.all(16),
              child: Semantics(
                liveRegion: true,
                label: isPractice
                    ? l10n.setlistSessionPracticeSemantics
                    : l10n.setlistSessionPerformanceSemantics,
                child: Text(
                  isPractice
                      ? l10n.setlistSessionPracticeDescription
                      : l10n.setlistSessionPerformanceDescription,
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
                  padding: const EdgeInsets.symmetric(horizontal: 16),
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
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
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
