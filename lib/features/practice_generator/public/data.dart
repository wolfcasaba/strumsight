export '../data/adapter/legacy_lesson_candidate_adapter.dart';
export '../data/adapter/legacy_lesson_catalog_adapter.dart';
export '../data/adapter/legacy_mapping_table.dart';
export '../data/adapter/legacy_progress_evidence_adapter.dart';
export '../data/adapter/practice_outcome_adapter.dart';
export '../data/adapter/analysis_evidence_adapter.dart';
export '../data/adapter/vision_evidence_adapter.dart';
export '../data/adapter/tutor_plan_proposal_adapter.dart';
export '../data/adapter/practice_engine_catalog_adapter.dart';
export '../data/adapter/song_goal_reader_adapter.dart';
export '../data/ai/planner_assist_schema.dart';
export '../data/ai/remote_planner_assist_gateway.dart';
export '../data/ai/fake_planner_assist_gateway.dart';
export '../data/local/local_practice_evidence_repository.dart';
export '../data/local/local_practice_plan_repository.dart';
export '../data/local/practice_plan_migrator.dart';
// The older serializer record is repository-local. R23 publishes the richer
// execution [PracticeOutcome] instead; local persistence keeps importing its
// own record type directly.
export '../data/local/practice_plan_serializer.dart' hide PracticeOutcome;
