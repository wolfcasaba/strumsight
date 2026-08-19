/// Coordinates caller-fed outcome ingestion with bounded adaptation.
library;

import '../../domain/model/adaptation_decision.dart';
import '../../domain/id/planner_ids.dart';
import '../../domain/model/review_item.dart';
import '../../domain/model/weekly_availability.dart';
import '../../domain/service/adaptation_decider.dart';
import '../../data/adapter/practice_outcome_adapter.dart';
import '../service/outcome_ingestion_service.dart';

/// Inputs for [RecordPracticeOutcome]. Persistence remains caller-owned.
final class RecordPracticeOutcomeRequest {
  const RecordPracticeOutcomeRequest({
    required this.ingestion,
    this.adaptationRequest,
  });

  final OutcomeIngestionRequest ingestion;
  final AdaptationRequest? adaptationRequest;
}

/// Explicit typed arguments passed through to [OutcomeIngestionService].
final class OutcomeIngestionRequest {
  const OutcomeIngestionRequest({
    required this.outcome,
    required this.activeRevisionId,
    required this.processedOutcomeIds,
    required this.reviewItems,
    required this.today,
  });

  final PracticeOutcome outcome;
  final RevisionId activeRevisionId;
  final Set<String> processedOutcomeIds;
  final Iterable<ReviewItem> reviewItems;
  final LocalDate today;
}

/// Result the application caller can persist or hand to the next planner.
final class RecordPracticeOutcomeResult {
  const RecordPracticeOutcomeResult({
    required this.ingestion,
    required this.adaptationDecision,
  });

  final OutcomeIngestionResult ingestion;
  final AdaptationDecision? adaptationDecision;
}

/// Runs adaptation only for newly processed, non-technical outcomes.
final class RecordPracticeOutcome {
  RecordPracticeOutcome({
    OutcomeIngestionService? ingestionService,
    AdaptationDecider? adaptationDecider,
  }) : _ingestionService = ingestionService ?? OutcomeIngestionService(),
       _adaptationDecider = adaptationDecider ?? AdaptationDecider();

  final OutcomeIngestionService _ingestionService;
  final AdaptationDecider _adaptationDecider;

  RecordPracticeOutcomeResult call(RecordPracticeOutcomeRequest request) {
    final input = request.ingestion;
    final ingestion = _ingestionService.ingest(
      outcome: input.outcome,
      activeRevisionId: input.activeRevisionId,
      processedOutcomeIds: input.processedOutcomeIds,
      reviewItems: input.reviewItems,
      today: input.today,
    );
    final decision = ingestion.canAdapt && request.adaptationRequest != null
        ? _adaptationDecider.decide(request.adaptationRequest!)
        : null;
    return RecordPracticeOutcomeResult(
      ingestion: ingestion,
      adaptationDecision: decision,
    );
  }
}
