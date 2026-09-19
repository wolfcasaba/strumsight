/// Public contract of the 60-second strum challenge for other features.
///
/// Hand-written barrel (no `public/` fragments). The Today hub reads today's
/// best through [strumChallengeBestProvider]; the router reaches the screen
/// directly, as it does every other screen.
library;

/// The pattern, the tempo, the bar count and the "full pattern" rule.
export 'domain/strum_challenge.dart';

/// Today's best as a persisted record.
export 'model/strum_challenge_best.dart';

/// Today's best (or null), and the clock it is keyed on.
export 'providers/strum_challenge_providers.dart';
