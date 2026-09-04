"""Az áteresztő-képesség programjának őrei (ADR 0171).

A gyorsítás akkor ér valamit, ha a mérce közben NEM lazul. Ez a modul ezért két
dolgot mér egyszerre:

1. a hat lever mechanikáját (CI-terv, brief-lint, slotok, azonnali
   lánc-folytatás, időmérleg, gate-zár);
2. a MÉRCE-ŐRÖKET — azokat az állításokat, amelyek pirosra váltanak, ha valaki
   később a gyorsítás ürügyén elvenne a mérce-láncból (pl. kihagyna egy lépést
   a `full-gate.yml`-ből, vagy egy natív útvonalat kivenne az APK-ág alól).

A 2. csoport nélkül ez a program pontosan az a hibaosztály lenne, ami ellen a
repó egyébként véd: a mércét nem gyengítheti az, akit mér (docs/LESSONS.md).
"""

import json
import os
import re
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

import importlib.util


def _load(module_name: str, relative: str):
    """A kötőjeles fájlnevű CLI-k betöltése modulként (nem importálható névvel)."""
    spec = importlib.util.spec_from_file_location(module_name, ROOT / relative)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


ci_plan = _load("round_ci_plan", "tools/round-ci-plan.py")
brief_lint = _load("brief_lint", "tools/brief-lint.py")
round_slots = _load("round_slots", "tools/round-slots.py")
round_metrics = _load("round_metrics", "tools/round-metrics.py")

PIPELINE = ROOT / "tools" / "round-pipeline.sh"
GATE = ROOT / "tools" / "round-gate.sh"

VALID_BRIEF = """# E09-R01 — Példa kör

<!-- A minta-brief a MINDENKORI elvárást modellezi: az S8 (ADR 0312) óta ide
     tartozik a visszakeresett előzmény is — a lecke/ADR azonosítójával, vagy
     annak kimondásával, hogy nincs ilyen. -->
**Visszakeresett előzmények:** `lessons/L305` (a célzott gate önmagában nem
elég), `adr/0312` (visszakeresési kötelezettség).

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "lib/features/example/example.dart",
  "test/features/example/example_test.dart",
  "docs/rounds/e09-r01-example.md",
]
gate_tests = ["test/features/example"]
native_gate = false
```

## 1. Cél

Példa. A gate artefaktuma: `tools/round-gate.sh test/features/example`.

## 8. Acceptance

- A reducer üres bemenetre `idle` állapotot ad. **Pirosra váltja:** az a
  hibás implementáció, amely a legutóbbi állapotot tartja meg.

**STOP:** scope-ütközésnél dokumentált brief-revízió.

## 9. Kör-jelzés

`done` csak review + CI + merge után.
"""


def write_brief(directory: Path, name: str, text: str) -> Path:
    path = directory / "docs" / "rounds" / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text, encoding="utf-8")
    return path


def make_repo(directory: Path) -> Path:
    """Minimális repó-váz a lint/slot tesztekhez."""
    (directory / "docs" / "adr").mkdir(parents=True, exist_ok=True)
    (directory / "docs" / "execution").mkdir(parents=True, exist_ok=True)
    (directory / "test" / "features" / "example").mkdir(parents=True, exist_ok=True)
    (directory / "test" / "features" / "example" / "example_test.dart").write_text("", encoding="utf-8")
    return directory


class CiPlanTest(unittest.TestCase):
    """3. lever — melyik CI a kapu."""

    ROUTER_PATHS = ("docs/rounds/**", "tools/tests/**", ".ai/**")

    def plan(self, **kwargs):
        base = {
            "native_gate": False,
            "changed_files": ("lib/features/a.dart",),
            "router_ci_paths": self.ROUTER_PATHS,
        }
        base.update(kwargs)
        return ci_plan.plan(**base)

    def test_pure_dart_round_skips_the_android_build(self) -> None:
        result = self.plan(changed_files=("lib/a.dart", "test/a_test.dart", "docs/rounds/e09-r01.md"))
        self.assertEqual(result["dispatch"], ["full-gate.yml"])
        self.assertFalse(result["apk_required"])

    def test_native_gate_forces_the_apk_lane(self) -> None:
        self.assertEqual(self.plan(native_gate=True)["dispatch"], ["build-apk.yml"])

    def test_native_paths_force_the_apk_lane(self) -> None:
        for path in (
            "android/app/build.gradle",
            "ios/Runner/Info.plist",
            "pubspec.yaml",
            "pubspec.lock",
            "assets/models/hand.tflite",
            ".github/actions/flutter-gates/action.yml",
        ):
            with self.subTest(path=path):
                result = self.plan(changed_files=("lib/a.dart", path))
                self.assertEqual(result["dispatch"], ["build-apk.yml"], result["reasons"])

    def test_unknown_diff_is_fail_closed(self) -> None:
        """Bizonyítatlan eset nem lehet olcsóbb, mint a bizonyított."""
        result = self.plan(changed_files=())
        self.assertEqual(result["dispatch"], ["build-apk.yml"])
        self.assertIn("fail-closed", " ".join(result["reasons"]))

    def test_router_ci_expectation_comes_from_the_real_workflow(self) -> None:
        text = (ROOT / ".github" / "workflows" / "router-ci.yml").read_text(encoding="utf-8")
        paths = ci_plan.router_ci_trigger_paths(text)
        self.assertTrue(paths, "a router-ci.yml paths: blokkja nem elemezhető")

        # LEFEDETTSÉGET mérünk, nem minta-SZÖVEGET (2026-08-19). A korábbi
        # assertIn("tools/tests/**", paths) a felsorolás ALAKJÁHOZ kötötte a
        # tesztet: amikor a fájlonkénti lista családi globra cserélődött
        # (tools/**), pirosra váltott, holott a lefedettség NŐTT (127 -> 143
        # fájl, docs/LESSONS.md L322). A minta szövege nem viselkedés — a
        # viselkedés az, hogy egy ilyen fájl elindítja-e a Router CI-t.
        for covered in ("tools/tests/test_pipeline_throughput.py", "docs/rounds/e09-r01.md"):
            with self.subTest(path=covered):
                self.assertTrue(
                    ci_plan.plan(
                        native_gate=False,
                        changed_files=(covered,),
                        router_ci_paths=paths,
                    )["router_ci_expected"],
                    f"{covered} nem indítja el a Router CI-t",
                )
        self.assertFalse(
            ci_plan.plan(
                native_gate=False,
                changed_files=("lib/a.dart",),
                router_ci_paths=paths,
            )["router_ci_expected"]
        )

    def test_cli_rejects_an_unparseable_brief(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "e09-r01-broken.md"
            path.write_text("# nincs blokk", encoding="utf-8")
            result = subprocess.run(
                [sys.executable, str(ROOT / "tools" / "round-ci-plan.py"), "--brief", str(path)],
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 2, result.stdout)


class GateChainParityTest(unittest.TestCase):
    """MÉRCE-ŐR: a gyorsított sáv ugyanazt méri, mint az APK-s."""

    def setUp(self) -> None:
        self.apk = (ROOT / ".github" / "workflows" / "build-apk.yml").read_text(encoding="utf-8")
        self.full = (ROOT / ".github" / "workflows" / "full-gate.yml").read_text(encoding="utf-8")

    def test_both_lanes_run_the_same_gate_composite(self) -> None:
        for text, name in ((self.apk, "build-apk.yml"), (self.full, "full-gate.yml")):
            with self.subTest(workflow=name):
                self.assertIn("./.github/actions/flutter-gates", text)

    def test_full_gate_keeps_every_non_apk_gate_of_the_apk_lane(self) -> None:
        """Ha valaki a full-gate-ből kivesz egy mérési lépést, ez pirosra vált."""
        required = (
            "dart run tool/ci/check_song_schema.dart",
            "dart run tool/ci/check_song_fixture_licenses.dart",
            "flutter test --coverage",
        )
        for step in required:
            with self.subTest(step=step):
                self.assertIn(step, self.apk, "az APK-sáv referenciája megváltozott")
                self.assertIn(step, self.full, "a gyorsított sáv elvesztett egy mérési lépést")

    def test_the_gate_composite_still_contains_the_full_test_and_property_gate(self) -> None:
        action = (ROOT / ".github" / "actions" / "flutter-gates" / "action.yml").read_text(encoding="utf-8")
        self.assertIn("flutter test", action)
        self.assertIn("test/property", action)
        self.assertIn("PROPERTY_SEED", action)

    def test_every_native_directory_of_the_repo_is_covered_by_the_apk_rule(self) -> None:
        """Új natív könyvtár nem csúszhat némán az olcsó sávba."""
        native_like = {"android", "ios", "macos", "linux", "windows", "web", "assets"}
        for entry in ROOT.iterdir():
            if entry.is_dir() and entry.name in native_like:
                with self.subTest(directory=entry.name):
                    self.assertIsNotNone(
                        ci_plan.matches_any(f"{entry.name}/x", ci_plan.NATIVE_PATH_PATTERNS),
                        f"a(z) {entry.name}/ nincs lefedve — natív diff kerülné az APK-t",
                    )


class BriefLintTest(unittest.TestCase):
    """4. lever — a javító körök okait a briefben fogjuk meg."""

    def lint(self, text: str, *, name: str = "e09-r01-example.md", repo: Path | None = None):
        if repo is None:
            self.directory = tempfile.TemporaryDirectory()
            self.addCleanup(self.directory.cleanup)
            repo = make_repo(Path(self.directory.name))
        path = write_brief(repo, name, text)
        return brief_lint.lint_text(text, path=path, repo=repo), repo

    def codes(self, findings) -> set:
        return {item["code"] for item in findings}

    def test_a_well_formed_brief_has_no_findings(self) -> None:
        findings, _ = self.lint(VALID_BRIEF)
        self.assertEqual(self.codes(findings), set(), findings)

    def test_missing_gate_artifact_reference_is_a_base_finding(self) -> None:
        findings, _ = self.lint(VALID_BRIEF.replace("`tools/round-gate.sh test/features/example`", "a szokásos gate"))
        self.assertIn("B4", self.codes(findings))

    def test_output_truncating_gate_shape_is_a_base_finding(self) -> None:
        text = VALID_BRIEF.replace(
            "## 9. Kör-jelzés",
            "```bash\ntools/round-gate.sh test/features/example | tail -5\n```\n\n## 9. Kör-jelzés",
        )
        findings, _ = self.lint(text)
        self.assertIn("B5", self.codes(findings))

    def test_analyze_and_test_chain_is_a_base_finding(self) -> None:
        text = VALID_BRIEF.replace(
            "## 9. Kör-jelzés",
            "```bash\nflutter analyze lib/ && flutter test test/\n```\n\n## 9. Kör-jelzés",
        )
        findings, _ = self.lint(text)
        self.assertIn("B5", self.codes(findings))

    def test_brief_must_allow_itself(self) -> None:
        findings, _ = self.lint(VALID_BRIEF.replace('  "docs/rounds/e09-r01-example.md",\n', ""))
        self.assertIn("B2", self.codes(findings))

    def test_heading_and_filename_round_id_must_match(self) -> None:
        findings, _ = self.lint(VALID_BRIEF.replace("# E09-R01 —", "# E09-R02 —"))
        self.assertIn("B6", self.codes(findings))

    def test_gate_test_nobody_creates_is_a_base_finding(self) -> None:
        findings, _ = self.lint(VALID_BRIEF.replace('gate_tests = ["test/features/example"]', 'gate_tests = ["test/features/ghost"]'))
        self.assertIn("B3", self.codes(findings))

    def test_gate_test_created_by_an_earlier_queue_round_is_accepted(self) -> None:
        """Előre megírt epicnél a könyvtárat egy KORÁBBI kör hozza létre."""
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        repo = make_repo(Path(directory.name))
        earlier = VALID_BRIEF.replace("E09-R01", "E09-R00").replace(
            '  "test/features/example/example_test.dart",',
            '  "test/features/ghost/ghost_test.dart",',
        )
        write_brief(repo, "e09-r00-earlier.md", earlier.replace("e09-r01-example.md", "e09-r00-earlier.md"))
        (repo / "docs" / "execution" / "pipeline-queue.tsv").write_text(
            "E09-R00\tdocs/rounds/e09-r00-earlier.md\tcodex\tnincs\tpending\n"
            "E09-R01\tdocs/rounds/e09-r01-example.md\tcodex\tnincs\tpending\n",
            encoding="utf-8",
        )
        findings, _ = self.lint(
            VALID_BRIEF.replace('gate_tests = ["test/features/example"]', 'gate_tests = ["test/features/ghost"]'),
            repo=repo,
        )
        self.assertNotIn("B3", self.codes(findings))

    def test_new_allowed_file_colliding_with_an_existing_type_is_a_strict_finding(self) -> None:
        """MÉRT eset (E06-R10/H3, docs/LESSONS.md): a brief ÚJ fájlt írt elő
        egy olyan típusnévvel, ami MÁR élt egy nem engedélyezett fájlban —
        a `public.dart` barrel ambiguous exportot dobott volna. STRICT, mert
        a bevezetéskor 3 másik előre megírt Epic-6 brief (R11/R12/R17) is
        ugyanezt hordozta — nem minden meglévő brief teljesíti, ezért nem
        lehet base-szintű CI-kapu."""
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        repo = make_repo(Path(directory.name))
        feature = repo / "lib" / "features" / "example"
        feature.mkdir(parents=True, exist_ok=True)
        (feature / "analysis_event.dart").write_text(
            "final class OnsetEvent {\n  const OnsetEvent();\n}\n", encoding="utf-8"
        )
        text = VALID_BRIEF.replace(
            '  "lib/features/example/example.dart",\n',
            '  "lib/features/example/example.dart",\n  "lib/features/example/onset_event.dart",\n',
        )
        findings, _ = self.lint(text, repo=repo)
        self.assertIn("S5", self.codes(findings))

    def test_new_allowed_file_with_no_existing_collision_is_clean(self) -> None:
        """Ugyanabban a feature-gyökérben lévő, de nem ütköző fájlok nem leletek."""
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        repo = make_repo(Path(directory.name))
        feature = repo / "lib" / "features" / "example"
        feature.mkdir(parents=True, exist_ok=True)
        (feature / "unrelated.dart").write_text(
            "final class Unrelated {\n  const Unrelated();\n}\n", encoding="utf-8"
        )
        text = VALID_BRIEF.replace(
            '  "lib/features/example/example.dart",\n',
            '  "lib/features/example/example.dart",\n  "lib/features/example/onset_event.dart",\n',
        )
        findings, _ = self.lint(text, repo=repo)
        self.assertNotIn("S5", self.codes(findings))

    def test_editing_an_existing_file_is_never_a_collision(self) -> None:
        """A path LÉTEZIK ága sosem lelet — a bővítés a normál eset."""
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        repo = make_repo(Path(directory.name))
        feature = repo / "lib" / "features" / "example"
        feature.mkdir(parents=True, exist_ok=True)
        (feature / "example.dart").write_text(
            "final class Example {\n  const Example();\n}\n", encoding="utf-8"
        )
        findings, _ = self.lint(VALID_BRIEF, repo=repo)
        self.assertNotIn("S5", self.codes(findings))

    def test_strict_level_asks_for_falsification_and_threshold_matrix(self) -> None:
        text = VALID_BRIEF.replace(
            "- A reducer üres bemenetre `idle` állapotot ad. **Pirosra váltja:** az a\n  hibás implementáció, amely a legutóbbi állapotot tartja meg.",
            "- A reducer üres bemenetre `idle` állapotot ad, ha a timeout küszöb 500 ms.",
        )
        findings, _ = self.lint(text)
        self.assertIn("S2", self.codes(findings))
        self.assertIn("S3", self.codes(findings))

    def test_every_open_round_brief_passes_the_base_gate(self) -> None:
        """Ez UGYANAZ az állítás, amit a Router CI kapuja mér."""
        rows = list(brief_lint.queue_rows(ROOT))
        self.assertTrue(rows, "a sor-fájl üres vagy nem parse-olható — ez VALÓDI hiba")
        paths = [ROOT / brief for _round, brief, status in rows if status != "done"]
        if not paths:
            # Ugyanaz a mért eset, mint a
            # test_pipeline_integration.py::test_open_rounds_follow_the_measured_engine_rule
            # skipje (2026-08-14, Epic 6 zárás): a kiürült sor epic-határ, nem
            # defekt. A brief-kapu minden NYITOTT kört ugyanúgy mér — nulla
            # nyitott körön nincs mit mérni, és a piros main a láncot állítja
            # meg, nem a hibát javítja.
            self.skipTest("a sor kiürült (minden kör `done`) — epic-határ, emberi döntésre vár")
        report, worst = brief_lint.lint_paths(paths, repo=ROOT, level="base")
        self.assertEqual(worst, 0, json.dumps(report, ensure_ascii=False, indent=2))

    def test_e06_r10_brief_is_clean_after_the_h3_self_heal(self) -> None:
        """MÉRT regresszió (E06-R10/H3, docs/LESSONS.md): a self-heal ELŐTT ez
        a brief allowed_paths-a két, a nem engedélyezett
        domain/analysis_event.dart-ban már élő típusnévvel (OnsetEvent,
        StrumEvent) ütköző ÚJ fájlt írt elő (S5). A revideált brief egyetlen
        szinten sem adhat leletet — enélkül UGYANAZ a halt térne vissza."""
        path = ROOT / "docs" / "rounds" / "e06-r10-event-evidence-onset-strum-timeline.md"
        findings = brief_lint.lint_text(path.read_text(encoding="utf-8"), path=path, repo=ROOT)
        self.assertEqual(findings, [], findings)


class SlotPlanningTest(unittest.TestCase):
    """1. lever — párhuzam CSAK bizonyítottan független körökre."""

    def test_disjoint_and_overlapping_path_sets(self) -> None:
        left = frozenset({"lib/a/x.dart", "test/a/x_test.dart"})
        right = frozenset({"lib/b/y.dart"})
        self.assertEqual(round_slots.paths_conflict(left, right), [])
        self.assertTrue(round_slots.paths_conflict(left, frozenset({"lib/a"})))
        self.assertTrue(round_slots.paths_conflict(left, frozenset({"lib/a/x.dart"})))

    def test_shared_ritual_files_do_not_count_as_conflict(self) -> None:
        """Minden kör hozzájuk ér — ezeket a merge-zár sorosítja, nem a terv."""
        paths = round_slots.effective_paths(("HANDOFF.md", "docs/LESSONS.md", "lib/a.dart"))
        self.assertEqual(paths, frozenset({"lib/a.dart"}))

    def test_real_epic_four_rounds_are_correctly_rejected(self) -> None:
        """Mért helyzet: az Epic 4 körei ugyanazt a public.dart-ot érintik."""
        left = round_slots.load_paths(ROOT, "docs/rounds/e04-r15-streaming-transport.md")
        right = round_slots.load_paths(ROOT, "docs/rounds/e04-r16-orchestration-state-machine.md")
        self.assertTrue(round_slots.paths_conflict(left, right))

    def test_prerequisites_block_a_round_whose_epic_predecessor_is_open(self) -> None:
        rows = [
            ("E09-R01", "docs/rounds/e09-r01.md", "codex", "nincs", "pending"),
            ("E09-R02", "docs/rounds/e09-r02.md", "codex", "nincs", "pending"),
        ]
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            blocking = round_slots.unmet_prerequisites(repo, "E09-R02", "docs/rounds/e09-r02.md", rows)
            self.assertEqual(blocking, ["E09-R01"])

    def test_declared_prerequisite_of_another_epic_is_honoured(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            (repo / "docs" / "rounds").mkdir(parents=True)
            (repo / "docs" / "rounds" / "e10-r01.md").write_text(
                "- **Előfeltétel:** Epic 9 (**E09-R02**) lezárva\n", encoding="utf-8"
            )
            rows = [
                ("E09-R02", "docs/rounds/e09-r02.md", "codex", "nincs", "pending"),
                ("E10-R01", "docs/rounds/e10-r01.md", "codex", "nincs", "pending"),
            ]
            blocking = round_slots.unmet_prerequisites(repo, "E10-R01", "docs/rounds/e10-r01.md", rows)
            self.assertIn("E09-R02", blocking)

    def test_adr_reservation_is_atomic_and_above_the_highest_on_disk(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repo = make_repo(Path(directory))
            (repo / "docs" / "adr" / "0171-example.md").write_text("", encoding="utf-8")
            inflight = repo / ".pipeline" / "inflight"
            first = round_slots.reserve_adr(repo, inflight, "E09-R01")
            second = round_slots.reserve_adr(repo, inflight, "E09-R02")
            self.assertEqual(first, 172)
            self.assertEqual(second, 173, "két párhuzamos kör ugyanazt a számot kapta")

    def test_adr_reservation_sees_numbers_taken_on_other_branches(self) -> None:
        """MÉRT rés (ADR 0173): a futó kör a saját ágán már foglalt egy számot."""
        with tempfile.TemporaryDirectory() as directory:
            repo = make_repo(Path(directory))
            subprocess.run(["git", "init", "-q"], cwd=repo, check=True)
            subprocess.run(["git", "config", "user.email", "t@e.hu"], cwd=repo, check=True)
            subprocess.run(["git", "config", "user.name", "T"], cwd=repo, check=True)
            (repo / "docs" / "adr" / "0171-example.md").write_text("", encoding="utf-8")
            subprocess.run(["git", "add", "-A"], cwd=repo, check=True)
            subprocess.run(["git", "commit", "-q", "-m", "main"], cwd=repo, check=True)
            subprocess.run(["git", "checkout", "-q", "-b", "round"], cwd=repo, check=True)
            (repo / "docs" / "adr" / "0172-inflight.md").write_text("", encoding="utf-8")
            subprocess.run(["git", "add", "-A"], cwd=repo, check=True)
            subprocess.run(["git", "commit", "-q", "-m", "round adr"], cwd=repo, check=True)
            subprocess.run(["git", "checkout", "-q", "-"], cwd=repo, check=True)
            (repo / "docs" / "adr" / "0172-inflight.md").unlink(missing_ok=True)

            self.assertIn(172, round_slots.branch_adr_numbers(repo))
            self.assertEqual(
                round_slots.reserve_adr(repo, repo / ".pipeline" / "inflight", "E09-R01"),
                173,
                "a foglaló egy másik ágon már kiosztott számot adott ki újra",
            )

    def test_inflight_registry_round_trip(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repo = make_repo(Path(directory))
            inflight = repo / ".pipeline" / "inflight"
            script = str(ROOT / "tools" / "round-slots.py")
            common = [sys.executable, script, "--repo", str(repo), "--inflight", str(inflight)]
            subprocess.run(
                common + ["inflight-add", "--round", "E09-R01", "--brief", "docs/rounds/e09-r01.md"],
                check=True,
                capture_output=True,
            )
            listed = json.loads(subprocess.run(common + ["inflight-list"], capture_output=True, text=True, check=True).stdout)
            self.assertEqual([entry["round"] for entry in listed], ["E09-R01"])
            subprocess.run(common + ["inflight-remove", "--round", "E09-R01"], check=True, capture_output=True)
            listed = json.loads(subprocess.run(common + ["inflight-list"], capture_output=True, text=True, check=True).stdout)
            self.assertEqual(listed, [])

    def test_inflight_commands_reject_a_malformed_round_id(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repo = make_repo(Path(directory))
            result = subprocess.run(
                [
                    sys.executable,
                    str(ROOT / "tools" / "round-slots.py"),
                    "--repo",
                    str(repo),
                    "--inflight",
                    str(repo / "inflight"),
                    "inflight-add",
                    "--round",
                    "../escape",
                    "--brief",
                    "x.md",
                ],
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 2)


class DriverThroughputTest(unittest.TestCase):
    """1–2. lever a driverben — az alapértelmezés a MAI viselkedés."""

    def run_hook(self, *arguments, env=None):
        environment = dict(os.environ)
        environment.setdefault("PIPELINE_NO_LAUNCH", "1")
        if env:
            environment.update(env)
        return subprocess.run(
            ["bash", str(PIPELINE), *arguments],
            capture_output=True,
            text=True,
            env=environment,
            cwd=str(ROOT),
        )

    def test_default_slot_count_is_one(self) -> None:
        result = self.run_hook("--effective-slots", "1")
        self.assertEqual(result.stdout.strip(), "1", result.stderr)

    def test_slot_one_keeps_the_legacy_lock_file(self) -> None:
        """Egy régi, még futó driver zárával is ütköznie kell."""
        with tempfile.TemporaryDirectory() as directory:
            result = self.run_hook("--slot-lock-path", "1", env={"PIPELINE_STATE_DIR": directory})
            self.assertEqual(result.stdout.strip(), str(Path(directory) / "lock"))

    def test_extra_slots_are_clamped_by_available_memory(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            result = self.run_hook(
                "--effective-slots",
                "4",
                env={"PIPELINE_MIN_FREE_GB_PER_SLOT": "100000", "PIPELINE_STATE_DIR": directory},
            )
            self.assertEqual(result.stdout.strip().splitlines()[-1], "1")
            self.assertIn("SLOT-KORLÁT", result.stderr)

    def test_self_chain_starts_the_next_firing_after_the_parent_exits(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            marker = Path(directory) / "marker"
            result = self.run_hook(
                "--spawn-next-firing",
                env={
                    "PIPELINE_STATE_DIR": directory,
                    "PIPELINE_NO_LAUNCH": "0",
                    "PIPELINE_SELF_CHAIN_CMD": f"touch {marker}",
                },
            )
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("azonnali lánc-folytatás", result.stderr)
            deadline = time.time() + 20
            while time.time() < deadline and not marker.exists():
                time.sleep(0.5)
            self.assertTrue(marker.exists(), "a lánc-folytatás nem indult el a szülő kilépése után")

    def test_self_chain_can_be_switched_off(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            marker = Path(directory) / "marker"
            result = self.run_hook(
                "--spawn-next-firing",
                env={
                    "PIPELINE_STATE_DIR": directory,
                    "PIPELINE_NO_LAUNCH": "0",
                    "PIPELINE_SELF_CHAIN": "0",
                    "PIPELINE_SELF_CHAIN_CMD": f"touch {marker}",
                },
            )
            time.sleep(2)
            self.assertFalse(marker.exists())
            self.assertIn("PIPELINE_SELF_CHAIN=0", result.stderr)

    def test_self_chain_never_launches_in_test_mode(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            marker = Path(directory) / "marker"
            result = self.run_hook(
                "--spawn-next-firing",
                env={"PIPELINE_STATE_DIR": directory, "PIPELINE_SELF_CHAIN_CMD": f"touch {marker}"},
            )
            time.sleep(1)
            self.assertFalse(marker.exists())
            self.assertIn("PIPELINE_NO_LAUNCH=1", result.stderr)

    def test_brief_lint_hook_writes_a_report_for_the_preflight(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            result = self.run_hook(
                "--brief-lint",
                "E04-R15",
                "docs/rounds/e04-r15-streaming-transport.md",
                env={"PIPELINE_STATE_DIR": directory},
            )
            report = result.stdout.strip()
            self.assertTrue(report.endswith("brief-lint-E04-R15.md"), result.stdout + result.stderr)
            self.assertTrue(Path(report).is_file())

    def test_the_orchestrator_prompt_declares_every_placeholder_the_driver_fills(self) -> None:
        template = (ROOT / "docs" / "execution" / "pipeline-orchestrator-prompt.md").read_text(encoding="utf-8")
        driver = PIPELINE.read_text(encoding="utf-8")
        for placeholder in re.findall(r"\{\{[A-Z_]+\}\}", template):
            with self.subTest(placeholder=placeholder):
                self.assertIn(placeholder, driver, "a sablon olyan helyőrzőt kér, amit a driver nem tölt ki")


class GateLockTest(unittest.TestCase):
    """A gate-zár sorosít, de semmit nem hagy ki."""

    def gate_sandbox(self, directory: Path) -> dict:
        (directory / "pubspec.yaml").write_text("name: sandbox\n", encoding="utf-8")
        (directory / "test").mkdir(exist_ok=True)
        environment = dict(os.environ)
        environment.update(
            {
                "FLUTTER_BIN": "/bin/true",
                "DART_BIN": "/bin/true",
                "ROUND_GATE_SLEEP_SECONDS": "0",
            }
        )
        return environment

    def test_gate_passes_when_the_lock_is_free(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            environment = self.gate_sandbox(path)
            environment["ROUND_GATE_LOCK"] = str(path / "gate.lock")
            result = subprocess.run(
                ["bash", str(GATE), "test/example"],
                cwd=str(path),
                env=environment,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_a_second_gate_waits_and_reports_an_environment_failure(self) -> None:
        """Két gate SOHA nem futhat egyszerre ezen a boxon (OOM, L05)."""
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            environment = self.gate_sandbox(path)
            lock = path / "gate.lock"
            lock.touch()
            environment["ROUND_GATE_LOCK"] = str(lock)
            environment["ROUND_GATE_LOCK_WAIT"] = "1"
            holder = subprocess.Popen(["flock", str(lock), "sleep", "10"])
            try:
                time.sleep(0.5)
                result_json = path / "result.json"
                result = subprocess.run(
                    ["bash", str(GATE), "--result-json", str(result_json), "test/example"],
                    cwd=str(path),
                    env=environment,
                    capture_output=True,
                    text=True,
                )
                self.assertEqual(result.returncode, 20, result.stdout + result.stderr)
                payload = json.loads(result_json.read_text(encoding="utf-8"))
                self.assertEqual(payload["failed_step"], "preflight.lock")
            finally:
                holder.kill()
                holder.wait()

    def test_lock_can_be_disabled_for_measurement(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            environment = self.gate_sandbox(path)
            environment["ROUND_GATE_LOCK"] = "none"
            result = subprocess.run(
                ["bash", str(GATE), "test/example"],
                cwd=str(path),
                env=environment,
                capture_output=True,
                text=True,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_gate_still_runs_every_measured_step(self) -> None:
        """MÉRCE-ŐR: a zár bevezetése nem vehetett el lépést a gate-ből."""
        text = GATE.read_text(encoding="utf-8")
        for step in ('run_step "format"', 'run_step "analyze"', 'run_step "architecture"', 'run_step "secrets"', 'run_step "l10n"'):
            with self.subTest(step=step):
                self.assertIn(step, text)
        self.assertIn('run_step "test $test_path"', text)


class RoundMetricsTest(unittest.TestCase):
    """5. lever — a kör-granularitás döntése MÉRT adaton áll."""

    LOG = """2026-08-05T10:00:00+00:00  orchestrátor-session indul (E09-R01), időkorlát 14400s → /x.log
2026-08-05T10:05:00+00:00  zár foglalt — már fut egy kör, ez a firing kimarad
2026-08-05T11:00:00+00:00  E09-R01 MERGE-ELVE — kész
2026-08-05T11:05:00+00:00  HIBA: piszkos munkafa — a lánc nem indul ismeretlen lokális változás fölé
2026-08-05T11:30:00+00:00  orchestrátor-session indul (E09-R02), időkorlát 14400s → /y.log
2026-08-05T11:40:00+00:00  ÖNJAVÍTÓ KÖR indul: E09-R02 / H6 (1/3)
2026-08-05T12:30:00+00:00  E09-R02 MERGE-ELVE — kész
2026-08-05T12:35:00+00:00  orchestrátor-session indul (E09-R03), időkorlát 14400s → /z.log
"""

    def test_round_duration_idle_and_self_heal_are_measured(self) -> None:
        result = round_metrics.summarize(round_metrics.parse_chain_log(self.LOG))
        rounds = {item["round"]: item for item in result["rounds"]}
        self.assertEqual(set(rounds), {"E09-R01", "E09-R02"}, "a be nem fejezett kör nem számít")
        self.assertEqual(rounds["E09-R01"]["duration_seconds"], 3600)
        self.assertEqual(rounds["E09-R02"]["duration_seconds"], 3600)
        self.assertEqual(rounds["E09-R02"]["idle_before_seconds"], 1800)
        self.assertEqual(rounds["E09-R02"]["blocked_firings_before"], 1)
        self.assertEqual(rounds["E09-R02"]["self_heal_rounds"], 1)

    def test_summary_reports_the_idle_share(self) -> None:
        result = round_metrics.summarize(round_metrics.parse_chain_log(self.LOG))
        self.assertEqual(result["summary"]["rounds_measured"], 2)
        self.assertAlmostEqual(result["summary"]["idle_share"], 1800 / (3600 + 3600 + 1800), places=6)

    def test_cli_reports_a_missing_log_as_an_error(self) -> None:
        result = subprocess.run(
            [sys.executable, str(ROOT / "tools" / "round-metrics.py"), "--chain-log", "/nincs/ilyen.log"],
            capture_output=True,
            text=True,
        )
        self.assertEqual(result.returncode, 2)


if __name__ == "__main__":
    unittest.main()


class MeasuredPrerequisiteRegimeTest(unittest.TestCase):
    """ADR 0495 D1/D2 — a párhuzamot a KIMONDOTT előfeltétel dönti el.

    MÉRVE 2026-09-03: a korábbi, epicen belüli VAK sorosítás a teljes hátralévő
    sort (E15-R09…R13 + E16-R01…R05) egyszálúvá tette, pedig az `E15-R10` és
    az `E15-R11` briefje az `E15-R03`-at (KÉSZ) nevezi meg előfeltételként. A
    2. slot heteken át üresen állt (`.pipeline/chain.log`: „nincs a futókkal
    diszjunkt, előfeltétel-kész kör" — az utolsó héten 358 firing).
    """

    def _round_brief(self, repo: Path, name: str, prerequisite_line: str | None) -> str:
        rounds = repo / "docs" / "rounds"
        rounds.mkdir(parents=True, exist_ok=True)
        text = "# fixture\n"
        if prerequisite_line is not None:
            text += prerequisite_line + "\n"
        (rounds / name).write_text(text, encoding="utf-8")
        return f"docs/rounds/{name}"

    def test_a_declared_and_done_prerequisite_no_longer_serialises_the_epic(self) -> None:
        """A kimondottan FÜGGETLEN, azonos epicbeli kör NEM blokkolt."""
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            first = self._round_brief(repo, "e15-r09.md", "- **Előfeltétel:** `E15-R03` merge-elve")
            second = self._round_brief(repo, "e15-r10.md", "- **Előfeltétel:** `E15-R03` merge-elve")
            rows = [
                ("E15-R03", "docs/rounds/e15-r03.md", "sonnet-impl", "nincs", "done"),
                ("E15-R09", first, "sonnet-impl", "nincs", "pending"),
                ("E15-R10", second, "sonnet-impl", "nincs", "pending"),
            ]
            self.assertEqual(round_slots.unmet_prerequisites(repo, "E15-R10", second, rows), [])

    def test_a_declared_and_open_prerequisite_still_blocks(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            brief = self._round_brief(repo, "e16-r02.md", "- **Előfeltétel:** `E16-R01` merge-elve")
            rows = [
                ("E16-R01", "docs/rounds/e16-r01.md", "sonnet-impl", "nincs", "pending"),
                ("E16-R02", brief, "sonnet-impl", "nincs", "pending"),
            ]
            self.assertEqual(round_slots.unmet_prerequisites(repo, "E16-R02", brief, rows), ["E16-R01"])

    def test_a_brief_that_says_nothing_falls_back_to_epic_serialisation(self) -> None:
        """FAIL-CLOSED: a hallgatás nem enged párhuzamot."""
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            first = self._round_brief(repo, "e15-r09.md", None)
            second = self._round_brief(repo, "e15-r10.md", None)
            rows = [
                ("E15-R09", first, "sonnet-impl", "nincs", "pending"),
                ("E15-R10", second, "sonnet-impl", "nincs", "pending"),
            ]
            self.assertEqual(round_slots.unmet_prerequisites(repo, "E15-R10", second, rows), ["E15-R09"])

    def test_a_round_does_not_block_itself(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            brief = self._round_brief(repo, "e15-r10.md", "- **Előfeltétel:** `E15-R10` a saját sora")
            rows = [("E15-R10", brief, "sonnet-impl", "nincs", "pending")]
            self.assertEqual(round_slots.unmet_prerequisites(repo, "E15-R10", brief, rows), [])

    def test_the_migration_journal_is_not_a_collision_surface(self) -> None:
        """A migrációs napló a merge-zár sorosítottja, nem ütközési felület."""
        paths = round_slots.effective_paths(
            ("docs/ui/migration-status.md", "lib/features/a/x_screen.dart")
        )
        self.assertEqual(paths, frozenset({"lib/features/a/x_screen.dart"}))

    def test_the_real_queue_admits_a_second_round_beside_the_running_one(self) -> None:
        """A MÉRT defekt cellája: E15-R09 futása mellett indulhat egy másik kör.

        A cella a VAK sorosítást méri — azt, hogy egy előfeltétel-KÉSZ jelöltet
        egy ál-útvonalütközés zár ki. Ha a nyitott sorban egyetlen
        előfeltétel-kész jelölt sincs, az nem áteresztő-defekt, hanem a
        roadmap KIMONDOTT alakja, és a cellának nincs mit mérnie.

        MÉRVE 2026-09-03 (ADR 0112 önjavító kör, E16-R02/H3): a `main` Router
        CI-je ezen a cellán pirosra váltott (`33802070985`), mert a sor
        maradéka szigorú előfeltétel-LÁNC — `E16-R02 → R03 → R04 → R05`,
        mindhárom jelölt `unmet_prerequisites` miatt esik ki, útvonalütközés
        nélkül. Ez ugyanaz a hibaosztály, amit az `docs/LESSONS.md` L612 mér:
        az őr a fa/sor egy ÁTMENETI állapotát pinnelte örök igazságként.
        """
        rows = round_slots.queue_rows(ROOT)
        pending = [row for row in rows if row[4] == "pending"]
        if not pending:
            self.skipTest("nincs nyitott kör a sorban")
        running = pending[0]
        ready = [
            candidate
            for candidate in pending[1:]
            if not round_slots.unmet_prerequisites(ROOT, candidate[0], candidate[1], rows)
        ]
        if not ready:
            self.skipTest(
                "a nyitott sor maradéka KIMONDOTT előfeltétel-lánc "
                f"({running[0]} után sorosított) — nincs előfeltétel-kész jelölt, "
                "tehát vak sorosítás sem lehet"
            )
        admitted = [
            candidate[0]
            for candidate in ready
            if not round_slots.paths_conflict(
                round_slots.load_paths(ROOT, running[1]),
                round_slots.load_paths(ROOT, candidate[1]),
            )
        ]
        self.assertTrue(
            admitted,
            "a 2. slot ismét üresen áll: van előfeltétel-kész kör "
            f"({[candidate[0] for candidate in ready]}), de mind útvonalütközésre "
            f"hivatkozva esik ki a(z) {running[0]} mellett",
        )

    def test_a_prerequisite_ready_candidate_blocked_only_by_paths_is_still_red(self) -> None:
        """A MÉRT defektet (E15-R09) a fenti `skipTest` NEM engedi át.

        Ez az előző cella ellenpróbája: előfeltétel-kész jelölt + ál-ütközés →
        a lelet megmarad. A skip kizárólag az előfeltétel-lánc alakra szól.
        """
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            first = self._round_brief(repo, "e15-r09.md", "- **Előfeltétel:** `E15-R03` merge-elve")
            second = self._round_brief(repo, "e15-r10.md", "- **Előfeltétel:** `E15-R03` merge-elve")
            rows = [
                ("E15-R03", "docs/rounds/e15-r03.md", "sonnet-impl", "nincs", "done"),
                ("E15-R09", first, "sonnet-impl", "nincs", "pending"),
                ("E15-R10", second, "sonnet-impl", "nincs", "pending"),
            ]
            pending = [row for row in rows if row[4] == "pending"]
            ready = [
                candidate
                for candidate in pending[1:]
                if not round_slots.unmet_prerequisites(repo, candidate[0], candidate[1], rows)
            ]

            self.assertEqual(
                [candidate[0] for candidate in ready],
                ["E15-R10"],
                "a kimondottan KÉSZ előfeltétel után a jelölt előfeltétel-kész — "
                "a skip-ág itt NEM léphet be, a mérés folytatódik",
            )


class IndependenceClauseTest(unittest.TestCase):
    """ADR 0495 D6 — a brief KIMONDHATJA, hogy egy körtől FÜGGETLEN.

    MÉRVE 2026-09-04 (E14 sáv visszakapcsolása): három brief szó szerint azt
    állítja, hogy párhuzamosítható —

        `E14-R03`: „Az `E14-R02`-től FÜGGETLEN — a két kör fájlhalmaza
                    diszjunkt, párhuzamosítható."
        `E14-R06`: „Az `E14-R02…R05`-től FÜGGETLEN — a fájlhalmaz diszjunkt…"
        `E14-R11`: „Az `E14-R10`-től független, de ha az előbb landol…"

    — a `declared_prerequisites` viszont MINDEN kör-tokent kiolvasott az
    `Előfeltétel` sorból, tehát pont az ELLENKEZŐJÉT értette, és a 18 körös
    sávot egyszálúvá tette. A kikötés ráadásul a KÖVETKEZŐ sorra volt tördelve,
    amit a soronkénti olvasás el sem ért.
    """

    def _prereqs(self, body: str) -> set[str]:
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            (repo / "docs" / "rounds").mkdir(parents=True)
            brief = repo / "docs" / "rounds" / "fixture.md"
            brief.write_text(body, encoding="utf-8")
            return set(round_slots.declared_prerequisites(repo, "docs/rounds/fixture.md"))

    def test_a_plain_prerequisite_still_blocks(self) -> None:
        self.assertEqual(
            self._prereqs("- **Előfeltétel:** `E14-R04` merge-elve (RecognitionFrame V2).\n"),
            {"E14-R04"},
        )

    def test_an_independence_clause_on_the_next_line_is_read(self) -> None:
        """A MÉRT alak: a kikötés a folytatás-sorra tördelve."""
        self.assertEqual(
            self._prereqs(
                "- **Előfeltétel:** `E14-R01` merge-elve (release guard). Az `E14-R02`-től\n"
                "  FÜGGETLEN — a két kör fájlhalmaza diszjunkt, párhuzamosítható.\n"
                "- **Brief szerzője:** Claude (Opus 5)\n"
            ),
            {"E14-R01"},
        )

    def test_a_lowercase_independence_clause_is_read_too(self) -> None:
        self.assertEqual(
            self._prereqs(
                "- **Előfeltétel:** `E14-R04` merge-elve (RecognitionFrame V2). Az `E14-R10`-től\n"
                "  független, de ha az előbb landol, a §2-t a pre-flight frissíti.\n"
            ),
            {"E14-R04"},
        )

    def test_a_mixed_clause_is_fail_closed(self) -> None:
        """Pozitív kötés ÉS függetlenség egy mondatban → MEGTARTJUK.

        A félreolvasás veszélyes iránya két függő kör párhuzamos indítása
        volna; egy elmaradt párhuzam csak lassabb.
        """
        self.assertEqual(
            self._prereqs(
                "- **Előfeltétel:** `E14-R04` merge-elve, az `E14-R10`-től független.\n"
            ),
            {"E14-R04", "E14-R10"},
        )

    def test_the_block_stops_at_the_next_bullet(self) -> None:
        """A következő felsorolás-elem kör-hivatkozása NEM előfeltétel."""
        self.assertEqual(
            self._prereqs(
                "- **Előfeltétel:** `E14-R04` merge-elve.\n"
                "- **Kapcsolódó:** `E14-R09` handoffja.\n"
            ),
            {"E14-R04"},
        )

    def test_the_real_e14_band_is_not_single_threaded(self) -> None:
        """A MÉRT defekt cellája: a sáv eleje párhuzamosítható."""
        rows = round_slots.queue_rows(ROOT)
        open_e14 = [row for row in rows if row[0].startswith("E14-") and row[4] == "pending"]
        if not open_e14:
            self.skipTest("az E14 sáv nincs nyitva")
        ready = [
            row[0]
            for row in open_e14
            if not round_slots.unmet_prerequisites(ROOT, row[0], row[1], rows)
        ]
        self.assertGreaterEqual(
            len(ready),
            2,
            "az E14 sáv egyszálú: a briefek KIMONDOTT függetlenségi kikötése nem érvényesül "
            f"(indítható körök: {ready})",
        )
