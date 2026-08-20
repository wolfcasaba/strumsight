"""E99-R19 (GOV-13) D3 — a `risk = "high"` indoklás-kötelezettség cellái.

A D3 a `tools/brief-lint.py` új `strict` leletét, az `S7`-et vezeti be:
ha egy brief `risk = "high"`-t deklarál, de sem az `allowed_paths` nem
érinti a `.ai/router.toml` `[security] high_risk_path_fragments`
listájának LEGALÁBB egy elemét, sem a brief szövege nem tartalmazza a
`**Kockázat = high, indoklás:**` kezdetű sort → strict lelet, `base`
szint változatlan. A D3 célja a 68 nyitott, igazolatlanul `high`
besorolású brief jövőbeli fegyelmezése — a meglévők fegyelmeztetlenül
maradnak a CI-kapuban, csak a jövő pre-flightja kapcsolja be a szűrőt.

A mérce cellái (brief §4):

  * `risk = "high"` + `**Kockázat = high, indoklás:**` sor → nincs lelet;
  * `risk = "high"` + allowed_path a router egyik `high_risk_path_fragments`
    elemével → nincs lelet;
  * `risk = "high"` + indoklás nincs + allowed_path nem kockázatos →
    S7 strict lelet, base-szinten tiszta;
  * `risk != "high"` (pl. `normal`) + indoklás nincs → S7 nem lő (a D3
    kizárólag a high besorolásra szigorít).

A falszifikációs cella: ha a `.ai/router.toml` hiányzik vagy üres
fragment-listát ad, a `_high_risk_fragments` `()`-tel tér vissza, és a
konkret útvonal-egyezés kikapcsol — ilyenkor CSAK az indoklás-sor
szünteti meg az S7-et (konzervatív, blokkolásmentes fallback).
"""

from __future__ import annotations

import importlib.util
import os
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
TOOLS = ROOT / "tools"


def _load_brief_lint():
    spec = importlib.util.spec_from_file_location("brief_lint", TOOLS / "brief-lint.py")
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


brief_lint = _load_brief_lint()


SAMPLE_ROUTER_TOML = textwrap.dedent(
    """\
    [security]
    high_risk_path_fragments = [
      "auth",
      "authorization",
      "camera",
      "credential",
      "crypto",
      "encryption",
      "migration",
      "payment",
      "privacy",
      "secret",
      "share",
      "upload",
      "vision",
    ]
    """
)


def _make_repo(directory: Path, *, router_text: str | None = SAMPLE_ROUTER_TOML) -> Path:
    """Minimális repo-váz a lint-teszthez: ai-router config + queue + test fixture.

    A `make_repo` az `test_pipeline_throughput.py`-ból származó mintát
    követi: a docs-vázon túl az S7 a `.ai/router.toml` jelenlétére
    épít — a hiányzó vagy üres config a D3 konzervatív fallback ágát
    tesztelhetővé teszi.
    """
    (directory / "docs" / "adr").mkdir(parents=True, exist_ok=True)
    (directory / "docs" / "execution").mkdir(parents=True, exist_ok=True)
    (directory / "test" / "features" / "example").mkdir(parents=True, exist_ok=True)
    (directory / "test" / "features" / "example" / "example_test.dart").write_text("", encoding="utf-8")
    if router_text is not None:
        (directory / ".ai").mkdir(parents=True, exist_ok=True)
        (directory / ".ai" / "router.toml").write_text(router_text, encoding="utf-8")
    return directory


def _write_brief(directory: Path, name: str, text: str) -> Path:
    path = directory / "docs" / "rounds" / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    return path


def _base_brief(*, risk: str, allowed_paths: list[str], gate_tests: list[str], body: str) -> str:
    """Egységes brief-váz: csak az `ai-router` blokk és a törzs változik."""
    paths = "\n".join(f'  "{path}",' for path in allowed_paths)
    gates = "[" + ", ".join(f'"{gt}"' for gt in gate_tests) + "]"
    return f"""# E99-R20 — Teszt-kör (D3 S7 cella)

{body}

```ai-router
schema_version = 1
risk = "{risk}"
allowed_paths = [
{paths}
]
gate_tests = {gates}
native_gate = false
```

## 9. Kör-jelzés

`done` csak review + CI + merge után.
"""


def _lint(text: str, *, repo: Path, name: str = "e99-r20-fixture.md"):
    path = _write_brief(repo, name, text)
    return brief_lint.lint_text(text, path=path, repo=repo)


def _codes(findings) -> set[str]:
    return {item["code"] for item in findings}


def _strict(findings) -> list:
    return [item for item in findings if item["level"] == "strict"]


class BriefRiskJustificationTest(unittest.TestCase):
    """A D3 / S7 mérce-mátrixa — strict lelet, base tiszta."""

    def test_justification_line_alone_drops_the_strict_finding(self) -> None:
        """1. cella: `risk = "high"` + `**Kockázat = high, indoklás:**` → nincs S7."""
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        repo = _make_repo(Path(directory.name))

        text = _base_brief(
            risk="high",
            allowed_paths=["docs/rounds/e99-r20-fixture.md"],
            gate_tests=["test/features/example"],
            body="> **Kockázat = high, indoklás:** a teszt-rövidzár elengedhetetlen.",
        )
        findings = _lint(text, repo=repo)
        self.assertNotIn(
            "S7",
            _codes(findings),
            f"indoklás-sor jelenlétében az S7 nem lőhet; findings={findings}",
        )

    def test_allowed_path_matching_a_fragment_drops_the_strict_finding(self) -> None:
        """2. cella: `risk = "high"` + allowed_path a router egyik fragmentjével → nincs S7.

        A router-konfig a mért igazság forrása: ha az `allowed_paths`
        bármely eleme tartalmazza a `high_risk_path_fragments` valamely
        szövegrészletét, a router CI mércéje a szigorúbb ágra vált, és
        az S7 ezt a tényt ismeri el — nincs szükség indoklás-sorra.
        """
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        repo = _make_repo(Path(directory.name))

        text = _base_brief(
            risk="high",
            allowed_paths=[
                "docs/rounds/e99-r20-fixture.md",
                # A `crypto` a router-konfig 6. eleme; a `credentials/`
                # útvonal a substring-egyezés miatt S7-mentesít.
                "lib/features/crypto/credentials_handler.dart",
            ],
            gate_tests=["test/features/example"],
            body="(nincs indoklás-sor — a router fragmentje önmagában elég)",
        )
        findings = _lint(text, repo=repo)
        self.assertNotIn(
            "S7",
            _codes(findings),
            f"router-fragment egyezésnél az S7 nem lőhet; findings={findings}",
        )

    def test_high_risk_with_no_justification_or_path_is_a_strict_finding(self) -> None:
        """3. cella: `risk = "high"` + indoklás nincs + útvonal nem kockázatos → S7 strict.

        A `base` szint VÁLTOZATLAN: a CI-kapu nem szigorodik, csak a
        jövő pre-flightja kapja meg a S7-et a §2 teendőjeként. A 68
        meglévő, nem-igazolt `risk = "high"` brief egyetlen éjszaka
        alatt sem vált pirosra — ez a D3 szándékos korlátja.
        """
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        repo = _make_repo(Path(directory.name))

        text = _base_brief(
            risk="high",
            allowed_paths=["docs/rounds/e99-r20-fixture.md"],
            gate_tests=["test/features/example"],
            body="(se indoklás, se kockázatos útvonal)",
        )
        findings = _lint(text, repo=repo)
        codes = _codes(findings)
        strict = _strict(findings)

        self.assertIn(
            "S7",
            codes,
            f"S7 strict lelet kell; findings={findings}",
        )
        self.assertIn(
            "S7",
            {item["code"] for item in strict},
            f"S7 csak strict szinten lőhet; strict={strict}",
        )
        self.assertNotIn(
            "S7",
            {item["code"] for item in findings if item["level"] == "base"},
            f"S7 a base szintet NEM szigoríthatja; findings={findings}",
        )

    def test_normal_risk_never_triggers_S7_even_without_justification(self) -> None:
        """4. cella: `risk != "high"` → S7 soha nem lő. Az S7 kizárólag a magas besorolásra szigorít."""
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        repo = _make_repo(Path(directory.name))

        text = _base_brief(
            risk="normal",
            allowed_paths=["docs/rounds/e99-r20-fixture.md"],
            gate_tests=["test/features/example"],
            body="(se indoklás, se kockázatos útvonal — de a risk 'normal')",
        )
        findings = _lint(text, repo=repo)
        self.assertNotIn(
            "S7",
            _codes(findings),
            f"S7 'normal' riskre nem lőhet; findings={findings}",
        )


class BriefRiskJustificationFalsificationTest(unittest.TestCase):
    """A D3 falszifikációs cellái — a router-config konzervatív fallbackje."""

    def test_missing_router_config_forces_the_justification_path(self) -> None:
        """Ha a `.ai/router.toml` hiányzik, a fragment-lista üres, és CSAK az
        indoklás-sor szünteti meg az S7-et — a D3 konzervatív, nem-blokkoló
        fallbackje. A falszifikáció: aki a fragment-listát leveszi a
        konfigból, nem kap „automatikus zöldet", csak a kézi indoklás
        marad életben.
        """
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        repo = _make_repo(Path(directory.name), router_text=None)

        text_no_justification = _base_brief(
            risk="high",
            allowed_paths=["docs/rounds/e99-r20-fixture.md"],
            gate_tests=["test/features/example"],
            body="(nincs indoklás — router-config hiányzik)",
        )
        findings = _lint(text_no_justification, repo=repo)
        self.assertIn(
            "S7",
            _codes(findings),
            f"hiányzó router.toml mellett a S7 az indoklás-sorra épül; findings={findings}",
        )

        text_with_justification = _base_brief(
            risk="high",
            allowed_paths=["docs/rounds/e99-r20-fixture.md"],
            gate_tests=["test/features/example"],
            body="> **Kockázat = high, indoklás:** kézzel igazolva, mert a router-config nem elérhető.",
        )
        findings = _lint(text_with_justification, repo=repo)
        self.assertNotIn(
            "S7",
            _codes(findings),
            f"indoklás-sor a fallbackben is leveszi az S7-et; findings={findings}",
        )

    def test_empty_router_fragment_list_falls_back_to_justification(self) -> None:
        """Ha a fragment-lista üres (`high_risk_path_fragments = []`), nincs
        substring-egyezés, és CSAK az indoklás-sor szünteti meg az S7-et.
        """
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        repo = _make_repo(Path(directory.name), router_text="[security]\nhigh_risk_path_fragments = []\n")

        text_no_justification = _base_brief(
            risk="high",
            allowed_paths=[
                "docs/rounds/e99-r20-fixture.md",
                "lib/features/crypto/auth_handler.dart",
            ],
            gate_tests=["test/features/example"],
            body="(fragment-lista üres — útvonal-egyezés nem segít)",
        )
        findings = _lint(text_no_justification, repo=repo)
        self.assertIn(
            "S7",
            _codes(findings),
            f"üres fragment-listánál S7 marad; findings={findings}",
        )

    def test_justification_marker_must_match_the_exact_prefix(self) -> None:
        """Az S7 a `**Kockázat = high, indoklás:**` SZÓ SZERINTI prefixét várja (anchor-olt).

        A marker `^\\*\\*Kockázat = high, indoklás:\\*\\*` — a `**Kockázat =
        high, indoklás:`-nál rövidebb, toldalékolt vagy eltérő prefixű sor
        NEM számít indoklásnak. Ez a stabilitás: a jövőbeli brief-szerkesztő
        NEM tudja „megkerülni" a S7-et egy hasonló, de nem pontos sorral.
        """
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        repo = _make_repo(Path(directory.name))

        body = (
            "> Kockázat = high, indoklás: hiányzó `**` prefix — NEM számít indoklásnak.\n"
            "> **Kockázat = high** — indoklás nélkül (nincs `:`, a prefix szövege más).\n"
        )
        text = _base_brief(
            risk="high",
            allowed_paths=["docs/rounds/e99-r20-fixture.md"],
            gate_tests=["test/features/example"],
            body=body,
        )
        findings = _lint(text, repo=repo)
        self.assertIn(
            "S7",
            _codes(findings),
            f"a két rossz prefix NEM elégíti ki a markert; findings={findings}",
        )

    def test_cli_strict_level_reports_S7_while_base_level_stays_silent(self) -> None:
        """A CLI-szintű ellenőrzés: `strict` szinten megjelenik az S7,
        `base` szinten nem — ez a D3 legfontosabb ígérete a CI-kapu felé.
        """
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        repo = _make_repo(Path(directory.name))
        text = _base_brief(
            risk="high",
            allowed_paths=["docs/rounds/e99-r20-fixture.md"],
            gate_tests=["test/features/example"],
            body="(se indoklás, se kockázatos útvonal)",
        )
        path = _write_brief(repo, "e99-r20-cli.md", text)

        base_run = subprocess.run(
            [
                sys.executable,
                str(TOOLS / "brief-lint.py"),
                "--brief",
                str(path),
                "--level",
                "base",
                "--repo",
                str(repo),
            ],
            capture_output=True,
            text=True,
        )
        strict_run = subprocess.run(
            [
                sys.executable,
                str(TOOLS / "brief-lint.py"),
                "--brief",
                str(path),
                "--level",
                "strict",
                "--repo",
                str(repo),
            ],
            capture_output=True,
            text=True,
        )
        self.assertNotEqual(base_run.returncode, 3, f"base usage-hiba: {base_run.stderr}")
        self.assertNotEqual(strict_run.returncode, 3, f"strict usage-hiba: {strict_run.stderr}")
        # A base szinten B2/B4 tüzel a csupasz fixture-on (returncode 2),
        # de a D3 lényege CSAK az, hogy az S7 a base kimenetben NEM jelenik
        # meg — a CI-kapu nem szigorodhat, csak a pre-flight kapja meg S7-et.

        self.assertNotIn(
            "S7",
            base_run.stdout,
            f"base szinten S7 NEM jelenhet meg; stdout={base_run.stdout!r}",
        )
        self.assertIn(
            "S7",
            strict_run.stdout,
            f"strict szinten S7 megjelenik; stdout={strict_run.stdout!r}",
        )


if __name__ == "__main__":
    unittest.main()