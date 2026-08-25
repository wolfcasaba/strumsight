import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

/// `initializeDateFormatting` loads symbol/pattern data for EVERY locale in
/// one synchronous pass (the `locale` argument is ignored — see
/// `package:intl/date_symbol_data_local.dart`), so calling it once, lazily,
/// on first use is enough for the life of the isolate.
bool _dateSymbolsReady = false;

void _ensureDateSymbols() {
  if (_dateSymbolsReady) return;
  initializeDateFormatting();
  _dateSymbolsReady = true;
}

/// Locale-aware formatters for the numeric/date values StrumSight renders
/// (practice duration, tempo, tuning offset, progress percentage, session
/// date) — `package:intl` under the hood, never manual string building or
/// `toString()` (ADR 0424 §5.3). The locale is always a required parameter
/// and none reads `BuildContext`, so each is testable in isolation; [date]
/// is not otherwise pure — its first call lazily writes the memoized
/// `_dateSymbolsReady` module global via [_ensureDateSymbols].
abstract final class SsFormatters {
  /// Elapsed practice time as decimal minutes (e.g. 12.5) — the decimal
  /// separator is the locale's (`.` in en, `,` in hu).
  static String duration(Duration value, {required String localeName}) {
    final minutes = value.inMilliseconds / Duration.millisecondsPerMinute;
    return NumberFormat('0.0', localeName).format(minutes);
  }

  /// Tempo in beats per minute, grouped for large values.
  static String bpm(num value, {required String localeName}) =>
      NumberFormat.decimalPattern(localeName).format(value);

  /// Tuning offset in cents, always signed (`+0.0` for in-tune).
  static String cents(num value, {required String localeName}) =>
      NumberFormat('+0.0;-0.0', localeName).format(value);

  /// [ratio] in `[0, 1]` as a percentage, e.g. `0.4567` → `45.7%` (en) /
  /// `45,7%` (hu) at `decimalDigits: 1`.
  static String percent(
    num ratio, {
    required String localeName,
    int decimalDigits = 0,
  }) => NumberFormat.decimalPercentPattern(
    locale: localeName,
    decimalDigits: decimalDigits,
  ).format(ratio);

  /// A calendar date in the locale's customary long form.
  static String date(DateTime value, {required String localeName}) {
    _ensureDateSymbols();
    return DateFormat.yMMMd(localeName).format(value);
  }
}
