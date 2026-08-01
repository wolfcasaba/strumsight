import tempfile
import unittest
from pathlib import Path

from tools.ai_router.classification import FailureClass, classify_provider_failure
from tools.ai_router.execution import ProcessRunner


class ExecutionEnvironmentTest(unittest.TestCase):
    def test_missing_executable_is_structured_environment_failure(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            result = ProcessRunner().run(
                [str(Path(directory) / "missing")],
                cwd=Path(directory),
                timeout_seconds=1,
            )

        self.assertEqual(result.returncode, 127)
        self.assertIn("unavailable", result.stderr)
        self.assertEqual(
            classify_provider_failure(result.returncode, (), result.stderr),
            FailureClass.ENV_BLOCKED,
        )


if __name__ == "__main__":
    unittest.main()
