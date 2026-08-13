import 'package:flutter_test/flutter_test.dart';
import 'package:strumsight/features/audio_analysis/domain/analysis_hotspot.dart';
import 'package:strumsight/features/audio_analysis/presentation/controllers/timeline_viewport.dart';
import 'package:strumsight/features/audio_analysis/presentation/widgets/hotspot_navigator.dart';

void main() {
  final hotspots = <AnalysisHotspot>[
    _hotspot('a', 1),
    _hotspot('b', 4),
    _hotspot('c', 8),
  ];

  test(
    'next wraps after the final hotspot and reveals each selected range',
    () {
      final navigator = HotspotNavigator(hotspots);
      final initial = TimelineViewport(
        duration: const Duration(seconds: 10),
        logicalWidth: 400,
        start: Duration.zero,
        end: const Duration(seconds: 4),
      );

      final first = navigator.next(viewport: initial, currentIndex: null);
      final second = navigator.next(
        viewport: first.viewport,
        currentIndex: first.index,
      );
      final third = navigator.next(
        viewport: second.viewport,
        currentIndex: second.index,
      );
      final wrapped = navigator.next(
        viewport: third.viewport,
        currentIndex: third.index,
      );

      expect(
        <int>[first.index, second.index, third.index, wrapped.index],
        <int>[0, 1, 2, 0],
      );
      for (final navigation in <HotspotNavigation>[
        first,
        second,
        third,
        wrapped,
      ]) {
        final hotspot = hotspots[navigation.index];
        expect(navigation.viewport.start, lessThanOrEqualTo(hotspot.start));
        expect(navigation.viewport.end, greaterThanOrEqualTo(hotspot.end));
      }
    },
  );
}

AnalysisHotspot _hotspot(String id, int second) => AnalysisHotspot(
  id: id,
  kind: AnalysisHotspotKind.timing,
  start: Duration(seconds: second),
  end: Duration(seconds: second + 1),
  severity: AnalysisHotspotSeverity.medium,
  confidence: .8,
  metricIds: const <String>[],
  evidenceIds: const <String>[],
);
