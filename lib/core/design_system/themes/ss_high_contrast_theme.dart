import 'package:flutter/material.dart';

import 'ss_dark_theme.dart';

abstract final class SsHighContrastTheme {
  static ThemeData data() => SsDarkTheme.build(highContrast: true);
}
