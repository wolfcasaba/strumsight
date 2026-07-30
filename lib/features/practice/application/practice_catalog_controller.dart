import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/builtin_practice_catalog.dart';
import '../domain/model/practice_definition.dart';
import '../domain/repository/practice_catalog_repository.dart';

/// The active [PracticeCatalogRepository] for the running app.
///
/// Tests and adapters override this provider with a fake or alternative
/// repository; production code reads the const [BuiltinPracticeCatalog].
final practiceCatalogRepositoryProvider = Provider<PracticeCatalogRepository>((
  ref,
) {
  return const BuiltinPracticeCatalog();
});

/// The full, immutable list of authored practice definitions available to
/// the app. Reads from [practiceCatalogRepositoryProvider] so overriding
/// the repository automatically rewires this list.
final practiceCatalogProvider = Provider<List<PracticeDefinition>>((ref) {
  final repository = ref.watch(practiceCatalogRepositoryProvider);
  return repository.all();
});
