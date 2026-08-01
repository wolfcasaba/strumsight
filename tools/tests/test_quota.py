import io
import json
import tempfile
import unittest
import urllib.error
from pathlib import Path

from tools.ai_router.quota import check_quota, parse_quota_payload


class FakeResponse:
    def __init__(self, payload: dict[str, object]):
        self.payload = json.dumps(payload).encode()

    def __enter__(self) -> "FakeResponse":
        return self

    def __exit__(self, *_: object) -> None:
        return None

    def read(self, limit: int) -> bytes:
        return self.payload[:limit]


class QuotaTest(unittest.TestCase):
    def test_parses_known_model_remains_without_raw_body(self) -> None:
        result = parse_quota_payload(
            {
                "base_resp": {"status_code": 0, "status_msg": "success"},
                "model_remains": [
                    {
                        "model_name": "MiniMax-M3",
                        "current_interval_total_count": 100,
                        "current_interval_usage_count": 40,
                        "current_interval_end_time": 123456,
                    }
                ],
                "private_field": "must-not-leak",
            }
        )

        encoded = json.dumps(result.to_dict())
        self.assertEqual(result.status, "ok")
        self.assertTrue(result.quota_known)
        self.assertEqual(result.remaining_units, 60)
        self.assertNotIn("private_field", encoded)
        self.assertNotIn("must-not-leak", encoded)

    def test_unknown_success_schema_fails_closed(self) -> None:
        result = parse_quota_payload({"unexpected": {"shape": True}})

        self.assertEqual(result.status, "unknown_response")
        self.assertFalse(result.quota_known)

    def test_http_429_is_quota_not_model_failure(self) -> None:
        def opener(*_: object, **__: object) -> object:
            raise urllib.error.HTTPError("url", 429, "limited", {}, io.BytesIO())

        result = check_quota("secret", opener=opener)

        self.assertEqual(result.status, "quota_limited")
        self.assertFalse(result.quota_known)

    def test_http_401_is_credential_block(self) -> None:
        def opener(*_: object, **__: object) -> object:
            raise urllib.error.HTTPError("url", 401, "unauthorized", {}, io.BytesIO())

        self.assertEqual(check_quota("secret", opener=opener).status, "credential_blocked")

    def test_authorization_value_never_enters_result(self) -> None:
        seen: list[str] = []

        def opener(request: object, *, timeout: float) -> FakeResponse:
            seen.append(request.get_header("Authorization"))
            return FakeResponse(
                {
                    "base_resp": {"status_code": 0},
                    "model_remains": [
                        {
                            "model_name": "MiniMax-M3",
                            "current_interval_total_count": 10,
                            "current_interval_usage_count": 1,
                        }
                    ],
                }
            )

        result = check_quota("secret-token", opener=opener)

        self.assertEqual(seen, ["Bearer secret-token"])
        self.assertNotIn("secret-token", json.dumps(result.to_dict()))


if __name__ == "__main__":
    unittest.main()
