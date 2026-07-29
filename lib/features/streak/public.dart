/// Public streak contract for other features (SDD Ch2 §10.4).
library;

/// Pure streak maths (no clock) and the daily challenge definition.
export 'streak_logic.dart';
export 'daily_challenge.dart';

/// Current streak state + "practised today" credit.
export 'providers/streak_provider.dart';

/// The flame badge shown on the Live screen.
export 'widgets/streak_badge.dart';
