import unittest

from tools.ai_router.classification import (
    FailureClass,
    classify_gate_failure,
    classify_provider_failure,
    error_fingerprint,
    normalize_error,
)


class ClassificationTest(unittest.TestCase):
    def test_gate_categories_are_structural(self) -> None:
        self.assertEqual(classify_gate_failure("code_failure"), FailureClass.CODE_FAILURE)
        self.assertEqual(
            classify_gate_failure("environment_failure"), FailureClass.ENV_BLOCKED
        )
        self.assertEqual(classify_gate_failure("invalid_gate"), FailureClass.INVALID_TASK)
        self.assertEqual(classify_gate_failure("pass"), FailureClass.PASS)

    def test_provider_precedence_never_escalates_service_failures(self) -> None:
        self.assertEqual(
            classify_provider_failure(1, (), "HTTP 403 and 429"),
            FailureClass.CREDENTIAL_BLOCKED,
        )
        self.assertEqual(
            classify_provider_failure(1, (), "HTTP 429 rate limit"),
            FailureClass.PROVIDER_QUOTA,
        )
        self.assertEqual(
            classify_provider_failure(1, (), "upstream HTTP 503"),
            FailureClass.PROVIDER_TRANSIENT,
        )
        self.assertEqual(
            classify_provider_failure(124, (), "", timed_out=True),
            FailureClass.PROVIDER_TRANSIENT,
        )

    def test_structured_event_beats_unstructured_unknown_exit(self) -> None:
        events = ({"type": "error", "error": {"code": 429, "message": "limited"}},)
        self.assertEqual(
            classify_provider_failure(1, events, "unknown"), FailureClass.PROVIDER_QUOTA
        )

    def test_unknown_provider_failure_stops(self) -> None:
        self.assertEqual(classify_provider_failure(9, (), "mystery"), FailureClass.STOPPED)

    def test_normalization_produces_stable_fingerprint(self) -> None:
        first = "2026-08-01T12:00:01Z /tmp/work-123 test X failed\nrun_id=991"
        second = "2026-08-01T12:01:55Z /tmp/work-456 test X failed\nrun_id=992"

        self.assertEqual(normalize_error(first), normalize_error(second))
        self.assertEqual(error_fingerprint("test X", first), error_fingerprint("test X", second))


if __name__ == "__main__":
    unittest.main()
