"""A tudás-RAG darabolójának és frissesség-őrének mérése (ADR 0310).

A RAG értéke a VISSZAKERESHETŐSÉG, ezért a teszt nem a modellt méri, hanem azt,
amit gépileg lehet: a chunk-határokat, a korpusz-lefedettséget és azt, hogy az
elavult index elavultnak LÁTSZIK-e (mérve 2026-08-18: a régi kód-index három
hete állt, 168 fájlt ismert a 918-ból, és ezt semmi nem jelezte).
"""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent.parent
TOOL = REPO_ROOT / "tools" / "knowledge-rag.mjs"


def node(*args: str, cwd: Path | None = None, env: dict | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["node", str(TOOL), *args],
        capture_output=True,
        text=True,
        cwd=str(cwd or REPO_ROOT),
        env={**os.environ, **(env or {})},
        timeout=600,
    )


@unittest.skipUnless(shutil.which("node"), "nincs node ezen a futón")
class KnowledgeRagTest(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.index_dir = Path(self._tmp.name)
        self.addCleanup(self._tmp.cleanup)
        # Kulcs nélkül futunk: a BM25-ág mérhető hálózat nélkül.
        self.env = {"RAG_INDEX_DIR": str(self.index_dir), "OPENAI_API_KEY": ""}

    def test_every_lesson_becomes_its_own_chunk(self) -> None:
        """A leckék száma a chunkok alsó korlátja — egy lecke nem olvadhat a szomszédjába."""
        lessons = (REPO_ROOT / "docs" / "LESSONS.md").read_text(encoding="utf-8")
        expected = lessons.count("\n## L")
        result = node("--bm25", "--corpus", "lessons", "--top", "1", "--json", "lecke", env=self.env)
        self.assertEqual(result.returncode, 0, result.stderr)
        hits = json.loads(result.stdout)
        self.assertTrue(hits, "a lecke-korpusz üres")
        self.assertTrue(hits[0]["id"].startswith("lessons/L"), hits[0]["id"])
        self.assertGreater(expected, 300, "a lecke-marker konvenció megváltozott")

    def test_a_measured_lesson_is_retrievable_by_its_own_words(self) -> None:
        """L313 (ambiens PIPELINE_* szivárgás) — pont az az eset, amit a RAG-nak fognia kell."""
        result = node(
            "--bm25", "--corpus", "lessons", "--top", "8", "--json",
            "PIPELINE_ORCH_SWAP_ENGINE driver teszt os.environ örökölte",
            env=self.env,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        ids = [hit["id"] for hit in json.loads(result.stdout)]
        self.assertIn("lessons/L313", ids, f"a mért lecke nincs a top-8-ban: {ids}")

    def test_the_code_corpus_covers_the_live_tree_not_a_stale_snapshot(self) -> None:
        """MÉRVE: a régi kód-index 168 fájlt ismert a 918-ból, három hete."""
        result = node("--bm25", "--corpus", "code", "--top", "3", "--json", "PlanValidator", env=self.env)
        self.assertEqual(result.returncode, 0, result.stderr)
        hits = json.loads(result.stdout)
        self.assertTrue(hits, "a kód-korpusz nem ad találatot a friss fára")
        self.assertTrue(
            any(hit["file"].startswith("lib/") or hit["file"].startswith("test/") for hit in hits),
            [hit["file"] for hit in hits],
        )

    def test_stat_reports_a_missing_index_instead_of_pretending(self) -> None:
        result = node("--stat", env=self.env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("MÉG NEM ÉPÜLT", result.stdout)

    def test_stat_flags_an_index_built_on_an_older_commit(self) -> None:
        """Az elavult index a legveszélyesebb: magabiztos, de régi választ ad."""
        (self.index_dir / "index.json").write_text(
            json.dumps({
                "meta": {"model": "text-embedding-3-small", "updatedAt": "2026-07-28T19:11:07Z",
                          "commit": "0" * 40, "chunks": 310, "counts": {"code": 310}},
                "entries": {},
            }),
            encoding="utf-8",
        )
        result = node("--stat", env=self.env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("ELAVULT", result.stdout)

    def test_search_degrades_to_bm25_without_a_key_instead_of_failing(self) -> None:
        result = node("--corpus", "adr", "--top", "2", "--json", "zöld kapu", env=self.env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertTrue(json.loads(result.stdout))


if __name__ == "__main__":
    unittest.main()


@unittest.skipUnless(shutil.which("node"), "nincs node ezen a futón")
class LearningCorporaTest(unittest.TestCase):
    """A lánc SAJÁT tanulása is korpusz (ADR 0312 §4.3)."""

    def test_git_notes_are_indexed_as_an_experience_buffer(self) -> None:
        result = node("--bm25", "--corpus", "notes", "--top", "3", "--json", "round verdict lesson")
        self.assertEqual(result.returncode, 0, result.stderr)
        hits = json.loads(result.stdout)
        if not hits:
            self.skipTest("ebben a klónban nincsenek git-notes")
        self.assertTrue(all(hit["id"].startswith("notes/") for hit in hits), hits)

    def test_halt_records_are_retrievable_by_their_code(self) -> None:
        result = node("--bm25", "--corpus", "halts", "--top", "3", "--json", "H3 halt scope")
        self.assertEqual(result.returncode, 0, result.stderr)
        hits = json.loads(result.stdout)
        if not hits:
            self.skipTest("nincs elérhető .pipeline állapotkönyvtár ezen a futón")
        self.assertTrue(all(hit["corpus"] == "halts" for hit in hits), hits)


class PipelineWiringTest(unittest.TestCase):
    """A RAG csak akkor ér valamit, ha a lánc TÉNYLEG használja."""

    def test_the_driver_reindexes_after_a_merge(self) -> None:
        driver = (REPO_ROOT / "tools" / "round-pipeline.sh").read_text(encoding="utf-8")
        self.assertIn("PIPELINE_RAG_REINDEX", driver)
        # Az útvonal idézőjeles változóból jön, ezért a két jelet külön mérjük.
        self.assertIn("knowledge-rag.mjs", driver)
        self.assertIn("--reindex", driver)

    def test_the_self_heal_prompt_gets_prior_cases(self) -> None:
        driver = (REPO_ROOT / "tools" / "round-pipeline.sh").read_text(encoding="utf-8")
        self.assertIn("Korábbi, hasonló esetek a tudás-indexből", driver)

    def test_the_orchestrator_prompt_requires_a_retrieval_step(self) -> None:
        prompt = (REPO_ROOT / "docs" / "execution" / "pipeline-orchestrator-prompt.md").read_text(encoding="utf-8")
        self.assertIn("knowledge-rag.mjs", prompt)

    def test_brief_lint_flags_a_brief_without_retrieved_precedent(self) -> None:
        """Corrected under the E07-R25 H5 self-heal (ADR 0112, 2026-08-19) --
        same failure class as docs/LESSONS.md L279/L280. The original
        fixture pointed at a REAL round's brief
        (`e99-r15-gov-09-halt-escalation.md`). `brief-lint.py`'s S8 check is
        deliberately silent once that round's queue row is `done` (see the
        "CSAK NYITOTT körre" comment above S8's implementation; measured
        precedent: `e06-r10`'s brief, `test_e06_r10_brief_is_clean_after_
        the_h3_self_heal` in test_pipeline_throughput.py) -- so the moment
        E99-R15 completed, brief-lint correctly stopped flagging it and this
        test broke, not because S8 regressed but because it did exactly what
        it was designed to do. Any real round brief is a ticking time bomb
        for this fixture, since every round eventually reaches `done`; a
        synthetic brief with a task id that never appears in the real queue
        removes the coupling instead of just moving its expiry date."""
        import subprocess as sp
        import tempfile

        brief_text = (
            "# E00-R00 — Self-heal fixture (no retrieved-precedent section)\n\n"
            "```ai-router\n"
            'schema_version = 1\n'
            'risk = "normal"\n'
            "allowed_paths = [\n"
            '  "lib/features/example/example.dart",\n'
            '  "test/features/example/example_test.dart",\n'
            "]\n"
            'gate_tests = ["test/features/example"]\n'
            "native_gate = false\n"
            "```\n\n"
            "## 1. Cél\n\n"
            "Self-heal fixture -- deliberately carries no retrieved-precedent "
            "marker, so S8 (ADR 0312 §4.1) must fire regardless of any real "
            "round's queue status.\n"
        )
        # `brief-lint.py`'s lint_text() requires the brief path to resolve
        # under `repo` (`path.resolve().relative_to(repo.resolve())`), so the
        # tempdir must be nested inside REPO_ROOT, not the system temp root.
        with tempfile.TemporaryDirectory(dir=REPO_ROOT) as tmp:
            brief = Path(tmp) / "e00-r00-selfheal-fixture.md"
            brief.write_text(brief_text, encoding="utf-8")
            result = sp.run(
                ["python3", str(REPO_ROOT / "tools" / "brief-lint.py"), "--brief", str(brief), "--level", "strict"],
                capture_output=True, text=True, timeout=120,
            )
        self.assertIn("S8", result.stdout, result.stdout[-400:])

    def test_the_base_gate_did_not_get_stricter(self) -> None:
        import subprocess as sp
        result = sp.run(
            ["python3", str(REPO_ROOT / "tools" / "brief-lint.py"), "--open", "--level", "base"],
            capture_output=True, text=True, timeout=600,
        )
        self.assertEqual(result.returncode, 0, result.stdout[-600:])


@unittest.skipUnless(shutil.which("node"), "nincs node ezen a futón")
class RetrievalRankingTest(unittest.TestCase):
    """A RANGSOR mérése (ADR 0316).

    A visszakeresés minőségét a `tools/rag-eval.tsv` mércéje méri; ezek a
    tesztek azt védik, ami gépileg ellenőrizhető hálózat nélkül: a
    dokumentum-korlát CSOPORTOSÍTÁSI EGYSÉGÉT, a több-korpuszos szűrőt és az
    ágankénti helyezés láthatóságát.
    """

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.index_dir = Path(self._tmp.name)
        self.addCleanup(self._tmp.cleanup)
        self.env = {"RAG_INDEX_DIR": str(self.index_dir), "OPENAI_API_KEY": ""}

    def test_the_document_cap_does_not_collapse_a_record_corpus(self) -> None:
        """A `docs/LESSONS.md` 346 leckéje EGY fájl — a fájl-alapú korlát az
        egész korpuszt két találatra vágná.

        MÉRVE 2026-08-19: a naiv, fájlra csoportosító korlát a visszakeresési
        mércét 53,8%-ról 38,5%-ra rontotta, és a döntő leckék (L142, L143,
        L323) kiestek a top-20-ból. Ez a teszt azt a regressziót fogja meg.
        """
        result = node("--bm25", "--corpus", "lessons", "--top", "8", "--json", "gate",
                      env={**self.env, "RAG_MAX_PER_DOC": "2"})
        self.assertEqual(result.returncode, 0, result.stderr)
        hits = json.loads(result.stdout)
        self.assertGreater(
            len(hits), 2,
            "a dok-korlát a lecke-korpuszt fájl-szinten csoportosítja — "
            f"csak {len(hits)} találat jött vissza",
        )

    def test_the_document_cap_does_bound_a_narrative_document(self) -> None:
        """Ahol egy fájl ÖSSZEFÜGGŐ dokumentum, ott a korlátnak élnie kell:
        egyetlen forrás ne foglalhassa a lista több helyét (MÉRVE: egy
        lekérdezés első négy helyét ugyanannak a briefnek négy szakasza vitte)."""
        result = node("--bm25", "--corpus", "sdd", "--top", "12", "--json", "teszt gate kör",
                      env={**self.env, "RAG_MAX_PER_DOC": "2"})
        self.assertEqual(result.returncode, 0, result.stderr)
        hits = json.loads(result.stdout)
        self.assertTrue(hits, "üres találati lista")
        per_file: dict[str, int] = {}
        for h in hits:
            per_file[h["file"]] = per_file.get(h["file"], 0) + 1
        worst = max(per_file.values())
        self.assertLessEqual(worst, 2, f"egy forrás {worst} helyet foglal: {per_file}")

    def test_several_corpora_can_be_filtered_in_one_call(self) -> None:
        """`--corpus lessons,adr` — a pre-flight természetes szűkítése."""
        result = node("--bm25", "--corpus", "lessons,adr", "--top", "12", "--json", "gate kör",
                      env=self.env)
        self.assertEqual(result.returncode, 0, result.stderr)
        hits = json.loads(result.stdout)
        found = {h["corpus"] for h in hits}
        self.assertTrue(found <= {"lessons", "adr"}, f"idegen korpusz szivárgott be: {found}")
        self.assertEqual(found, {"lessons", "adr"}, f"nem mindkét korpuszból jött találat: {found}")

    def test_the_handoff_corpus_is_indexed(self) -> None:
        """A HANDOFF.md + archívum 12 093 sora korábban EGYÁLTALÁN nem volt
        kereshető (ADR 0316 §2.4)."""
        result = node("--bm25", "--corpus", "handoff", "--top", "3", "--json", "kör lezárva",
                      env=self.env)
        self.assertEqual(result.returncode, 0, result.stderr)
        hits = json.loads(result.stdout)
        self.assertTrue(hits, "a handoff korpusz üres")
        self.assertTrue(all(h["corpus"] == "handoff" for h in hits), hits)

    def test_the_result_shows_which_branch_ranked_it(self) -> None:
        """A puszta RRF-pontszám rang-információ, nem relevancia (1/61, 1/62 …):
        ugyanaz a 0,0164 jött ki értelmes és értelmetlen kérdésre is. Az
        ágankénti helyezés az, amiből a hiba diagnosztizálható."""
        result = node("--bm25", "--corpus", "lessons", "--top", "3", "win32", env=self.env)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("bm25#", result.stdout, result.stdout[:400])
