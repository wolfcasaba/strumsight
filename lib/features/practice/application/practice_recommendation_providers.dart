import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/model/next_practice_recommendation.dart';
import '../domain/service/next_practice_recommender.dart';
import 'practice_catalog_controller.dart';
import 'practice_progress_providers.dart';

/// The learner's next practice, derived from the catalog and the persisted
/// V2 history ([recommendNextPractice]). While the history is still loading
/// (or failed to load) the recommendation is made from an empty history,
/// which yields the catalog's easiest entry — never nothing, never an
/// invented one. `null` only for an empty catalog.
final nextPracticeRecommendationProvider =
    Provider<NextPracticeRecommendation?>((ref) {
      final catalog = ref.watch(practiceCatalogProvider);
      final history =
          ref.watch(practiceHistoryV2ListProvider).value ?? const [];
      return recommendNextPractice(catalog: catalog, history: history);
    });
