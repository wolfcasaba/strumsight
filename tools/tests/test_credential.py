import json
import os
import tempfile
import unittest
from pathlib import Path

from tools.ai_router.credential import CredentialError, read_minimax_api_key


class CredentialTest(unittest.TestCase):
    def write_config(self, root: Path, *, mode: int = 0o600) -> Path:
        path = root / "config.json"
        path.write_text(json.dumps({"api_key": "test-secret-value", "region": "global"}))
        path.chmod(mode)
        return path

    def test_reads_owned_private_regular_file(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = self.write_config(Path(directory))

            self.assertEqual(read_minimax_api_key(path), "test-secret-value")

    def test_rejects_group_or_world_permissions(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = self.write_config(Path(directory), mode=0o640)

            with self.assertRaises(CredentialError):
                read_minimax_api_key(path)

    def test_rejects_special_permission_bits(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = self.write_config(Path(directory), mode=0o4600)

            with self.assertRaises(CredentialError):
                read_minimax_api_key(path)

    def test_rejects_symlink(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            target = self.write_config(root)
            link = root / "link.json"
            link.symlink_to(target)

            with self.assertRaises(CredentialError):
                read_minimax_api_key(link)

    def test_rejects_wrong_owner_without_disclosing_value(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = self.write_config(Path(directory))

            with self.assertRaisesRegex(CredentialError, "owner") as error:
                read_minimax_api_key(path, expected_uid=os.getuid() + 1)
            self.assertNotIn("test-secret-value", str(error.exception))


if __name__ == "__main__":
    unittest.main()
