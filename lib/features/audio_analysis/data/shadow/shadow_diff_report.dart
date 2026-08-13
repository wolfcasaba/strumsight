/// Deterministic V1/V2 comparison facts produced by one shadow execution.
///
/// The report deliberately contains no timestamp, PCM, filename, or other
/// raw input data. It is diagnostics-only and never changes the V1 result.
final class ShadowDiffReport {
  const ShadowDiffReport({
    required this.v1EventCount,
    required this.v2EventCount,
    required this.v1ChordSegmentCount,
    required this.v2ChordSegmentCount,
    required this.v1Bpm,
    required this.v2Bpm,
    required this.v1Duration,
    required this.v2Duration,
    required this.v1Runtime,
    required this.v2Runtime,
    required this.v2Failed,
  });

  final int v1EventCount;
  final int v2EventCount;
  final int v1ChordSegmentCount;
  final int v2ChordSegmentCount;
  final double v1Bpm;
  final double? v2Bpm;
  final Duration v1Duration;
  final Duration? v2Duration;
  final Duration v1Runtime;
  final Duration? v2Runtime;
  final bool v2Failed;
}
