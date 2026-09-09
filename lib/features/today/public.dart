/// Public Today-hub contract for other features (SDD Ch2 §10.4).
library;

/// The "10 useful minutes" chain (E14-R36, ADR 0546): the composition rule,
/// its step state machine and the pure interruption/evidence resolution the
/// Today hub renders from.
export 'domain/ten_minute_flow.dart';

/// Where each chain step sends the user — the single rule the ordinary
/// Today CTA and the chain's play step share.
export 'domain/ten_minute_flow_destinations.dart';

/// The chain controller. The tuner advances it when the player says they
/// are done tuning; nothing else outside `features/today/` writes to it.
export 'providers/ten_minute_flow_providers.dart';
