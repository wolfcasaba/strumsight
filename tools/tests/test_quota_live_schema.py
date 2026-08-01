import unittest

from tools.ai_router.quota import parse_quota_payload


class QuotaLiveSchemaRegressionTest(unittest.TestCase):
    def test_percentage_schema_does_not_report_false_zero(self) -> None:
        result = parse_quota_payload(
            {
                "base_resp": {"status_code": 0},
                "model_remains": [
                    {
                        "model_name": "general",
                        "current_interval_total_count": 0,
                        "current_interval_usage_count": 0,
                        "current_interval_remaining_percent": 100,
                        "current_weekly_remaining_percent": 82,
                        "end_time": 1785596400000,
                        "weekly_end_time": 1785715200000,
                    }
                ],
            }
        )

        self.assertEqual(result.status, "ok")
        self.assertTrue(result.quota_known)
        self.assertIsNone(result.remaining_units)
        self.assertEqual(result.remaining_percent, 82)
        self.assertEqual(result.interval_reset_at, 1785596400000)
        self.assertEqual(result.weekly_reset_at, 1785715200000)


if __name__ == "__main__":
    unittest.main()
