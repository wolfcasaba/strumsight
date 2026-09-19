/// Public streak contract for other features (SDD Ch2 §10.4).
library;

/// Pure streak maths (no clock) and the daily challenge definition.
export 'streak_logic.dart';
export 'daily_challenge.dart';

/// Current streak state + "practised today" credit.
///
/// The state TYPE travels with the provider: `streakProvider` is
/// `NotifierProvider<StreakController, StreakData>`, so a consumer that could not
/// name `StreakData` could read `streak.current` through inference but never
/// declare the type — an incomplete public API rather than a deliberate boundary.
export 'model/streak_data.dart';
export 'providers/streak_provider.dart';

/// The flame badge shown on the Live screen.
export 'widgets/streak_badge.dart';
