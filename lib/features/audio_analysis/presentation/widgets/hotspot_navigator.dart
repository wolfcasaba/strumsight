import '../../domain/analysis_hotspot.dart';
import '../controllers/timeline_viewport.dart';

/// Immutable result of moving through the document's hotspot list.
final class HotspotNavigation {
  const HotspotNavigation({required this.index, required this.viewport});
  final int index;
  final TimelineViewport viewport;
}

/// Pure cyclic navigator. It never derives evidence; it only reveals the
/// already published hotspot range in the current viewport.
final class HotspotNavigator {
  const HotspotNavigator(this.hotspots);
  final List<AnalysisHotspot> hotspots;

  HotspotNavigation next({
    required TimelineViewport viewport,
    required int? currentIndex,
  }) {
    if (hotspots.isEmpty) {
      throw StateError('Cannot navigate an empty hotspot list.');
    }
    final index = currentIndex == null
        ? 0
        : (currentIndex + 1) % hotspots.length;
    final hotspot = hotspots[index];
    return HotspotNavigation(
      index: index,
      viewport: viewport.revealRange(hotspot.start, hotspot.end),
    );
  }

  HotspotNavigation previous({
    required TimelineViewport viewport,
    required int? currentIndex,
  }) {
    if (hotspots.isEmpty) {
      throw StateError('Cannot navigate an empty hotspot list.');
    }
    final index = currentIndex == null
        ? hotspots.length - 1
        : (currentIndex - 1 + hotspots.length) % hotspots.length;
    final hotspot = hotspots[index];
    return HotspotNavigation(
      index: index,
      viewport: viewport.revealRange(hotspot.start, hotspot.end),
    );
  }
}
