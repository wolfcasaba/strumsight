import 'package:strumsight/core/foundation/app_failure.dart';
import 'package:strumsight/core/foundation/app_result.dart';

import 'tutor_model_event.dart';
import 'tutor_model_gateway.dart';
import 'tutor_model_request.dart';

/// Failure code for capability-unavailable scenarios.
///
/// This stub represents a gateway that cannot operate in the current
/// environment (e.g., missing backend proxy, disabled feature flag).
const String _capabilityUnavailableCode = 'tutor.model_gateway.unavailable';

/// A local stub that always reports capability unavailable.
///
/// Use this stub when the tutor model gateway is not available in the
/// current environment (e.g., offline mode, feature disabled, backend
/// proxy not configured). The stub returns a consistent failure for
/// all operations, allowing the contract test suite to verify that
/// callers handle unavailability correctly.
final class LocalTutorModelGatewayStub implements TutorModelGateway {
  @override
  Future<AppResult<Stream<TutorModelEvent>>> start(
    TutorModelRequest request,
  ) async {
    return const AppResult.failure(
      UnknownFailure(code: _capabilityUnavailableCode),
    );
  }

  @override
  void cancel() {
    // No-op: no active session to cancel.
  }

  @override
  Future<AppResult<void>> health() async {
    return const AppResult.failure(
      UnknownFailure(code: _capabilityUnavailableCode),
    );
  }
}
