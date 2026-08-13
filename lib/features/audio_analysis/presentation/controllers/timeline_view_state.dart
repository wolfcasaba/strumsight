import 'timeline_viewport.dart';

/// Immutable presentation state for gesture-driven viewport updates.
final class TimelineViewState {
  const TimelineViewState({
    required this.viewport,
    this.selectionStart,
    this.selectionEnd,
  });
  final TimelineViewport viewport;
  final Duration? selectionStart;
  final Duration? selectionEnd;

  TimelineViewState copyWith({
    TimelineViewport? viewport,
    Duration? selectionStart,
    Duration? selectionEnd,
  }) => TimelineViewState(
    viewport: viewport ?? this.viewport,
    selectionStart: selectionStart ?? this.selectionStart,
    selectionEnd: selectionEnd ?? this.selectionEnd,
  );

  /// Removes the selected range without relying on nullable [copyWith] input.
  TimelineViewState clearSelection() => TimelineViewState(viewport: viewport);
}
