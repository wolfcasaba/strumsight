"""A driver HITELESÍTVE fetch-el a publikus repóból (ADR 0495 D5).

MÉRT eset (2026-09-03 07:40–08:05): a lánc három egymást követő firingen
`HIBA: git fetch origin main sikertelen`-nel esett ki, a szerver üzenete:

    GitHub is temporarily limiting some unauthenticated downloads to protect
    the stability of the platform. Please retry later or authenticate.

Az ok SZERKEZETI, nem alkalmi: a repó publikus, ezért a szerver a fetch-re nem
küld 401-et, a `store` credential-helper viszont kizárólag kihívásra tölt —
tehát minden fetch hitelesítetlen volt. Mérve ugyanezen a boxon: ugyanaz az
`ls-remote` a `http.extraHeader` Basic fejléccel AZONNAL sikeres.

A szerződés, amit ez a teszt rögzít:

1. van token → a driver exportálja a `GIT_CONFIG_*` hármast a GitHub-fejléccel;
2. a titok NEM kerül a parancssorba (argv) — környezeten megy;
3. nincs token / olvashatatlan fájl → néma no-op (a fetch a mai úton megy);
4. már beállított `GIT_CONFIG_COUNT` → nem írjuk felül (nem törünk el más
   git-konfigurációt).
"""

import base64
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "tools" / "round-pipeline.sh"

# A `providerToken` szabálynak nincs `valueGroup`-ja, ezért a szkenner
# `_placeholder` mentesítése (example/fake/test_only/...) RÁ NEM vonatkozik: a
# szolgáltatói előtag önmagában találat, akármi áll utána. Egy fixture-token
# egyetlen dokumentált kimenete a szkenner saját, sor végi markere.
TOKEN = "github_pat_FIXTURE_ONLY_not_a_real_secret"  # strumsight:allow-secret fixture-token, nem valódi hitelesítő


class AuthenticatedGitFetchTest(unittest.TestCase):
    def run_setup(self, home: Path, *, credentials: str | None, preset: dict | None = None) -> dict:
        if credentials is not None:
            (home / ".git-credentials").write_text(credentials, encoding="utf-8")
        shell = (
            "source <(sed -n '/^setup_authenticated_git_fetch() {/,/^}$/p' \"$PIPELINE_SCRIPT\")\n"
            "setup_authenticated_git_fetch\n"
            'printf "COUNT=%s\\n" "${GIT_CONFIG_COUNT:-}"\n'
            'printf "KEY=%s\\n" "${GIT_CONFIG_KEY_0:-}"\n'
            'printf "VALUE=%s\\n" "${GIT_CONFIG_VALUE_0:-}"\n'
        )
        environment = {
            "PATH": os.environ["PATH"],
            "HOME": str(home),
            "PIPELINE_SCRIPT": str(SCRIPT),
        }
        environment.update(preset or {})
        completed = subprocess.run(
            ["bash", "-c", shell], env=environment, text=True, capture_output=True, check=False
        )
        self.assertEqual(completed.returncode, 0, completed.stdout + completed.stderr)
        result = {}
        for line in completed.stdout.splitlines():
            key, _, value = line.partition("=")
            result[key] = value
        return result

    def test_a_stored_github_token_becomes_a_basic_auth_header(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            result = self.run_setup(home, credentials=f"https://wolfcasaba:{TOKEN}@github.com\n")
            self.assertEqual(result["COUNT"], "1")
            self.assertEqual(result["KEY"], "http.https://github.com/.extraheader")
            expected = base64.b64encode(f"x-access-token:{TOKEN}".encode()).decode()
            self.assertEqual(result["VALUE"], f"Authorization: Basic {expected}")

    def test_the_secret_never_reaches_the_command_line(self) -> None:
        """A titok KÖRNYEZETEN megy — a driver forrásában nincs argv-be írt token."""
        source = SCRIPT.read_text(encoding="utf-8")
        block = source.split("setup_authenticated_git_fetch() {", 1)[1].split("\n}\n", 1)[0]
        self.assertIn("export GIT_CONFIG_VALUE_0=", block)
        self.assertNotIn("--config", block)
        self.assertNotIn("http.extraHeader=", block)

    def test_no_credentials_file_is_a_silent_no_op(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            result = self.run_setup(Path(directory), credentials=None)
            self.assertEqual(result["COUNT"], "")
            self.assertEqual(result["VALUE"], "")

    def test_an_existing_git_config_env_is_not_overwritten(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            result = self.run_setup(
                home,
                credentials=f"https://wolfcasaba:{TOKEN}@github.com\n",
                preset={"GIT_CONFIG_COUNT": "3"},
            )
            self.assertEqual(result["COUNT"], "3")
            self.assertEqual(result["VALUE"], "")


if __name__ == "__main__":
    unittest.main()
