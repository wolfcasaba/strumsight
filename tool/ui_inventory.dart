import 'dart:io';

/// A deterministic snapshot of production screen paths for the UI baseline.
final class UiInventory {
  UiInventory(this.repository);

  final Directory repository;

  /// Finds production screen sources without including test or fixture trees.
  UiInventoryResult render() {
    final featuresDirectory = Directory(
      '${repository.path}${Platform.pathSeparator}lib${Platform.pathSeparator}features',
    );
    final featureFiles =
        featuresDirectory
            .listSync(recursive: true)
            .whereType<File>()
            .map((file) => _relativePath(file.path))
            .where((path) => path.endsWith('.dart'))
            .toList()
          ..sort();
    final screenPaths = featureFiles
        .where((path) => path.endsWith('_screen.dart'))
        .toList();
    final reusableWidgetPaths = featureFiles
        .where((path) => path.contains('/widgets/') || path.contains('/views/'))
        .toList();
    final overlayPaths = featureFiles
        .where(
          (path) => _hasOverlay(
            File('${repository.path}${Platform.pathSeparator}$path'),
          ),
        )
        .toList();
    return UiInventoryResult._(
      List.unmodifiable(screenPaths),
      List.unmodifiable(reusableWidgetPaths),
      List.unmodifiable(overlayPaths),
    );
  }

  bool _hasOverlay(File file) {
    final source = file.readAsStringSync();
    return source.contains('showDialog') ||
        source.contains('showModalBottomSheet') ||
        source.contains('showBottomSheet');
  }

  String _relativePath(String absolutePath) {
    final normalizedRoot = repository.absolute.path;
    final normalizedPath = File(absolutePath).absolute.path;
    final prefix = '$normalizedRoot${Platform.pathSeparator}';
    if (!normalizedPath.startsWith(prefix)) {
      throw ArgumentError.value(
        absolutePath,
        'absolutePath',
        'outside repository',
      );
    }
    return normalizedPath.substring(prefix.length).replaceAll('\\', '/');
  }
}

/// Immutable result that can be rendered into reviewable Markdown.
final class UiInventoryResult {
  UiInventoryResult._(
    this.screenPaths,
    this.reusableWidgetPaths,
    this.overlayPaths,
  );

  final List<String> screenPaths;
  final List<String> reusableWidgetPaths;
  final List<String> overlayPaths;

  String toMarkdown() => [
    '# Production screen inventory',
    '',
    'Measured production screen sources: ${screenPaths.length}.',
    'Reusable widget/view sources: ${reusableWidgetPaths.length}.',
    'Dialog or bottom-sheet sources: ${overlayPaths.length}.',
    '',
    '| Screen source | Baseline status |',
    '| --- | --- |',
    for (final path in screenPaths) '| `$path` | Legacy / migration pending |',
    '',
    '## Reusable widget and view sources',
    '',
    for (final path in reusableWidgetPaths) '- `$path`',
    '',
    '## Dialog and bottom-sheet sources',
    '',
    for (final path in overlayPaths) '- `$path`',
    '',
  ].join('\n');
}

void main(List<String> arguments) {
  final repository = arguments.isEmpty
      ? Directory.current
      : Directory(arguments.single);
  stdout.write(UiInventory(repository).render().toMarkdown());
}
