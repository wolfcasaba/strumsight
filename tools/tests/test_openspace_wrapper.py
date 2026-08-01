import json
import tempfile
import unittest
from pathlib import Path

from tools.ai_router.openspace import build_openspace_environment


class OpenspaceWrapperTest(unittest.TestCase):
    def test_injects_private_credential_into_child_copy_only(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "config.json"
            source.write_text(json.dumps({"api_key": "private-test-key"}))
            source.chmod(0o600)
            parent = {"SAFE": "yes", "OPENAI_API_KEY": "stale"}

            child = build_openspace_environment(source, parent)

        self.assertEqual(child["OPENAI_API_KEY"], "private-test-key")
        self.assertEqual(child["SAFE"], "yes")
        self.assertEqual(parent["OPENAI_API_KEY"], "stale")


if __name__ == "__main__":
    unittest.main()
