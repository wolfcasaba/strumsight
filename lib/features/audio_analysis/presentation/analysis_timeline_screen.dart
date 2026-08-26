import 'package:flutter/material.dart';

import '../../../core/design_system/public.dart';
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
  const AnalysisTimelineScreen({
    super.key,
    required this.document,
    this.onPracticeSelection,
  });
  final AnalysisDocument document;

  /// Invoked with the normalised (start <= end) selected range when the
  /// user confirms "Practice this section" — either after a manual
  /// long-press selection or after tapping a hotspot in the event list
  /// (SDD Ch13 §25 A8). Null hides the action entirely; the screen never
  /// invents a range on its own.
  final void Function(Duration start, Duration end)? onPracticeSelection;

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
              key: const Key('timeline-gesture-area'),
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
              child: _buildList(
                context,
                l10n: l10n,
                labels: labels,
                viewport: viewport,
                state: state,
              ),
            ),
          ),
        );
      },
    );
  }

  /// Builder-based (not `ListView(children: […])`) so every section is
  /// built lazily — the event list below is the section whose size
  /// actually scales with the recording (SDD Ch13 §25 A4).
  Widget _buildList(
    BuildContext context, {
    required AppLocalizations l10n,
    required AppLocalizationsOverviewLabels labels,
    required TimelineViewport viewport,
    required TimelineViewState? state,
  }) {
    final hasSelection =
        state?.selectionStart != null && state?.selectionEnd != null;
    final sections = <Widget>[
      Text(l10n.analysisTimelineDescription),
      const SizedBox(height: 8),
      TimelineRuler(viewport: viewport),
      if (hasSelection) ...<Widget>[
        const SizedBox(height: 8),
        _selectionSection(l10n, labels, state!),
      ],
      if (widget.document.hotspots.isNotEmpty) ...<Widget>[
        const SizedBox(height: 8),
        _hotspotEventList(context, l10n, viewport),
        const SizedBox(height: 8),
        _hotspotNavigationButtons(l10n, viewport),
      ],
      const SizedBox(height: 8),
      TimelineLanes(document: widget.document, viewport: viewport),
    ];
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sections.length,
      itemBuilder: (context, index) => sections[index],
    );
  }

  Widget _selectionSection(
    AppLocalizations l10n,
    AppLocalizationsOverviewLabels labels,
    TimelineViewState state,
  ) {
    final selectionText = l10n.analysisTimelineSelection(
      labels.formatDuration(state.selectionStart!),
      labels.formatDuration(state.selectionEnd!),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Semantics(label: selectionText, child: Text(selectionText)),
        if (widget.onPracticeSelection != null) ...<Widget>[
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              key: const Key('timeline-practice-selection'),
              onPressed: () => _practiceSelection(state),
              child: Text(l10n.analysisTimelinePracticeSelection),
            ),
          ),
        ],
      ],
    );
  }

  Widget _hotspotEventList(
    BuildContext context,
    AppLocalizations l10n,
    TimelineViewport viewport,
  ) {
    final hotspots = widget.document.hotspots;
    return SsEventList(
      scrollableKey: const Key('timeline-hotspot-event-list'),
      semanticLabel: l10n.analysisTimelineHotspotList(hotspots.length),
      rows: <SsEventListRow>[
        for (final (index, hotspot) in hotspots.indexed)
          _hotspotEventListRow(
            l10n,
            index: index,
            count: hotspots.length,
            hotspot: hotspot,
            viewport: viewport,
          ),
      ],
    );
  }

  SsEventListRow _hotspotEventListRow(
    AppLocalizations l10n, {
    required int index,
    required int count,
    required AnalysisHotspot hotspot,
    required TimelineViewport viewport,
  }) {
    final label = _hotspotSemanticsLabel(
      l10n,
      index: index + 1,
      count: count,
      hotspot: hotspot,
    );
    return SsEventListRow(
      id: hotspot.id,
      label: label,
      semanticLabel: label,
      onTap: () => _selectHotspotRange(hotspot, viewport),
    );
  }

  Widget _hotspotNavigationButtons(
    AppLocalizations l10n,
    TimelineViewport viewport,
  ) {
    return Column(
      children: <Widget>[
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () => _navigateHotspot(viewport, previous: true),
            child: Row(
              children: <Widget>[
                const Icon(Icons.chevron_left),
                const SizedBox(width: 8),
                Expanded(child: Text(l10n.analysisTimelinePreviousHotspot)),
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
                Expanded(child: Text(l10n.analysisTimelineNextHotspot)),
              ],
            ),
          ),
        ),
      ],
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

  /// Selects exactly [hotspot]'s published range and reveals it — the same
  /// range "Practice this section" later hands to [AnalysisTimelineScreen.
  /// onPracticeSelection] (A8): tapping an event-list row IS a selection.
  void _selectHotspotRange(AnalysisHotspot hotspot, TimelineViewport viewport) {
    setState(() {
      _viewState = _stateFor(viewport).copyWith(
        viewport: viewport.revealRange(hotspot.start, hotspot.end),
        selectionStart: hotspot.start,
        selectionEnd: hotspot.end,
      );
    });
  }

  void _practiceSelection(TimelineViewState state) {
    final a = state.selectionStart!;
    final b = state.selectionEnd!;
    final start = a <= b ? a : b;
    final end = a <= b ? b : a;
    widget.onPracticeSelection!(start, end);
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
