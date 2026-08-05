import 'package:meta/meta.dart';

/// Version identifier for prompt and schema contracts.
@immutable
final class PromptVersion {
  const PromptVersion._(this.value);

  static const PromptVersion v1 = PromptVersion._('v1');

  factory PromptVersion.parse(String value) => switch (value) {
    'v1' => v1,
    _ => throw ArgumentError.value(
      value,
      'value',
      'Unsupported prompt version.',
    ),
  };

  final String value;

  @override
  bool operator ==(Object other) =>
      other is PromptVersion && other.value == value;

  @override
  int get hashCode => value.hashCode;
}
