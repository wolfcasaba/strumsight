/// Public practice-log contract for other features (SDD Ch2 §10.4).
library;

/// One logged practice session and the aggregate stats derived from the log.
export 'model/practice_entry.dart';
export 'model/practice_stats.dart';

/// Append to / read the practice log (Live, Learn, Analyze, Streak).
export 'providers/practice_log_provider.dart';
