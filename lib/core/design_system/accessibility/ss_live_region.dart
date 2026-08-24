import 'package:flutter/widgets.dart';

import '../foundations/ss_semantics.dart';

/// Throttles a fast-changing reading (several updates per second, the Stage
/// Mode/Live case ADR 0280 exists for) into a screen-reader-safe cadence: an
/// update is announced only when it is BOTH a genuinely different value than
/// the last announcement AND at least [SsSemantics.liveRegionAnnouncementGap]
/// after it (the gap boundary is inclusive — §0.0/D3).
///
/// A reading that arrives too soon after the last announcement is dropped,
/// not queued: it is compared against the last ANNOUNCED value, not the last
/// SEEN one, so a burst of intermediate values between two announcements
/// never itself becomes announceable once the gap has passed (verified by
/// `semantics_contract_test.dart` A1, "below the threshold").
///
/// [report] takes the reading time explicitly ([at]) rather than reading a
/// wall clock, so callers (and tests) drive it synchronously and
/// deterministically (`docs/LESSONS.md` L122).
final class SsLiveRegion extends ChangeNotifier {
  final List<String> _announcements = [];
  String? _lastAnnouncedValue;
  Duration? _lastAnnouncedAt;

  /// Every value this region has actually announced, in order.
  List<String> get announcements => List.unmodifiable(_announcements);

  /// The most recently announced value, or `null` before the first one.
  String? get current => _announcements.isEmpty ? null : _announcements.last;

  /// Reports a new reading at time [at]. Returns `true` iff it produced a
  /// new announcement.
  bool report(String value, {required Duration at}) {
    if (value == _lastAnnouncedValue) return false;

    final lastAt = _lastAnnouncedAt;
    if (lastAt != null &&
        (at - lastAt) < SsSemantics.liveRegionAnnouncementGap) {
      return false;
    }

    _lastAnnouncedValue = value;
    _lastAnnouncedAt = at;
    _announcements.add(value);
    notifyListeners();
    return true;
  }
}

/// Renders [controller]'s [SsLiveRegion.current] value as an invisible
/// `liveRegion` semantics node, so assistive tech speaks each throttled
/// announcement as it lands — never the raw, un-throttled reading.
final class SsLiveRegionAnnouncer extends StatelessWidget {
  const SsLiveRegionAnnouncer({super.key, required this.controller});

  final SsLiveRegion controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => Semantics(
        liveRegion: true,
        label: controller.current ?? '',
        child: const SizedBox.shrink(),
      ),
    );
  }
}
