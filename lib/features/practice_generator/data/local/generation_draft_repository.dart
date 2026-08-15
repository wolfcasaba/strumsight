/// Local persistence for the setup wizard's in-progress draft (ADR 0259 §3).
library;

import 'dart:async';
import 'dart:convert';

import '../../../../core/foundation/app_failure.dart';
import '../../../../core/foundation/app_result.dart';
import '../../../../core/storage/key_value_store.dart';
import '../../domain/model/practice_generation_request.dart';
import 'generation_request_serializer.dart';

/// The single wizard-in-progress draft, isolated from any active-plan
/// storage (ADR 0259 §3).
///
/// Holds at most one draft, under [draftStorageKey] — a key namespace
/// dedicated to this repository and never shared with the active-plan
/// store. A corrupt or future-schema draft never propagates as a crash: it
/// surfaces as `AppResult.failure(StorageFailure)` so the caller can show a
/// recoverable "couldn't restore your draft" state and let the wizard start
/// over (ADR 0259 §4).
class GenerationDraftRepository {
  GenerationDraftRepository({
    required this.keyValueStore,
    this.serializer = const GenerationRequestSerializer(),
  });

  final KeyValueStore keyValueStore;
  final GenerationRequestSerializer serializer;

  /// Dedicated to the wizard draft — deliberately never the key an active
  /// plan is stored under (ADR 0259 §3). A shared key with a status field
  /// would let one bad draft write clobber the executed plan; a separate
  /// key namespace makes that structurally impossible.
  static const String draftStorageKey =
      'ss.practice_generator.generation_draft';

  /// Loads the current draft, or `Success(null)` when none has been saved.
  ///
  /// A malformed envelope, an undecodable payload, or a schema version this
  /// build cannot read (older than migration reaches, or newer than the
  /// code knows) surfaces as a [StorageFailure] — never a thrown exception,
  /// never a silently discarded draft.
  Future<AppResult<PracticeGenerationRequest?>> loadDraft() async {
    try {
      final raw = keyValueStore.readString(draftStorageKey);
      if (raw == null) {
        return const Success<PracticeGenerationRequest?>(null);
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('draft envelope is not a JSON object');
      }
      final request = serializer.fromJson(decoded);
      return Success<PracticeGenerationRequest?>(request);
    } catch (e, stackTrace) {
      return Failure<PracticeGenerationRequest?>(
        StorageFailure(
          code: FailureCode.storageRead,
          cause: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Overwrites the current draft. Never touches any other storage key.
  Future<AppResult<void>> saveDraft(PracticeGenerationRequest draft) async {
    try {
      await keyValueStore.writeString(
        draftStorageKey,
        jsonEncode(serializer.toJson(draft)),
      );
      return const Success<void>(null);
    } on StorageException catch (e, stackTrace) {
      return Failure<void>(
        StorageFailure(
          code: FailureCode.storageWrite,
          cause: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  /// Idempotent: clearing an already-absent draft still succeeds.
  Future<AppResult<void>> clearDraft() async {
    try {
      await keyValueStore.remove(draftStorageKey);
      return const Success<void>(null);
    } on StorageException catch (e, stackTrace) {
      return Failure<void>(
        StorageFailure(
          code: FailureCode.storageWrite,
          cause: e,
          stackTrace: stackTrace,
        ),
      );
    }
  }

  bool get hasDraft => keyValueStore.contains(draftStorageKey);
}
