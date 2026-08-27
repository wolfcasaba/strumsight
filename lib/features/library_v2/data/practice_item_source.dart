import '../domain/library_item.dart';
import '../domain/library_item_source.dart';

/// Wraps the existing practice history repository via an injected loader.
/// The repository's concrete type is intentionally never named in this
/// file: `practice/public.dart` exports only `practiceHistoryRepositoryProvider`,
/// not the `PracticeHistoryRepository` type itself, so the caller
/// (`library_v2_providers.dart`) builds the loader from the provider and
/// this class stays a plain callback wrapper (read-only in this round —
/// no per-entry delete exists on that contract yet, §0.0/B3).
final class PracticeItemSource implements LibraryItemSource {
  const PracticeItemSource(this._load);

  final Future<LibrarySourceLoad> Function() _load;

  @override
  LibraryItemType get type => LibraryItemType.practice;

  @override
  Future<LibrarySourceLoad> load() => _load();
}
