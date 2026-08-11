/// Lightweight, per-chunk microphone level feedback in dBFS.
final class RecordingLevel {
  const RecordingLevel({
    required this.peakDbfs,
    required this.rmsDbfs,
    required this.isClipping,
  });

  final double peakDbfs;
  final double rmsDbfs;
  final bool isClipping;
}
