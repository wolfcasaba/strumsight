import 'dart:io';
import 'dart:math' as math;

abstract final class ContrastCheck {
  static const minimumTextContrast = 4.5;
  static const minimumNonTextContrast = 3.0;

  static bool meetsTextContrast(int first, int second) =>
      contrastRatio(first, second) >= minimumTextContrast;

  static bool meetsNonTextContrast(int first, int second) =>
      contrastRatio(first, second) >= minimumNonTextContrast;

  static bool meetsTextContrastForLuminances(double first, double second) =>
      contrastRatioFromLuminances(first, second) >= minimumTextContrast;

  static double contrastRatio(int first, int second) =>
      contrastRatioFromLuminances(
        relativeLuminance(first),
        relativeLuminance(second),
      );

  static double contrastRatioFromLuminances(double first, double second) {
    final light = first > second ? first : second;
    final dark = first > second ? second : first;
    return (light + .05) / (dark + .05);
  }

  static double relativeLuminance(int argb) {
    final red = _linear((argb >> 16) & 0xff);
    final green = _linear((argb >> 8) & 0xff);
    final blue = _linear(argb & 0xff);
    return .2126 * red + .7152 * green + .0722 * blue;
  }

  static double _linear(int channel) {
    final normalized = channel / 255;
    return normalized <= .04045
        ? normalized / 12.92
        : math.pow((normalized + .055) / 1.055, 2.4).toDouble();
  }
}

void main(List<String> arguments) {
  if (arguments.length != 2) {
    throw ArgumentError('Expected two ARGB hexadecimal colors.');
  }
  final first = int.parse(arguments[0].replaceFirst('#', ''), radix: 16);
  final second = int.parse(arguments[1].replaceFirst('#', ''), radix: 16);
  stdout.writeln(ContrastCheck.contrastRatio(first, second));
}
