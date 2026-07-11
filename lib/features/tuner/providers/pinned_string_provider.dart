import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../model/guitar_strings.dart';

/// The manually pinned target string (round 91), or null for auto (chromatic)
/// mode. Session-only by design — pinning is a moment-to-moment tool, not a
/// preference.
class PinnedStringNotifier extends Notifier<GuitarString?> {
  @override
  GuitarString? build() => null;

  /// Tap a chip: pin it; tap the pinned chip again: back to auto.
  void toggle(GuitarString s) => state = identical(state, s) ? null : s;

  /// Drop a pin that no longer exists in the selected tuning's string set —
  /// a stale target would read cents against a string that isn't shown.
  void reconcile(List<GuitarString> strings) {
    final pinned = state;
    if (pinned != null && !strings.any((s) => identical(s, pinned))) {
      state = null;
    }
  }
}

final pinnedStringProvider =
    NotifierProvider<PinnedStringNotifier, GuitarString?>(
        PinnedStringNotifier.new);
