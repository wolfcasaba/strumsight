import 'package:flutter/foundation.dart';

import '../../../core/music/strum.dart';

/// One slot in a bar's rolling beat counter ("1 & 2 & 3 & 4").
///
/// Live-specific view model: it exists only to drive the Live beat counter,
/// so it deliberately stayed in the feature when [Strum] moved to
/// `core/music` in E01-R10 (a shared domain model is one another feature can
/// reasonably consume — nothing outside Live counts beats this way).
@immutable
class BeatSlot {
  const BeatSlot({required this.label, required this.isDownbeat, this.strum});

  /// Display label: "1", "&", "2", …
  final String label;

  /// True on the numbered beats (1, 2, 3, 4), false on the "&" offbeats.
  final bool isDownbeat;

  /// The strum played on this slot, or null if none.
  final Strum? strum;
}
