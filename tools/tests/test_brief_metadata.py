import tempfile
import unittest
from pathlib import Path

from tools.ai_router.brief import BriefMetadataError, load_brief, parse_brief_metadata


VALID = '''# E03-R01 — Example

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = ["lib/features/example.dart", "test/features/example_test.dart"]
gate_tests = ["test/features/example_test.dart"]
native_gate = false
```

## 1. Cél
Example task.
'''


class BriefMetadataTest(unittest.TestCase):
    def test_parses_exactly_one_typed_block(self) -> None:
        brief = parse_brief_metadata(VALID)

        self.assertEqual(brief.metadata.risk, "normal")
        self.assertEqual(brief.metadata.allowed_paths[0], "lib/features/example.dart")
        self.assertIn("Example task", brief.text)

    def test_loads_task_id_from_filename(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "e03-r01-example.md"
            path.write_text(VALID)

            brief = load_brief(path)

            self.assertEqual(brief.task_id, "E03-R01")

    def test_rejects_missing_duplicate_or_unknown_metadata(self) -> None:
        with self.assertRaises(BriefMetadataError):
            parse_brief_metadata("# no metadata")
        with self.assertRaises(BriefMetadataError):
            parse_brief_metadata(VALID + VALID)
        with self.assertRaisesRegex(BriefMetadataError, "unknown"):
            parse_brief_metadata(VALID.replace("native_gate = false", "native_gate = false\nextra = 1"))

    def test_rejects_unsafe_paths_and_gate_arguments(self) -> None:
        replacements = (
            ('"lib/features/example.dart"', '"../outside"'),
            ('"lib/features/example.dart"', '"/absolute"'),
            ('"test/features/example_test.dart"', '"test/example;touch"'),
        )
        for old, new in replacements:
            with self.subTest(new=new), self.assertRaises(BriefMetadataError):
                parse_brief_metadata(VALID.replace(old, new, 1))

    def test_rejects_invalid_types_risk_and_empty_lists(self) -> None:
        invalid = (
            VALID.replace('risk = "normal"', 'risk = "critical"'),
            VALID.replace("native_gate = false", 'native_gate = "no"'),
            VALID.replace(
                'allowed_paths = ["lib/features/example.dart", "test/features/example_test.dart"]',
                "allowed_paths = []",
            ),
            VALID.replace('gate_tests = ["test/features/example_test.dart"]', "gate_tests = []"),
        )
        for content in invalid:
            with self.assertRaises(BriefMetadataError):
                parse_brief_metadata(content)


if __name__ == "__main__":
    unittest.main()
