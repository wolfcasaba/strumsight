import 'package:flutter/material.dart';

import '../../../../l10n/app_localizations.dart';
import '../../domain/analysis_capability.dart';
import '../../domain/analysis_document.dart';
import '../../domain/analysis_event.dart';
import '../../domain/analysis_hotspot.dart';
import '../controllers/timeline_viewport.dart';
import 'timeline_lane.dart';

/// Capability-aware composition of the eight timeline lanes mandated by R24.
final class TimelineLanes extends StatelessWidget {
  const TimelineLanes({
    required this.document,
    required this.viewport,
    super.key,
  });
  final AnalysisDocument document;
  final TimelineViewport viewport;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Column(
      children: <Widget>[
        _unavailable(
          context,
          TimelineLaneKind.waveform,
          l10n.analysisTimelineLaneWaveform,
          l10n.analysisTimelineNoPreview,
        ),
        _lane(
          context,
          TimelineLaneKind.chord,
          l10n.analysisTimelineLaneChord,
          AnalysisCapability.chordTimeline,
          document.timeline.chordSegments
              .map(
                (e) => TimelineLaneItem(
                  start: e.start,
                  end: e.end,
                  label: e.label,
                ),
              )
              .toList(),
          l10n.analysisTimelineItemCount(
            document.timeline.chordSegments.length,
          ),
        ),
        _lane(
          context,
          TimelineLaneKind.beatBar,
          l10n.analysisTimelineLaneBeatBar,
          AnalysisCapability.beatGrid,
          <TimelineLaneItem>[
            ...document.timeline.beats.map(
              (e) => TimelineLaneItem.point(e.time),
            ),
            ...document.timeline.bars.map(TimelineLaneItem.point),
          ],
          l10n.analysisTimelineItemCount(document.timeline.beats.length),
        ),
        _lane(
          context,
          TimelineLaneKind.onset,
          l10n.analysisTimelineLaneOnset,
          AnalysisCapability.onsetTimeline,
          document.timeline.events
              .whereType<OnsetEvent>()
              .map((e) => TimelineLaneItem.point(e.time))
              .followedBy(
                document.timeline.events.whereType<StrumEvent>().map(
                  (e) => TimelineLaneItem.point(e.time),
                ),
              )
              .toList(),
          l10n.analysisTimelineItemCount(
            document.timeline.events.whereType<OnsetEvent>().length +
                document.timeline.events.whereType<StrumEvent>().length,
          ),
        ),
        _lane(
          context,
          TimelineLaneKind.timing,
          l10n.analysisTimelineLaneTiming,
          AnalysisCapability.timingAccuracy,
          document.hotspots
              .where((e) => e.kind == AnalysisHotspotKind.timing)
              .map((e) => TimelineLaneItem(start: e.start, end: e.end))
              .toList(),
          l10n.analysisTimelineItemCount(
            document.hotspots
                .where((e) => e.kind == AnalysisHotspotKind.timing)
                .length,
          ),
        ),
        _lane(
          context,
          TimelineLaneKind.dynamics,
          l10n.analysisTimelineLaneDynamics,
          AnalysisCapability.dynamicConsistency,
          document.timeline.dynamicPoints
              .map((e) => TimelineLaneItem.point(e.time))
              .toList(),
          l10n.analysisTimelineItemCount(
            document.timeline.dynamicPoints.length,
          ),
        ),
        _lane(
          context,
          TimelineLaneKind.pitch,
          l10n.analysisTimelineLanePitch,
          AnalysisCapability.monophonicPitch,
          document.timeline.pitchSegments
              .map((e) => TimelineLaneItem(start: e.start, end: e.end))
              .toList(),
          l10n.analysisTimelineItemCount(
            document.timeline.pitchSegments.length,
          ),
        ),
        _hotspotLane(context, l10n),
      ],
    );
  }

  Widget _lane(
    BuildContext context,
    TimelineLaneKind kind,
    String title,
    AnalysisCapability capability,
    List<TimelineLaneItem> items,
    String summary,
  ) {
    CapabilityReport? report;
    for (final candidate in document.capabilities) {
      if (candidate.capability == capability) {
        report = candidate;
        break;
      }
    }
    final isAvailable = report?.status == CapabilityStatus.available;
    final isDegraded = report?.status == CapabilityStatus.degraded;
    if (!isAvailable && !isDegraded) {
      return _unavailable(
        context,
        kind,
        title,
        AppLocalizations.of(context).analysisTimelineMeasurementUnavailable,
      );
    }
    return TimelineLane(
      kind: kind,
      title: title,
      summary: summary,
      viewport: viewport,
      items: items,
      degraded: isDegraded,
    );
  }

  Widget _hotspotLane(BuildContext context, AppLocalizations l10n) {
    if (document.hotspots.isEmpty) {
      return _unavailable(
        context,
        TimelineLaneKind.hotspot,
        l10n.analysisTimelineLaneHotspots,
        l10n.analysisTimelineNoHotspots,
      );
    }
    return TimelineLane(
      kind: TimelineLaneKind.hotspot,
      title: l10n.analysisTimelineLaneHotspots,
      summary: l10n.analysisTimelineItemCount(document.hotspots.length),
      viewport: viewport,
      items: document.hotspots
          .map((e) => TimelineLaneItem(start: e.start, end: e.end))
          .toList(),
    );
  }

  Widget _unavailable(
    BuildContext context,
    TimelineLaneKind kind,
    String title,
    String reason,
  ) => Semantics(
    label: '$title: $reason',
    child: Padding(
      key: Key('timeline-unavailable-${kind.name}'),
      padding: const EdgeInsets.only(bottom: 8),
      child: Text('$title — $reason'),
    ),
  );
}
