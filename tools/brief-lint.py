#!/usr/bin/env python3
"""Kör-brief lint: a javító körök MÉRT okait a briefben fogja meg (ADR 0171 §4).

    tools/brief-lint.py --brief docs/rounds/e04-r15-....md [--level strict]
    tools/brief-lint.py --all [--level base] [--format json]

MIÉRT: egy javító kör ára a kör legdrágább ismételhető eleme (implementer-futás
+ teljes gate + review + CI-újradispatch). A mért javító körök nagy része nem
kódhiba, hanem BRIEF-hiba: hiányzó falszifikációs cella (docs/LESSONS.md
„a mércét is ellenőrizd"), küszöb fölötti cella nélküli mátrix, olyan
gate_test, ami nem is létezik, vagy parancslánc a gate helyett.

Két szint, MÉRT okból:

* `base`  — ezt MINDEN meglévő brief teljesíti (mérve a bevezetéskor), ezért
  CI-kapunak alkalmas: a drift pirosra vált. Csak olyat tilt, ami bizonyítottan
  hibás.
* `strict` — a falszifikációs elvárások. Az előre megírt briefek egy része ezt
  még nem teljesíti, ezért NEM CI-kapu: a pipeline a kör pre-flightjában adja
  át az orchestrátornak teendőlistaként (a brief-revízió a §2 szerint az
  orchestrátor saját hatásköre), így a hiány a kör ELEJÉN javul, nem a
  review-ban.

Kilépési kódok:
    0 = nincs lelet a kért szinten
    1 = csak strict-lelet (figyelmeztetés)
    2 = base-lelet (hiba — CI-kapu piros)
    3 = használati hiba
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path, PurePosixPath

REPO_ROOT = Path(__file__).resolve().parent.parent
if str(REPO_ROOT) not in sys.path:
    sys.path.insert(0, str(REPO_ROOT))

from tools.ai_router.brief import BriefMetadataError, load_brief  # noqa: E402

GATE_ARTIFACT = "tools/round-gate.sh"
# A determinisztikus képernyő-leltár tesztje (S9). A `tool/ui_inventory.dart`
# a `lib/features/**` fa `_screen.dart` végű fájljait számolja, a teszt pedig
# EGZAKT `hasLength(...)`-et állít rájuk — minden ÚJ képernyő elmozdítja.
UI_INVENTORY_TEST = "test/ui/ui_inventory_test.dart"
FENCE = re.compile(r"^```(?:bash|sh)?[ \t]*\n(.*?)^```[ \t]*$", re.MULTILINE | re.DOTALL)
HEADING_TASK_ID = re.compile(r"(?im)^#\s*(E\d{2}-R\d{2})\b")
# A gate futtatását elrejtő parancsalakok. MÉRVE: a MiniMax M3 háromszor tette
# `| tail`-be a gate-et (docs/LESSONS.md), az `analyze && test` lánc pedig ezen
# a boxon OOM-ot okoz (L05) — ezért a briefben SEM szerepelhet mintaként.
FORBIDDEN_GATE_SHAPES = (
    (re.compile(r"round-gate\.sh[^\n]*\|\s*(tail|head)\b"), "a gate kimenetét csonkító pipe (`| tail`/`| head`)"),
    (re.compile(r"flutter\s+analyze[^\n]*&&[^\n]*flutter\s+test"), "`analyze && test` lánc (OOM ezen a boxon, L05)"),
)
# A falszifikáció ELFOGADOTT alakjai. MÉRVE (2026-08-05): az Epic 5 briefjeinek
# 25/30-a MÁR tartalmazott valódi falszifikációt („Valódi-sértés próba: az
# ellenőrzés kiszedése → a teszt PIROS → visszaállítás"), csak a korábbi, szűk
# markerlista nem ismerte fel — a lint 29 briefre riasztott, tévesen. Egy hamis
# riasztás rosszabb a hiányzó ellenőrzésnél: leszoktat az olvasásáról.
FALSIFICATION_PATTERNS = (
    re.compile(r"(?i)pirosra"),
    re.compile(r"(?i)falszifik"),
    re.compile(r"(?i)mérce-mátrix"),
    re.compile(r"(?i)melyik hibás implementáció"),
    re.compile(r"(?i)valódi-sértés"),
    re.compile(r"(?i)eldobható mutáci"),
    # A nagybetűs PIROS csak akkor számít, ha ELVÁRT KIMENET (nyíl vagy próba
    # mellett) — a „a CI piros lett" mondat nem falszifikációs cella.
    re.compile(r"→\s*\**PIROS"),
    re.compile(r"PIROS.{0,60}(visszaállítás|próba)", re.S),
)
STOP_MARKERS = ("**STOP", "STOP:", "STOP-protokoll", "STOP on scope conflict")
SIGNAL_MARKERS = ("kör-jelzés", "codex-round-status", "round-status", "Kör-jelzés")


QUEUE_RELATIVE = Path("docs") / "execution" / "pipeline-queue.tsv"
ROUTER_CONFIG_RELATIVE = Path(".ai") / "router.toml"
# A `risk = "high"` indoklás-kötelezettség (D3 / S7) a
# `.ai/router.toml` `[security] high_risk_path_fragments` listáját használja
# — a szigorítás a router-ci mércéjének saját, hivatalos forrásához kötött,
# nem a brief-lint saját definíciójához.
HIGH_RISK_JUSTIFICATION_MARKER = re.compile(r"^\*\*Kockázat = high, indoklás:\*\*")


def _high_risk_fragments(repo: Path) -> tuple[str, ...]:
    """A `[security] high_risk_path_fragments` értéke a router-configból.

    A config hiánya vagy a kulcs elhagyása NEM kivétel: a D3 kimondja, hogy
    `risk = "high"` csak akkor vállalható, ha a router konkrét, szöveges
    útvonal-mintája vagy a brief saját indoklása megvan. Hiányzó config
    mellett `()`-tel térünk vissza, ami minden magas-kockázatú briefet a
    `JUSTIFICATION`-ágra kényszerít — konzervatív, de nem blokkoló (a
    indoklás-sor bármikor hozzáírható).
    """
    path = repo / ROUTER_CONFIG_RELATIVE
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return ()
    import tomllib

    parsed = tomllib.loads(text)
    fragments = parsed.get("security", {}).get("high_risk_path_fragments", [])
    return tuple(fragment for fragment in fragments if isinstance(fragment, str) and fragment)


def screen_capable_prefixes(repo: Path, allowed_paths) -> list[str]:
    """A `lib/features/` alatti KÖNYVTÁR-előtagok, amelyek alá képernyő kerülhet.

    A `tool/ui_inventory.dart` REKURZÍVAN listázza a `lib/features/**` fát, ezért
    egy könyvtár-engedély a benne LÉTREHOZOTT képernyőre is szól. Az S9 eredeti,
    fájlútvonalra kötött predikátuma ezt nem látta — mérve az E13-R16/H3 halton
    (2026-08-25): a brief a `lib/features/onboarding/` könyvtárat engedte, a kör
    két képernyőt tett alá, a leltár 79→81 lett, és a lint mégis „nincs lelet"-et
    adott a teljes Ch13 sávra (`9acd14e5`).

    A hamis riasztás elleni mérce a fa MÉRHETŐ igazsága, nem tippelés:

    * a LÉTEZŐ, de `_screen.dart`-ot rekurzívan NEM tartó könyvtár kimarad — a
      leltár száma alóla nem mozdulhat (mérve: `lib/features/community/domain/
      repositories/` az E09-R05 `done` körből, `lib/features/practice_generator/
      public/` az E99-R18 `done` körből);
    * a MÉG NEM LÉTEZŐ könyvtárról semmit nem lehet mérni, ezért bent marad —
      épp ezek a Ch13 sáv új feature-fái (`lib/features/today/`, …).

    MÉRVE a 308 elemezhető brief korpuszán: 23 lelet, ebből **0 `done` (merge-elt)
    kör** — 20 `pending` (a teljes E13-R16…R35 sáv) és 3 `hold`.
    """
    capable: list[str] = []
    for path in allowed_paths:
        if not path.startswith("lib/features/") or not path.endswith("/"):
            continue
        directory = repo / path
        if directory.is_dir() and not any(directory.rglob("*_screen.dart")):
            continue
        capable.append(path)
    return sorted(set(capable))


def queue_rows(repo: Path) -> list[tuple[str, str, str]]:
    """(kör, brief, státusz) hármasok a sor-fájlból, sorrendben."""
    path = repo / QUEUE_RELATIVE
    try:
        text = path.read_text(encoding="utf-8")
    except OSError:
        return []
    rows: list[tuple[str, str, str]] = []
    for line in text.splitlines():
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) >= 5:
            rows.append((parts[0], parts[1], parts[4]))
    return rows


def predecessor_paths(repo: Path, task_id: str) -> frozenset[str]:
    """A sorban KORÁBBI körök allowed_paths uniója.

    MIÉRT KELL: egy előre megírt brief `gate_tests` értéke jogosan hivatkozhat
    olyan könyvtárra, amit egy korábbi kör hoz létre (mérve: az Epic 5 kamerás
    köreinél a `test/core/camera` az E05-R03-ban születik, de az E05-R06 is
    gate-eli). A puszta lemez-állapot ezt hamis pozitívnak látná, és a lint
    használhatatlanná válna minden előre megírt epicre.
    """
    collected: set[str] = set()
    for round_id, brief, _status in queue_rows(repo):
        if round_id.upper() == task_id.upper():
            break
        try:
            metadata = load_brief(repo / brief).metadata
        except (BriefMetadataError, OSError):
            continue
        collected.update(metadata.allowed_paths)
    return frozenset(collected)


def _gate_test_is_covered(gate_test: str, paths: frozenset[str] | tuple[str, ...]) -> bool:
    prefix = gate_test.rstrip("/") + "/"
    for candidate in paths:
        if gate_test == candidate or candidate.startswith(prefix) or gate_test.startswith(candidate.rstrip("/") + "/"):
            return True
    return False


# S5 — MÉRT eset: E06-R10/H3 (docs/LESSONS.md). A brief két ÚJ fájlt írt elő
# (`domain/events/onset_event.dart`, `.../strum_event.dart`), a fájlnévből
# származó `OnsetEvent`/`StrumEvent` típusnév viszont MÁR élt a nem
# engedélyezett `domain/analysis_event.dart` sealed `AnalysisEvent` családban
# — a brief azért volt stale, mert előre, egy MÉG NEM létező domain modellre
# írták (`main @ a6e6f3d`, Epic 6 kickoff előtt). A `public.dart` barrel a két
# azonos nevű típust ambiguous exportként bukta volna, vagy a fájl saját
# importja ütközött volna — vagyis a hiba a gate-ig el sem jutott volna
# implementáció nélkül mérve. Ez a lelet ugyanezt a fájlnév→típusnév
# heurisztikát futtatja MINDEN allowed_paths-beli, MÉG NEM létező .dart
# fájlra: ha a lemezen ÉRTELMEZETT típusnév egy, ugyanabban a feature-
# gyökérben MÁR létező, allowed_paths-on KÍVÜLI fájlban deklarálva van,
# az kollízió-gyanús, és emberi/orchesztrátor-felülvizsgálatot igényel —
# a fájl EXISTS-e szerinti ág (bővítés) nem lelet, csak az ÚJ fájl ága.
_DART_TYPE_DECL_KEYWORDS = r"(?:abstract\s+|base\s+|final\s+|interface\s+|sealed\s+)*(?:class|enum|mixin)"


def _dart_type_name_guess(filename_stem: str) -> str:
    """`onset_event` → `OnsetEvent` — a repó saját, kivétel nélküli konvenciója
    (fájlnév = az elsődleges publikus típus snake_case alakja)."""
    return "".join(word[:1].upper() + word[1:] for word in filename_stem.split("_") if word)


def _feature_root(relative: str) -> PurePosixPath | None:
    parts = PurePosixPath(relative).parts
    if len(parts) >= 3 and parts[0] == "lib" and parts[1] == "features":
        return PurePosixPath(*parts[:3])
    if len(parts) >= 2 and parts[0] == "lib":
        return PurePosixPath(*parts[:2])
    return None


def _existing_dart_declaration(
    repo: Path, root: PurePosixPath, type_name: str, *, exclude: frozenset[str]
) -> str | None:
    """Az első allowed_paths-on kívüli fájl a feature-gyökér alatt, ami a
    `type_name` nevű top-level class/enum/mixin-t deklarálja — vagy None."""
    root_dir = repo / root
    if not root_dir.is_dir():
        return None
    pattern = re.compile(rf"(?m)^\s*{_DART_TYPE_DECL_KEYWORDS}\s+{re.escape(type_name)}\b")
    for dart_file in sorted(root_dir.rglob("*.dart")):
        relative = dart_file.resolve().relative_to(repo.resolve()).as_posix()
        if relative in exclude:
            continue
        try:
            text = dart_file.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        if pattern.search(text):
            return relative
    return None


class Finding(dict):
    """Egy lelet: szint + kód + üzenet. dict, hogy a JSON-kimenet triviális legyen."""

    def __init__(self, level: str, code: str, message: str) -> None:
        super().__init__(level=level, code=code, message=message)


def _fenced_blocks(text: str) -> str:
    return "\n".join(FENCE.findall(text))


def lint_text(text: str, *, path: Path, repo: Path) -> list[Finding]:
    """A brief teljes leletlistája (base + strict), sorrendben."""
    findings: list[Finding] = []

    try:
        brief = load_brief(path)
    except BriefMetadataError as error:
        return [Finding("base", "B1", f"az ai-router blokk nem elemezhető: {error}")]

    metadata = brief.metadata
    relative = path.resolve().relative_to(repo.resolve()).as_posix()

    # B2 — a brief SAJÁT magát is engedélyezze: a pre-flight brief-revíziója
    # (§0.0) és a státuszfrissítés különben scope-sértés lenne.
    if relative not in metadata.allowed_paths:
        findings.append(
            Finding("base", "B2", f"a brief nem szerepel a saját allowed_paths listáján ({relative})")
        )

    # B3 — minden gate_test vagy LÉTEZIK, vagy a kör hozza létre (allowed_paths).
    # Mért hibaosztály: nem létező gate-útvonalra írt acceptance = mérhetetlen kör.
    earlier = predecessor_paths(repo, brief.task_id)
    for gate_test in metadata.gate_tests:
        if (repo / gate_test).exists():
            continue
        if _gate_test_is_covered(gate_test, metadata.allowed_paths) or _gate_test_is_covered(gate_test, earlier):
            continue
        findings.append(
            Finding(
                "base",
                "B3",
                f"a gate_tests eleme nem létezik, és sem ez a kör, sem korábbi sorbeli kör nem hozza létre: {gate_test}",
            )
        )

    # B4 — a gate artefaktum SZÓ SZERINT szerepeljen: a parancssorban
    # reprodukált lista nem bizonyíték (AGENTS.md §12).
    if GATE_ARTIFACT not in text:
        findings.append(Finding("base", "B4", f"a brief nem hivatkozza a gate artefaktumot ({GATE_ARTIFACT})"))

    # B5 — tiltott parancsalakok a brief kód-blokkjaiban.
    blocks = _fenced_blocks(text)
    for pattern, label in FORBIDDEN_GATE_SHAPES:
        if pattern.search(blocks):
            findings.append(Finding("base", "B5", f"tiltott parancsalak a brief kód-blokkjában: {label}"))

    # B6 — a fájlnév és a címsor kör-azonosítója egyezzen.
    heading = HEADING_TASK_ID.search(text)
    if heading and heading.group(1).upper() != brief.task_id:
        findings.append(
            Finding("base", "B6", f"a címsor kör-azonosítója ({heading.group(1)}) ≠ fájlnév ({brief.task_id})")
        )

    # S5 — allowed_paths ÚJ (lemezen még nem létező) .dart fájlja a fájlnévből
    # származtatott típusnevet MÁR deklarálja egy, ugyanabban a feature-
    # gyökérben élő, allowed_paths-on KÍVÜLI fájl (E06-R10/H3, docs/LESSONS.md).
    # Meglévő fájl bővítése (a path LÉTEZIK) sosem lelet — az a normál eset.
    # STRICT, nem base: mérve (2026-08-12) az Epic 6 előre megírt briefjei
    # közül HÁROM (R11/R12/R17) is ugyanezt a hibaosztályt hordozza — a
    # bevezetéskor tehát NEM minden meglévő brief teljesíti, így nem
    # CI-kapu (a brief-lint saját szabálya a base/strict határra). Az egyes
    # körök saját pre-flightja zárja, ahogy a fájl alján lévő megjegyzés
    # is mondja: „a lista-tágítás NEM" az önjavítás hatásköre a HALT-olt
    # körön kívülre.
    for allowed in metadata.allowed_paths:
        if not allowed.startswith("lib/") or not allowed.endswith(".dart"):
            continue
        if (repo / allowed).exists():
            continue
        root = _feature_root(allowed)
        if root is None:
            continue
        type_name = _dart_type_name_guess(Path(allowed).stem)
        if not type_name:
            continue
        collision = _existing_dart_declaration(
            repo, root, type_name, exclude=frozenset(metadata.allowed_paths)
        )
        if collision is not None:
            findings.append(
                Finding(
                    "strict",
                    "S5",
                    f"{allowed} új fájl a(z) {type_name} típust deklarálná, de ez már létezik "
                    f"itt (nem engedélyezett): {collision} — kollízió-/ambiguous-export kockázat, "
                    "revideáld az allowed_paths-t vagy a típusnevet",
                )
            )

    # S8 — visszakeresett előzmények (ADR 0312 §4.1). MÉRVE 2026-08-18: az
    # E99-R14 H3 gyökéroka ÓRÁKKAL korábban le volt írva (HANDOFF, E07-R21
    # heal), és egy kör mégis belefutott; az E07-R21/H2-nél pedig a brief
    # glosszája mondott mást, mint a hivatkozott ADR tényleges szövege. A
    # briefnek ezért meg kell mutatnia, MIT nézett meg: legalább egy
    # tudás-index találat azonosítóját (`lessons/L###`, `adr/0###`, `halts/…`),
    # VAGY azt a kimondott állítást, hogy nincs releváns előzmény.
    # STRICT, nem base: a meglévő briefek nem teljesítik, és a CI-kapu nem
    # szigorodhat egy új szokás miatt.
    # A markernek EXPLICITNEK kell lennie: a puszta ADR-link vagy a saját
    # brief-útvonal minden briefben szerepel, tehát trivilálisan teljesülne —
    # egy mindig zöld szabály leszoktat az olvasásáról (ugyanaz a hibaosztály,
    # amit a falszifikációs cella hamis pozitívjainál már mértünk).
    # ...és CSAK NYITOTT körre: egy lezárt kör briefje történelem, a
    # visszakeresés viszont a pre-flight kötelezettsége. Enélkül a szabály
    # visszamenőleg adna leletet a `done` körökre (mérve: E06-R10 briefje).
    round_status = {row[0].upper(): row[2] for row in queue_rows(repo)}.get(brief.task_id, "")
    if round_status != "done" and not re.search(
        r"(visszakeresett előzmény|nincs releváns előzmény)", text, re.I
    ):
        findings.append(
            Finding(
                "strict",
                "S8",
                "nincs visszakeresett előzmény: futtasd a "
                "`node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "
                "\"<a kör témája>\"` parancsot (SZŰKÍTVE — mérve ez talál, ADR 0331), és "
                "hivatkozd a releváns leckét/ADR-t (vagy mondd ki, hogy nincs ilyen)",
            )
        )

    # S1 — STOP-protokoll: scope-ütközéskor a brief-revízió a kimenet, nem a
    # lista-tágítás. Enélkül az implementer csendben tágít.
    if not any(marker in text for marker in STOP_MARKERS):
        findings.append(Finding("strict", "S1", "nincs STOP-protokoll szakasz (scope-ütközés esetére)"))

    # S2 — falszifikáció: minden acceptance-ponthoz tartozzon mért állítás
    # arról, MELYIK hibás implementációt fogja pirosra.
    if not any(pattern.search(text) for pattern in FALSIFICATION_PATTERNS):
        findings.append(
            Finding(
                "strict",
                "S2",
                "nincs falszifikációs cella: egyetlen acceptance-pont sem mondja meg, "
                "melyik hibás implementációt fogja pirosra (docs/LESSONS.md: a mércét is ellenőrizd)",
            )
        )

    # S3 — küszöb-mátrix: ahol numerikus küszöb van, ott alatta/rajta/fölötte
    # hármas kell (mérve: E02-R08 lag-mátrixából hiányzott a FÖLÖTTE cella).
    has_threshold = re.search(r"(?i)\b(küszöb|threshold|timeout|tolerancia|max(imum)?\s*=)\b", text) is not None
    # A küszöb-hármas ELFOGADOTT alakjai. A briefek „a küszöb **alatt / rajta /
    # fölött**" alakot használnak (nem „alatta"), és a degenerált-cellás
    # („tipikus / határ / degenerált") változat ugyanazt a szigort adja.
    has_matrix = (
        re.search(r"(?i)(alatt|below)\w*.{0,160}(rajta|\bat\b).{0,160}(fölött|felett|above)\w*", text, re.S)
        is not None
        or re.search(r"(?i)határ.{0,120}(degenerált|két oldal|±)", text, re.S) is not None
    )
    if has_threshold and not has_matrix:
        findings.append(
            Finding("strict", "S3", "numerikus küszöb szerepel, de nincs alatta/rajta/fölötte cellahármas")
        )

    # S4 — kör-jelzés: jelzés nélküli futás = bukott futás (AGENTS.md §15.2).
    if not any(marker.lower() in text.lower() for marker in SIGNAL_MARKERS):
        findings.append(Finding("strict", "S4", "nincs kör-jelzés (STOP/`done`) szakasz"))

    # S7 — `risk = "high"` indoklás-kötelezettség (E99-R19 D3, ADR 0307 §6).
    # Ha a brief kockázati besorolása magas, két, egymást kizáró út tartja
    # elfogadhatónak: (a) az `allowed_paths` ÉRINTI a router-konfig
    # `high_risk_path_fragments` listájának LEGALÁBB egy elemét — a router
    # CI mércéje így automatikusan szigorúbb ágra vált —, VAGY (b) a brief
    # szövege tartalmazza a `**Kockázat = high, indoklás:**` kezdetű sort, ami
    # kézzel, eseti indoklással látja el a magas besorolást. Mindkét út
    # hiánya: S7 strict lelet (a `base` szint változatlan, hogy a 68 meglévő,
    # nem igazolt `risk = "high"` brief egyből NE legyen piros — a kör
    # pre-flightja az S7-et a §2 szerint javítja, nem a CI-kapu).
    #
    # A korszak-határ fontos: CSAK NYITOTT (státusz != done) körökre lő.
    # Egy már lezárt kör briefje történeti rekord; a S7-et a §4 szerint
    # NEM szabad visszamenőleg pirosra állítania (mérve: E06-R10 briefje
    # `risk = "high"`, de a self-heal és a merge megelőzte a D3 bevezetését
    # — a teszt-regresszió elkerülésének ez a kulcsa).
    round_status_for_s7 = {row[0].upper(): row[2] for row in queue_rows(repo)}.get(brief.task_id, "")
    if metadata.risk == "high" and round_status_for_s7 != "done":
        fragments = _high_risk_fragments(repo)
        hit_path = False
        if fragments:
            for allowed in metadata.allowed_paths:
                if any(fragment in allowed for fragment in fragments):
                    hit_path = True
                    break
        has_justification = False
        for line in text.splitlines():
            # A brief a `> **Kockázat = high, indoklás:** ...` alakot
            # használja (markdown blockquote), és a marker a sor ELEJÉN
            # álló szó-szerinti szöveget várja — a `>` és a vezető szóköz
            # ezért a marker-illesztés ELŐTT le kell venni. A `lstrip`
            # `"> \t"`-vel kezeli a „> > " mélyebb idézet-blokkot is.
            candidate = line.lstrip("> \t").strip()
            if HIGH_RISK_JUSTIFICATION_MARKER.match(candidate):
                has_justification = True
                break
        if not hit_path and not has_justification:
            fragments_hint = (
                f"egyező allowed_path a router high_risk_path_fragments listájából "
                f"({', '.join(fragments)}) VAGY "
                if fragments
                else ""
            )
            findings.append(
                Finding(
                    "strict",
                    "S7",
                    "risk = \"high\", de a brief sem "
                    f"{fragments_hint}a `**Kockázat = high, indoklás:**` sort "
                    "nem tartalmazza — az indoklás a pre-flight §2 teendője",
                )
            )

    # S6 — aránytalanul kicsi kör (E99-R16 D3, ADR 0307 §3). Ha a brief
    # `allowed_paths` listája a brief-dokumentumon és a `gate_tests` elemein
    # kívül 2-nél kevesebb fájlt tartalmaz, és `native_gate = false`, a kör
    # valószínűleg összevonható a sorban szomszédos körével — a mérőeszköz
    # a `tools/brief-merge-plan.py`. CSAK strict, NEM base: egyes jogosan
    # kicsi körök (pl. ADR-bejegyzés, hotfix-egy-sor) nem CI-pirosak.
    # A küszöb SZÁNDÉKOSAN 2 (nem 1): a jelenlegi 6-os, 8-as `allowed_paths`
    # méretű governance-körök többsége a brief-fájlon kívül 5-7 fájlt ír —
    # a küszöb alatt az EGYSZERŰ (1 munka-fájl) kör marad.
    non_test_paths = [
        path
        for path in metadata.allowed_paths
        if path != relative and path not in metadata.gate_tests
    ]
    if not metadata.native_gate and len(non_test_paths) < 2:
        findings.append(
            Finding(
                "strict",
                "S6",
                "a brief munka-területe aránytalanul kicsi (a brief-fájlon és a "
                f"gate_tests-en kívül {len(non_test_paths)} fájl); valószínűleg "
                "összevonható a szomszédjával — futtasd a `tools/brief-merge-plan.py` "
                "elemzést, és mérlegeld az egyesítést",
            )
        )

    # S9 — képernyő-leltár drift (E09-R24 H-NOSIGNAL önjavítás, ADR 0112,
    # 2026-08-24). MÉRT ok: a `test/ui/ui_inventory_test.dart` EGZAKT
    # képernyőszámot állít (`screenPaths, hasLength(N)`), a `tool/ui_inventory.dart`
    # pedig a `lib/features/**` fa `_screen.dart` végű fájljait számolja. Egy ÚJ
    # képernyőt létrehozó kör tehát MINDIG elmozdítja a számot — és ha a brief
    # `allowed_paths`-a nem engedi a leltártesztet, az implementer hozzá sem
    # nyúlhat: a kör a ~17 perces exact-SHA Full Gate-en bukik.
    #
    # Az E09-R24 mért ára: `full-gate` 32713670226 FAILURE (`855db329`,
    # hasLength(76) vs 79) → diagnózis → `§0.0c` brief-revízió → EGY TELJES
    # javító implementer-kör az egysoros szám-emelésért → `full-gate`
    # 32716654207 (success). ~60 perc újramunka egy 4 órás időkeretben — ez
    # vitte a sessiont a H-NOSIGNAL-ig.
    #
    # A hibaosztály PRECEDENSES (E08-R15/H3 PR #383, E09-R21 §0.0), de a
    # védelem eddig csak KÖRSPECIFIKUS, utólagos regressziós tesztekben élt,
    # ezért a következő kört nem védte. A kör saját commit-üzenete (`863a8ac3`)
    # ki is mondja: „my own pre-flight missed applying it here despite having
    # read that exact precedent". Ez a lelet teszi általánossá, a pre-flight
    # szintjén, ahol még olcsó javítani.
    #
    # A LÉTEZÉS-feltétel a hamis riasztás elleni mérce: a MÓDOSÍTOTT képernyő
    # nem mozdítja a számot. MÉRVE a 343 brief korpuszán: a feltétel nélkül 39
    # lelet (36 már zölden merge-elt körre — mind hamis), a feltétellel 0 hamis
    # és 4 valódi (`e09-r25`, `e09-r28`, `e09-r29`, `e10-r31`, mind `pending`).
    # STRICT, nem base — a meglévő briefek nem válhatnak visszamenőleg
    # CI-pirossá (ugyanaz az elv, mint az S6/S7/S8 esetében).
    #
    # A KÖNYVTÁR-előtag vakfolt (E13-R16/H3 önjavítás, 2026-08-25). A fenti
    # predikátum kizárólag LITERÁLISAN `_screen.dart`-ra végződő `allowed_paths`
    # elemet nézett. Az E13-R16 briefje viszont a `lib/features/onboarding/`
    # KÖNYVTÁRAT engedte, és a két új képernyőt az alá tette — az S9 néma maradt.
    # A sáv-szintű batch pre-flight (`9acd14e5`) commit-üzenete rögzíti, hogy a
    # `--level strict` mind a 20 Ch13 briefen „nincs lelet"-et adott, miközben
    # mind a 20 ugyanezt a haltot hordozta. A mért ár: full-gate 32867296946
    # FAILURE (`hasLength(79)` vs 81) → H3, mert a leltárteszt felvétele az
    # orchestrátornak tágítás (L478). A `screen_capable_prefixes` a fa mérhető
    # igazságával zárja ki a hamis riasztást (lásd ott a korpusz-mérést).
    new_screens = sorted(
        path
        for path in metadata.allowed_paths
        if path.startswith("lib/features/")
        and path.endswith("_screen.dart")
        and not (repo / path).exists()
    )
    screen_dirs = screen_capable_prefixes(repo, metadata.allowed_paths)
    if (new_screens or screen_dirs) and not (
        UI_INVENTORY_TEST in metadata.allowed_paths and UI_INVENTORY_TEST in metadata.gate_tests
    ):
        reasons = []
        if new_screens:
            listed = ", ".join(f"`{path}`" for path in new_screens)
            reasons.append(f"{len(new_screens)} ÚJ képernyőt hoz létre ({listed})")
        if screen_dirs:
            listed_dirs = ", ".join(f"`{path}`" for path in screen_dirs)
            reasons.append(
                f"képernyőt tartható KÖNYVTÁR-előtagot enged ({listed_dirs}), tehát új "
                "képernyőt is létrehozhat alatta"
            )
        findings.append(
            Finding(
                "strict",
                "S9",
                f"a kör {' és '.join(reasons)}, de a "
                f"`{UI_INVENTORY_TEST}` nem szerepel egyszerre az `allowed_paths`-ban "
                "ÉS a `gate_tests`-ben — a leltár egzakt `hasLength(...)` száma "
                "elmozdul, és az exact-SHA Full Gate pirosra vált (mérve: E08-R15 "
                "PR #383, E09-R24 full-gate 32713670226, E13-R16 full-gate "
                "32867296946); vedd fel mindkét listára, "
                "és a szám-emelés a kör saját munkája legyen",
            )
        )

    return findings


def lint_paths(paths: list[Path], *, repo: Path, level: str) -> tuple[list[dict], int]:
    """Leletek + a legmagasabb súlyosság kilépési kódja."""
    wanted = {"base"} if level == "base" else {"base", "strict"}
    report: list[dict] = []
    worst = 0
    for path in sorted(paths):
        try:
            text = path.read_text(encoding="utf-8")
        except OSError as error:
            report.append({"brief": str(path), "findings": [Finding("base", "B0", f"olvashatatlan: {error}")]})
            worst = 2
            continue
        findings = [item for item in lint_text(text, path=path, repo=repo) if item["level"] in wanted]
        if findings:
            report.append({"brief": path.resolve().relative_to(repo.resolve()).as_posix(), "findings": findings})
            if any(item["level"] == "base" for item in findings):
                worst = 2
            elif worst == 0:
                worst = 1
    return report, worst


def render_markdown(report: list[dict], *, level: str) -> str:
    if not report:
        return f"# Brief-lint ({level}) — nincs lelet\n"
    lines = [f"# Brief-lint ({level}) — {len(report)} briefen van lelet", ""]
    for entry in report:
        lines.append(f"## {entry['brief']}")
        for finding in entry["findings"]:
            lines.append(f"- **{finding['code']}** ({finding['level']}): {finding['message']}")
        lines.append("")
    lines.append(
        "> A `strict` leletek a kör pre-flightjának teendői: a brief-revízió "
        "(§0.0) az orchestrátor saját hatásköre, a lista-tágítás NEM."
    )
    return "\n".join(lines) + "\n"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Kör-brief lint (ADR 0171)")
    parser.add_argument("--brief", type=Path, action="append", default=[], help="egy brief útvonala")
    parser.add_argument("--all", action="store_true", help="minden docs/rounds/*.md brief")
    parser.add_argument(
        "--open",
        action="store_true",
        help="a sor MÉG NYITOTT (státusz != done) köreinek briefjei — ez a CI-kapu hatóköre",
    )
    parser.add_argument("--repo", type=Path, default=REPO_ROOT)
    parser.add_argument("--level", choices=("base", "strict"), default="base")
    parser.add_argument("--format", choices=("markdown", "json"), default="markdown")
    parser.add_argument("--out", type=Path, default=None, help="a jelentés fájlba is")
    arguments = parser.parse_args(argv)

    repo = arguments.repo.resolve()
    paths = [path if path.is_absolute() else repo / path for path in arguments.brief]
    if arguments.all:
        rounds = repo / "docs" / "rounds"
        paths.extend(sorted(path for path in rounds.glob("*.md") if re.search(r"(?i)e\d{2}-r\d{2}", path.name)))
    if arguments.open:
        # A MERGE-ELT körök briefje történeti rekord: visszamenőleg nem
        # linteljük (a régi, ai-router blokk nélküli E01/E02-es briefek
        # különben örökre pirosra állítanák a kaput). A kapu a JÖVŐ köreit
        # méri — ott van értelme, mert ott még olcsó javítani.
        paths.extend(repo / brief for _round, brief, status in queue_rows(repo) if status != "done")
    if not paths:
        if arguments.open:
            # MÉRT eset (2026-08-14, az Epic 6 lezárása): ha a sor minden köre
            # `done`, az `--open` nulla briefet old fel — de ez NEM hiányzó
            # kapcsoló, hanem LEGITIM epic-határ. A régi ág usage-hibának
            # vette (exit 3), amitől a router-ci.yml „Round brief lint gate
            # (open rounds)" lépése pirosra állította a main-t, a
            # `round-pipeline.sh:1584` main-health kapuja pedig nem indít
            # munkát piros main fölé — a lánc magára zárta az ajtót.
            #
            # Ez a HARMADIK fogyasztója ugyanannak az „üres sor" állapotnak
            # (a másik kettő a tools/tests két kapuja, PR #258). A mérce nem
            # gyengül: nulla nyitott briefen nincs mit linteni, és minden
            # MÁSIK hívási alak (`--brief`, `--all`) változatlanul usage-hibát
            # ad, ha nem old fel útvonalat.
            print("brief-lint: nincs nyitott kör — a sor kiürült (epic-határ)")
            return 0
        print("brief-lint: adj meg --brief-et, --open-t vagy --all-t", file=sys.stderr)
        return 3

    report, worst = lint_paths(paths, repo=repo, level=arguments.level)

    if arguments.format == "json":
        rendered = json.dumps(
            {"schema_version": 1, "level": arguments.level, "briefs": report},
            ensure_ascii=False,
            sort_keys=True,
            indent=2,
        )
    else:
        rendered = render_markdown(report, level=arguments.level)
    print(rendered)
    if arguments.out is not None:
        arguments.out.parent.mkdir(parents=True, exist_ok=True)
        arguments.out.write_text(rendered, encoding="utf-8")
    return worst


if __name__ == "__main__":
    raise SystemExit(main())
