/// Public surface of the Practice feature (SDD Ch2 §8.1, E02-R12).
///
/// Exposes the practice entry points another feature (or the app shell) is
/// allowed to know about — the Hub and Setup screens, the `PreparePractice`
/// sink, and the route argument parser. The Hub and Setup are flag-gated
/// routes: in a build with `practiceEngineV2Enabled == false` the routes are
/// not registered, so importing them here does NOT make them reachable.
library;

export 'presentation/practice_route_args.dart';
export 'presentation/screens/practice_hub_screen.dart';
export 'presentation/screens/practice_setup_screen.dart';
export 'presentation/widgets/practice_mode_card.dart';
export 'application/practice_setup_controller.dart';
