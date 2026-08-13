import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../domain/analysis_document.dart';
import '../domain/analysis_hotspot.dart';
import 'controllers/timeline_view_state.dart';
import 'controllers/timeline_viewport.dart';
import 'widgets/hotspot_navigator.dart';
import 'widgets/labels_adapter.dart';
import 'widgets/timeline_lanes.dart';
import 'widgets/timeline_ruler.dart';

/// Zoomable, capability-aware V2 analysis timeline. It consumes persisted
/// evidence only; no PCM, engine type or timing metric is reconstructed here.
final class AnalysisTimelineScreen extends StatefulWidget {
  const AnalysisTimelineScreen({super.key, required this.document});
  final AnalysisDocument document;
  @override
  State<AnalysisTimelineScreen> createState() => _AnalysisTimelineScreenState();
}

final class _AnalysisTimelineScreenState extends State<AnalysisTimelineScreen> {
  TimelineViewState? _viewState;
  TimelineViewport? _scaleStartViewport;
  int? _selectedHotspotIndex;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final labels = AppLocalizationsOverviewLabels(l10n);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : 320.0;
        final state = _viewState;
        final viewport = state == null || state.viewport.logicalWidth != width
            ? TimelineViewport.full(
                duration: widget.document.timeline.duration,
                logicalWidth: width,
              )
            : state.viewport;
        return Scaffold(
          appBar: AppBar(title: Text(l10n.analysisTimelineTitle)),
          body: SafeArea(
            child: GestureDetector(
              onScaleUpdate: (details) => setState(() {
                final source = _scaleStartViewport ?? viewport;
                _viewState = _stateFor(viewport).copyWith(
                  viewport: source.zoomBy(
                    scale: details.scale,
                    focalTime: source.timeForPixel(details.localFocalPoint.dx),
                  ),
                );
              }),
              onScaleStart: (_) => _scaleStartViewport = viewport,
              onScaleEnd: (_) => _scaleStartViewport = null,
              onHorizontalDragUpdate: (details) => setState(() {
                _viewState = _stateFor(viewport).copyWith(
                  viewport: viewport.panBy(
                    Duration(
                      microseconds:
                          (-details.delta.dx /
                                  width *
                                  viewport.visibleDuration.inMicroseconds)
                              .round(),
                    ),
                  ),
                );
              }),
              onLongPressStart: (details) => setState(() {
                final selectionStart = viewport.timeForPixel(
                  details.localPosition.dx,
                );
                _viewState = _stateFor(viewport).clearSelection().copyWith(
                  selectionStart: selectionStart,
                  selectionEnd: selectionStart,
                );
              }),
              onLongPressMoveUpdate: (details) => setState(() {
                _viewState = _stateFor(viewport).copyWith(
                  selectionEnd: viewport.timeForPixel(details.localPosition.dx),
                );
              }),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: <Widget>[
                  Text(l10n.analysisTimelineDescription),
                  const SizedBox(height: 8),
                  TimelineRuler(viewport: viewport),
                  if (state?.selectionStart != null &&
                      state?.selectionEnd != null)
                    Semantics(
                      label: l10n.analysisTimelineSelection(
                        labels.formatDuration(state!.selectionStart!),
                        labels.formatDuration(state.selectionEnd!),
                      ),
                      child: Text(
                        l10n.analysisTimelineSelection(
                          labels.formatDuration(state.selectionStart!),
                          labels.formatDuration(state.selectionEnd!),
                        ),
                      ),
                    ),
                  if (widget.document.hotspots.isNotEmpty)
                    Semantics(
                      container: true,
                      explicitChildNodes: true,
                      label: l10n.analysisTimelineHotspotList(
                        widget.document.hotspots.length,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          for (final (index, hotspot)
                              in widget.document.hotspots.indexed)
                            Semantics(
                              container: true,
                              label: _hotspotSemanticsLabel(
                                l10n,
                                index: index + 1,
                                count: widget.document.hotspots.length,
                                hotspot: hotspot,
                              ),
                              child: const SizedBox.shrink(),
                            ),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: () =>
                                  _navigateHotspot(viewport, previous: true),
                              child: Row(
                                children: <Widget>[
                                  const Icon(Icons.chevron_left),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      l10n.analysisTimelinePreviousHotspot,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton(
                              onPressed: () => _navigateHotspot(viewport),
                              child: Row(
                                children: <Widget>[
                                  const Icon(Icons.chevron_right),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      l10n.analysisTimelineNextHotspot,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  TimelineLanes(document: widget.document, viewport: viewport),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _navigateHotspot(TimelineViewport viewport, {bool previous = false}) {
    final navigator = HotspotNavigator(widget.document.hotspots);
    final result = previous
        ? navigator.previous(
            viewport: viewport,
            currentIndex: _selectedHotspotIndex,
          )
        : navigator.next(
            viewport: viewport,
            currentIndex: _selectedHotspotIndex,
          );
    setState(() {
      _selectedHotspotIndex = result.index;
      _viewState = _stateFor(viewport).copyWith(viewport: result.viewport);
    });
  }

  TimelineViewState _stateFor(TimelineViewport viewport) =>
      _viewState ?? TimelineViewState(viewport: viewport);

  String _hotspotSemanticsLabel(
    AppLocalizations l10n, {
    required int index,
    required int count,
    required AnalysisHotspot hotspot,
  }) => l10n.analysisTimelineHotspotItem(
    index,
    count,
    _hotspotKindLabel(l10n, hotspot.kind),
    _hotspotSeverityLabel(l10n, hotspot.severity),
  );

  String _hotspotKindLabel(AppLocalizations l10n, AnalysisHotspotKind kind) =>
      switch (kind) {
        AnalysisHotspotKind.timing => l10n.analysisTimelineHotspotKindTiming,
        AnalysisHotspotKind.rhythm => l10n.analysisTimelineHotspotKindRhythm,
        AnalysisHotspotKind.dynamics =>
          l10n.analysisTimelineHotspotKindDynamics,
        AnalysisHotspotKind.harmony => l10n.analysisTimelineHotspotKindHarmony,
        AnalysisHotspotKind.pitch => l10n.analysisTimelineHotspotKindPitch,
      };

  String _hotspotSeverityLabel(
    AppLocalizations l10n,
    AnalysisHotspotSeverity severity,
  ) => switch (severity) {
    AnalysisHotspotSeverity.low => l10n.analysisTimelineHotspotSeverityLow,
    AnalysisHotspotSeverity.medium =>
      l10n.analysisTimelineHotspotSeverityMedium,
    AnalysisHotspotSeverity.high => l10n.analysisTimelineHotspotSeverityHigh,
  };
}
