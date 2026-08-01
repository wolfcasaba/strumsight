import re
import shlex
import unittest
from pathlib import Path

from tools.ai_router.brief import load_brief


ROOT = Path(__file__).resolve().parents[2]
BRIEF_DIR = ROOT / "docs" / "rounds"
HIGH_RISK_ROUNDS = {6, 7, 8, 9, 10, 11, 12, 14, 16, 18, 19, 20, 21, 22}


def section(text: str, number: int) -> str:
    match = re.search(
        rf"^## {number}\.[^\n]*\n(.*?)(?=^## {number + 1}\.)",
        text,
        re.MULTILINE | re.DOTALL,
    )
    if match is None:
        raise AssertionError(f"missing section {number}")
    return match.group(1)


class Epic3BriefMetadataTest(unittest.TestCase):
    def test_all_twenty_two_briefs_match_their_committed_scope_and_gate(self) -> None:
        paths = sorted(BRIEF_DIR.glob("e03-r??-*.md"))
        self.assertEqual(len(paths), 22)
        self.assertEqual(
            [path.name[5:7] for path in paths],
            [f"{index:02d}" for index in range(1, 23)],
        )

        for index, path in enumerate(paths, 1):
            with self.subTest(round=index, brief=path.name):
                text = path.read_text(encoding="utf-8")
                self.assertEqual(text.count("```ai-router\n"), 1)
                brief = load_brief(path)
                self.assertEqual(brief.task_id, f"E03-R{index:02d}")

                scope_paths = tuple(
                    re.findall(r"^\| `([^`]+)` \|", section(text, 4), re.MULTILINE)
                )
                self.assertTrue(scope_paths)
                self.assertEqual(brief.metadata.allowed_paths, scope_paths)
                self.assertFalse(any(value in {".", "*", "**"} for value in scope_paths))

                gate_section = section(text, 7)
                command = re.search(
                    r"```bash\n(tools/round-gate\.sh[^\n]*)\n```",
                    gate_section,
                )
                self.assertIsNotNone(command)
                arguments = tuple(shlex.split(command.group(1))[1:])
                self.assertTrue(arguments)
                self.assertTrue(all(value.startswith("test/") for value in arguments))
                self.assertEqual(brief.metadata.gate_tests, arguments)

                expected_risk = "high" if index in HIGH_RISK_ROUNDS else "normal"
                self.assertEqual(brief.metadata.risk, expected_risk)
                has_native_scope = any(
                    value.startswith(("android/", "ios/", "macos/", "linux/", "windows/"))
                    or value.endswith((".kt", ".java", ".cpp", ".cc", ".c", ".h"))
                    for value in scope_paths
                )
                self.assertEqual(brief.metadata.native_gate, has_native_scope)


if __name__ == "__main__":
    unittest.main()
