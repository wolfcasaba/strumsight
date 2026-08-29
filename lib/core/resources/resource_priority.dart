/// Ordered priority for resources contending for the device's finite
/// capacity: live coaching audio outranks camera feedback, which outranks
/// background AI (ADR 0476 D1).
///
/// Declaration order IS priority order, highest first. Two consumers can
/// share a priority — equal priority never preempts (ADR 0476 D1/D2).
enum ResourcePriority {
  /// Live, on-device learning audio — the user is playing right now.
  liveAudio,

  /// Camera-based feedback (posture, technique).
  cameraFeedback,

  /// Background-running local AI (Epic 10, still `hold` — ADR 0476 D6).
  backgroundAi;

  /// True when this priority is strictly higher than [other] — i.e. this one
  /// may suspend an active [other], never the reverse (ADR 0476 D1/D2).
  bool outranks(ResourcePriority other) => index < other.index;
}
