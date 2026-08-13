import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../domain/analysis_document.dart';
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
  TimelineViewport? _viewport;
  TimelineViewport? _scaleStartViewport;
  int? _selectedHotspotIndex;
  Duration? _selectionStart;
  Duration? _selectionEnd;
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final labels = AppLocalizationsOverviewLabels(l10n);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite && constraints.maxWidth > 0
            ? constraints.maxWidth
            : 320.0;
        final current = _viewport;
        final viewport = current == null || current.logicalWidth != width
            ? TimelineViewport.full(
                duration: widget.document.timeline.duration,
                logicalWidth: width,
              )
            : current;
        return Scaffold(
          appBar: AppBar(title: Text(l10n.analysisTimelineTitle)),
          body: SafeArea(
            child: GestureDetector(
              onScaleUpdate: (details) => setState(() {
                final source = _scaleStartViewport ?? viewport;
                _viewport = source.zoomBy(
                  scale: details.scale,
                  focalTime: source.timeForPixel(details.localFocalPoint.dx),
                );
              }),
              onScaleStart: (_) => _scaleStartViewport = viewport,
              onScaleEnd: (_) => _scaleStartViewport = null,
              onHorizontalDragUpdate: (details) => setState(() {
                _viewport = viewport.panBy(
                  Duration(
                    microseconds:
                        (-details.delta.dx /
                                width *
                                viewport.visibleDuration.inMicroseconds)
                            .round(),
                  ),
                );
              }),
              onLongPressStart: (details) => setState(() {
                _selectionStart = viewport.timeForPixel(
                  details.localPosition.dx,
                );
                _selectionEnd = _selectionStart;
              }),
              onLongPressMoveUpdate: (details) => setState(() {
                _selectionEnd = viewport.timeForPixel(details.localPosition.dx);
              }),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: <Widget>[
                  Text(l10n.analysisTimelineDescription),
                  const SizedBox(height: 8),
                  TimelineRuler(viewport: viewport),
                  if (_selectionStart != null && _selectionEnd != null)
                    Semantics(
                      label: l10n.analysisTimelineSelection(
                        labels.formatDuration(_selectionStart!),
                        labels.formatDuration(_selectionEnd!),
                      ),
                      child: Text(
                        l10n.analysisTimelineSelection(
                          labels.formatDuration(_selectionStart!),
                          labels.formatDuration(_selectionEnd!),
                        ),
                      ),
                    ),
                  if (widget.document.hotspots.isNotEmpty)
                    Semantics(
                      container: true,
                      label: l10n.analysisTimelineHotspotList(
                        widget.document.hotspots.length,
                      ),
                      child: Wrap(
                        spacing: 8,
                        children: <Widget>[
                          OutlinedButton.icon(
                            onPressed: () =>
                                _navigateHotspot(viewport, previous: true),
                            icon: const Icon(Icons.chevron_left),
                            label: Text(l10n.analysisTimelinePreviousHotspot),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _navigateHotspot(viewport),
                            icon: const Icon(Icons.chevron_right),
                            label: Text(l10n.analysisTimelineNextHotspot),
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
      _viewport = result.viewport;
    });
  }
}
