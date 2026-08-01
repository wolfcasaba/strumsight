import tempfile
import unittest
from pathlib import Path

from tools.ai_router.brief import load_brief
from tools.ai_router.config import load_config
from tools.ai_router.quota import QuotaStatus
from tools.ai_router.router import DevelopmentRouter, RouterStatus
from tools.ai_router.state import StateStore
from tools.tests.test_router import FakeGate, FakeModel, FakeScope, codex_ok, gate


class RouterBaselineAdapterTest(unittest.TestCase):
    def test_dedicated_baseline_gate_is_used_only_for_precheck(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            worktree = root / "worktree"
            worktree.mkdir()
            path = root / "e03-r01-baseline.md"
            path.write_text(
                "# Task\n```ai-router\nschema_version = 1\nrisk = \"normal\"\n"
                "allowed_paths = [\"lib/example.dart\"]\n"
                "gate_tests = [\"test/new_test.dart\"]\n"
                "native_gate = false\n```\n"
            )
            baseline = FakeGate([gate("pass")])
            normal = FakeGate([gate("pass")])
            model = FakeModel([codex_ok()])
            scope = FakeScope()
            router = DevelopmentRouter(
                config=load_config(Path(__file__).resolve().parents[2] / ".ai" / "router.toml"),
                state=StateStore(root / "state"),
                run_model=model,
                run_gate=normal,
                run_baseline_gate=baseline,
                check_quota=lambda: QuotaStatus("ok", True, True, remaining_percent=80),
                capture_manifest=scope.capture,
                audit_scope=scope.audit,
            )

            result = router.run(load_brief(path), worktree)

            self.assertEqual(result.status, RouterStatus.READY_FOR_REVIEW)
            self.assertEqual(baseline.calls, 1)
            self.assertEqual(normal.calls, 1)


if __name__ == "__main__":
    unittest.main()
