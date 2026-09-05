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
import subprocess
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
# A shell-destination navigációs őrök (S10). Az E13-R08 óta EZEK pinnelik, hogy
# az adaptív shell melyik route-ja melyik képernyő-TÍPUST rendereli — az öt
# destinationt, a tizenegy alútvonal-adaptert és a tizenegy legacy redirect
# célját. Egy kör, amelyik a routert átírhatja, bármelyiket pirosra válthatja.
NAV_GUARD_DIR = "test/app/navigation/"
NAV_GUARD_TESTS = (
    "test/app/navigation/adaptive_scaffold_test.dart",
    "test/app/navigation/tab_state_restoration_test.dart",
    "test/app/navigation/legacy_route_redirect_test.dart",
)
# A router forrása: ezt kell engednie egy briefnek ahhoz, hogy egy destination
# builderét egyáltalán át tudja kötni.
ROUTING_SOURCE_DIR = "lib/app/routing/"
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


def covered_by(path: str, entries) -> bool:
    """A router `_matches` szemantikája: minden bejegyzés ELŐTAG.

    A `tools/ai_router/security.py::_matches` így dönt a scope-auditban
    (`path == prefix.rstrip('/') or path.startswith(prefix.rstrip('/') + '/')`),
    ezért a lint sem tekintheti hiánynak, ha a brief a KÖNYVTÁRAT engedte a
    fájl helyett — különben a saját mércéjétől eltérőt követelne.
    """
    for entry in entries:
        prefix = entry.rstrip("/")
        if path == prefix or path.startswith(prefix + "/"):
            return True
    return False


ROUTER_SOURCE = "lib/app/routing/app_router.dart"
ROUTE_CATALOGUE_SOURCE = "lib/app/routing/app_route.dart"

# `GoRoute(path: AppRoutes.profileProgress, builder: (_, _) => const ProgressScreen(`
GO_ROUTE_BUILDER = re.compile(
    r"GoRoute\(\s*path:\s*AppRoutes\.(?P<constant>\w+)\s*,"
    r"(?:\s*name:[^\n]*\n)?"
    r"\s*builder:\s*\([^)]*\)\s*=>\s*const\s+(?P<screen>\w+)\(",
)
# `static const String profileProgress = '/profile/progress';`
ROUTE_CONSTANT = re.compile(r"static const String (?P<name>\w+)\s*=\s*'(?P<literal>[^']*)'")
SCREEN_IMPORT = re.compile(r"^import\s+'(?P<uri>[^']*_screen\.dart)'", re.MULTILINE)


def _router_screen_files(repo: Path) -> dict[str, str]:
    """képernyő-TÍPUS → a forrásfájlja, a router saját importjaiból.

    A típusnevet a repó kivétel nélküli fájlnév-konvenciójából vezetjük le
    (`_dart_type_name_guess`), ugyanúgy, ahogy az `_screen_pins` teszi — így a
    két oldal ugyanazt a szabályt használja, nem két külön tippet.
    """
    source = repo / ROUTER_SOURCE
    try:
        text = source.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return {}
    files: dict[str, str] = {}
    for match in SCREEN_IMPORT.finditer(text):
        uri = match.group("uri")
        if uri.startswith("package:strumsight/"):
            relative = "lib/" + uri[len("package:strumsight/") :]
        elif uri.startswith("package:") or uri.startswith("dart:"):
            continue
        else:
            resolved = (repo / ROUTER_SOURCE).parent / uri
            try:
                relative = resolved.resolve().relative_to(repo.resolve()).as_posix()
            except (OSError, ValueError):
                continue
        if not relative.startswith("lib/") or not (repo / relative).is_file():
            continue
        files[_dart_type_name_guess(PurePosixPath(relative).stem)] = relative
    return files


def route_level_swapped_screens(
    repo: Path, allowed_paths, brief_text: str | None
) -> dict[str, list[str]]:
    """A kör által ÚTVONAL-SZINTEN lecserélhető, létező képernyők (S11/S14).

    A visszatérés `képernyő-fájl → a briefben MEGNEVEZETT útvonal-tokenek`
    (a konstans neve és a katalógusbeli szó szerinti útvonal); a tokenek adják
    a pin-szűrő második mércéjét (`_route_pin_requirement`).

    MÉRT vakfolt (E16-R02 / 3. H3, 2026-09-03): az `owned_existing_screens` a
    képernyő-cserét FÁJL-TULAJDONLÁSBÓL méri („a kör átírja a képernyő
    fájlját"), a valóságban viszont a csere történhet a routerben is — a
    képernyő fájlja érintetlen marad, csak a `GoRoute.builder` mutat máshová.
    Az E16-R02 `allowed_paths`-a egyetlen `*_screen.dart` fájlt és egyetlen
    `lib/` könyvtár-előtagot sem tartalmazott, ezért a képernyő-halmaz ÜRES
    lett, és az S11 (`external_screen_pins`) meg az S14 strukturálisan NÉMA
    maradt — miközben a `/profile/progress` átkötését a briefen kívül élő
    `test/features/today/hub_navigation_test.dart:247` pinnelte a legacy
    `ProgressScreen` típusára (`.pipeline/halt-detail-E16-R02.md` §3). A
    lecserélt képernyő ráadásul jellemzően a kör TILOS zónájában van, tehát
    elvileg sem kerülhetne az `allowed_paths`-ba.

    A HAMIS RIASZTÁS elleni három mérce (a router 45 `GoRoute`-ot köt be, a
    válogatás nélküli felvétel használhatatlan zajt adna):

    * a router forrása legyen a kör scope-jában (`covered_by`) — enélkül a kör
      egyetlen buildert sem tud átkötni;
    * a brief NEVEZZE MEG az útvonalat: vagy az `AppRoutes.<konstans>` alakot,
      vagy a katalógusbeli szó szerinti útvonalat. Az E16-R02-n mérve ez a két
      szűrő 45 bekötésből **2**-t hagy meg (`progress`, `profileProgress`),
      mindkettő ugyanarra a `ProgressScreen`-re — pontosan a cserélt képernyő;
    * a PIN oldalán ugyanezt kérjük (`_route_pin_requirement`): a listázott
      teszt nevezze meg magát az útvonalat is. Egy builder-átkötés ugyanis csak
      azt a tesztet viheti pirosra, amelyik AZON az útvonalon jut a képernyőhöz
      — a képernyőt közvetlenül építő teszt (`home: ProgressScreen()`,
      `test/core/screen_size_guard_test.dart:176`) és a képernyő saját
      unit-tesztje a routertől függetlenül fut tovább. Az E16-R02-n mérve ez a
      harmadik mérce 5 pinből **3**-at hagy meg — mindhárom valóban a
      `/progress` → `/profile/progress` láncon jut a képernyőhöz.
    """
    if brief_text is None or not covered_by(ROUTER_SOURCE, allowed_paths):
        return {}
    try:
        router_text = (repo / ROUTER_SOURCE).read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return {}
    try:
        catalogue_text = (repo / ROUTE_CATALOGUE_SOURCE).read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        catalogue_text = ""

    literals = {
        match.group("name"): match.group("literal")
        for match in ROUTE_CONSTANT.finditer(catalogue_text)
    }
    screen_files = _router_screen_files(repo)
    swapped: dict[str, list[str]] = {}
    for match in GO_ROUTE_BUILDER.finditer(router_text):
        constant = match.group("constant")
        relative = screen_files.get(match.group("screen"))
        if relative is None:
            continue
        literal = literals.get(constant)
        if not re.search(r"\bAppRoutes\." + re.escape(constant) + r"\b", brief_text):
            # Az útvonal-határ kizárja, hogy a `/progress` a `/profile/progress`
            # részszövegére, vagy egy szegmens egy hosszabb szó belsejére üljön.
            if not literal or not re.search(
                r"(?<![\w/])" + re.escape(literal) + r"(?![\w/:])", brief_text
            ):
                continue
        tokens = swapped.setdefault(relative, [])
        for token in (constant, literal):
            if token and token not in tokens:
                tokens.append(token)
    return {screen: sorted(tokens) for screen, tokens in sorted(swapped.items())}


def _route_pin_requirement(swapped: dict[str, list[str]], file_owned) -> dict[str, re.Pattern[str]]:
    """képernyő → az a minta, amit a PINNELŐ tesztnek is tartalmaznia kell.

    Csak a KIZÁRÓLAG útvonal-szinten cserélt képernyőkre szól: ha a kör magát a
    képernyő fájlját is átírhatja, a pin minden alakja érintett, tehát ott nincs
    második mérce.
    """
    requirement: dict[str, re.Pattern[str]] = {}
    for screen, tokens in swapped.items():
        if screen in file_owned or not tokens:
            continue
        alternatives = []
        for token in tokens:
            if token.startswith("/"):
                alternatives.append(r"(?<![\w/])" + re.escape(token) + r"(?![\w/:])")
            else:
                alternatives.append(r"\bAppRoutes\." + re.escape(token) + r"\b")
        requirement[screen] = re.compile("|".join(alternatives))
    return requirement


def owned_existing_screens(repo: Path, allowed_paths, brief_text: str | None = None) -> list[str]:
    """A kör által ÁTÍRHATÓ, a fában MÁR LÉTEZŐ képernyők (S11).

    Az S9 párja, ellenkező irányba: az S9 az ÚJ képernyő leltár-hatását méri, ez
    a MEGLÉVŐ képernyő lecserélésének kifelé mutató hatását. A könyvtár-előtag
    itt is számít (a `covered_by`/scope-audit ugyanígy dönt), de csak a
    ténylegesen létező fájlokra bomlik le — nemlétező képernyőt senki nem pinnel.

    A csere KÉT alakban történhet, és mindkettő ide tartozik: a kör átírja a
    képernyő FÁJLJÁT (ez a `brief_text` nélkül is mért, eredeti ág), vagy
    ÚTVONAL-SZINTEN köti át a routert (`route_level_swapped_screens`) — az
    utóbbi a mért E16-R02 vakfolt, ahol a képernyő fájlja érintetlen marad.
    """
    screens: set[str] = set(route_level_swapped_screens(repo, allowed_paths, brief_text))
    screens.update(file_owned_screens(repo, allowed_paths))
    return sorted(screens)


def file_owned_screens(repo: Path, allowed_paths) -> list[str]:
    """A kör `allowed_paths`-a által FÁJLKÉNT birtokolt, létező képernyők."""
    screens: set[str] = set()
    repo_root = repo.resolve()
    for path in allowed_paths:
        if not path.startswith("lib/"):
            continue
        if path.endswith("_screen.dart"):
            if (repo / path).is_file():
                screens.add(path)
            continue
        if not path.endswith("/"):
            continue
        directory = repo / path
        if not directory.is_dir():
            continue
        for dart_file in directory.rglob("*_screen.dart"):
            screens.add(dart_file.resolve().relative_to(repo_root).as_posix())
    return sorted(screens)


def _screen_pins(repo: Path, screens, keep, require=None) -> dict[str, list[str]]:
    """képernyő → az őt PINNELŐ tesztek, a `keep(relative)` szűrő szerint.

    A `require` (képernyő → minta) a KIZÁRÓLAG útvonal-szinten cserélt
    képernyők második mércéje: ott a tesztnek magát az útvonalat is meg kell
    neveznie, különben a builder-átkötés nem érinti (`_route_pin_requirement`).

    A pinnelés MÉRT alakja (E13-R17/H3): a teszt importálja a képernyő
    forrásfájlját ÉS néven nevezi a típusát (`find.byType(LiveScreen)`,
    `expect(..., isA<TunerScreen>())`). A kettős feltétel a hamis riasztás elleni
    mérce: egy puszta import (pl. tranzitív barrel-behúzás) még nem pinnel
    típust, a típusnév önmagában pedig szövegegyezés is lehet.
    """
    if not screens:
        return {}
    test_root = repo / "test"
    if not test_root.is_dir():
        return {}
    repo_root = repo.resolve()
    wanted = {
        screen: (
            "package:strumsight/" + screen[len("lib/") :],
            re.compile(
                r"\b" + re.escape(_dart_type_name_guess(PurePosixPath(screen).stem)) + r"\b"
            ),
        )
        for screen in screens
    }
    pins: dict[str, list[str]] = {}
    for dart_file in sorted(test_root.rglob("*_test.dart")):
        relative = dart_file.resolve().relative_to(repo_root).as_posix()
        if not keep(relative):
            continue
        try:
            source = dart_file.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        for screen, (import_uri, type_pattern) in wanted.items():
            if import_uri not in source or not type_pattern.search(source):
                continue
            route_pattern = (require or {}).get(screen)
            if route_pattern is not None and not route_pattern.search(source):
                continue
            pins.setdefault(screen, []).append(relative)
    return {screen: sorted(found) for screen, found in sorted(pins.items())}


def outside_screen_pins(
    repo: Path, screens, allowed_paths, gate_tests, require=None
) -> dict[str, list[str]]:
    """képernyő → a briefen KÍVÜL élő tesztek, amelyek PINNELIK (S11).

    A MÉRT halt-ok az `allowed_paths` hiánya: ha a teszt nincs a listán, az
    implementer hozzá sem nyúlhat, és a kör H3-ban áll meg (E13-R16/F9,
    E13-R17/H3). Ez a lelet PONTOSAN a listán kívüli pineket sorolja; a listán
    BELÜLI, de nem MÉRT pineket az `unmeasured_screen_pins` (S14) adja.
    """
    return _screen_pins(
        repo,
        screens,
        lambda relative: not covered_by(relative, allowed_paths),
        require,
    )


def unmeasured_screen_pins(
    repo: Path, screens, allowed_paths, gate_tests, require=None
) -> dict[str, list[str]]:
    """képernyő → a briefen BELÜL élő, de a kör kapuján NEM futó pinnelő tesztek.

    MÉRT rés (E15-R09, `docs/LESSONS.md` L593, 2026-09-03): az S11 a listán
    BELÜLI pint lezártnak vette — „hogy bekerül-e a célzott `gate_tests`-be is,
    az a brief szerzőjének mérlegelése". A mérés ezt megcáfolta: az öt migrált
    AI-Tutor képernyőt pinnelő teszt az `allowed_paths`-on volt, a
    `gate_tests`-en NEM, ezért a kör CÉLZOTT kapuja ZÖLDEN ment át azon a fán,
    amit a kör pirosra vitt — a lelet a 15 perces teljes CI-suite-ról érkezett,
    javító körrel.
    """
    return _screen_pins(
        repo,
        screens,
        lambda relative: covered_by(relative, allowed_paths)
        and not covered_by(relative, gate_tests),
        require,
    )


def tracked_directory_prefixes(repo: Path) -> set[str]:
    """A verziókövetett fában TÉNYLEGESEN létező könyvtár-előtagok (S13).

    Szándékosan `git ls-files`, nem lemez-bejárás: a gitignore-olt, generált
    kimenet (`.dart_tool/`, `lib/l10n/app_localizations*.dart`, `build/`) nem
    számít létező szerződésnek, és egy másik kör munkapéldánya sem szennyezheti
    a mérést.
    """
    try:
        listing = subprocess.run(
            ["git", "-C", str(repo), "ls-files"],
            capture_output=True,
            text=True,
            check=False,
        ).stdout
    except OSError:
        return set()
    prefixes: set[str] = set()
    for tracked in listing.splitlines():
        parts = tracked.split("/")
        for index in range(1, len(parts)):
            prefixes.add("/".join(parts[:index]) + "/")
    return prefixes


def nearest_existing_ancestor(prefix: str, tracked_prefixes: set[str]) -> tuple[str, list[str]]:
    """(a legközelebbi LÉTEZŐ ős, a valódi gyerekkönyvtárai) — a javítás anyaga.

    A pre-flight enélkül `find`-dal keresi ki ugyanezt (L497: `find
    lib/features/practice -type d` → `application data domain presentation`),
    ezért a lelet maga adja oda: a javítás így útvonal-csere, nem nyomozás.
    """
    parts = prefix.rstrip("/").split("/")
    for cut in range(len(parts) - 1, 0, -1):
        ancestor = "/".join(parts[:cut]) + "/"
        if ancestor in tracked_prefixes:
            depth = len(parts[:cut])
            children = sorted(
                {
                    candidate.rstrip("/").split("/")[depth]
                    for candidate in tracked_prefixes
                    if candidate.startswith(ancestor)
                    and len(candidate.rstrip("/").split("/")) > depth
                }
            )
            return ancestor, children
    return "", []


def routing_scope_paths(allowed_paths) -> list[str]:
    """Azok az `allowed_paths` elemek, amelyek a ROUTER forrását engedik.

    Mind a könyvtár-előtag (`lib/app/routing/`), mind a konkrét fájl
    (`lib/app/routing/app_router.dart`) idetartozik: a destination-builderek és
    a route-konstansok is itt élnek, és mindkettő elmozdíthatja azt, amit a
    navigációs őrök pinnelnek.
    """
    prefix = ROUTING_SOURCE_DIR.rstrip("/")
    return sorted(
        {
            path
            for path in allowed_paths
            if path.rstrip("/") == prefix or path.startswith(prefix + "/")
        }
    )


def existing_nav_guards(repo: Path) -> list[str]:
    """A fában TÉNYLEGESEN meglévő navigációs őrök.

    A predikátum így a repó mérhető igazságához kötött, nem egy beégetett
    listához: ha az őr valaha átnevezésre kerül, a szabály nem követel
    nemlétező fájlt — de a `NavGuardPredicateMatchesTreeTest` pirosra vált,
    tehát a hiány nem marad némán.
    """
    return [path for path in NAV_GUARD_TESTS if (repo / path).is_file()]


BASE_SHA = re.compile(r"main @ ([0-9a-f]{7,40})\b")
REFERENCED_PATH = re.compile(r"`((?:lib|test)/[A-Za-z0-9_./-]+\.dart)`")
# Hány fájlt soroljon fel az S15 üzenete, mielőtt „…"-tal zár. A lelet a
# pre-flight TEENDŐJE, tehát olvashatónak kell maradnia; a teljes lista a
# `git diff --name-only <sha>..HEAD` paranccsal bármikor előhívható.
DRIFT_LIST_LIMIT = 6
# Az S16 tárgya: a `tool/gen_l10n_segments.dart` GENERÁLT aggregátumai. A
# `lib/l10n/base/` és a `lib/l10n/features/` szegmensek a FORRÁSOK — csak azok
# szerkeszthetők kézzel (ADR 0307 §4).
GENERATED_ARB = re.compile(r"lib/l10n/app_([a-z]{2}(?:_[A-Za-z0-9]+)?)\.arb")


def _git_lines(repo: Path, *arguments: str) -> list[str] | None:
    """`git` kimenet sorokra bontva — `None`, ha a parancs nem futtatható.

    A `None` és az üres lista SZÁNDÉKOSAN különbözik: „nem tudom megmérni"
    (nincs git, sekély klón, ismeretlen SHA) nem ugyanaz, mint „mértem, és
    nincs sodródás" — az előbbi néma, az utóbbi zöld.
    """
    try:
        completed = subprocess.run(
            ["git", "-C", str(repo), *arguments],
            capture_output=True,
            text=True,
            check=False,
        )
    except OSError:
        return None
    if completed.returncode != 0:
        return None
    return [line for line in completed.stdout.splitlines() if line]


def _listed(paths: list[str]) -> str:
    """Olvasható, CSONKÍTOTT fájllista az S15 üzenetébe — a szám mindig teljes."""
    shown = ", ".join(f"`{path}`" for path in paths[:DRIFT_LIST_LIMIT])
    if len(paths) <= DRIFT_LIST_LIMIT:
        return shown
    return f"{shown} és még {len(paths) - DRIFT_LIST_LIMIT}"


def brief_base_sha(text: str, repo: Path) -> str | None:
    """A brief `main @ <sha>` mért alapja, ha a fa ISMERI is azt a commitot."""
    match = BASE_SHA.search(text)
    if match is None:
        return None
    sha = match.group(1)
    if _git_lines(repo, "cat-file", "-t", sha) != ["commit"]:
        return None
    return sha


def referenced_tree_files(text: str, allowed_paths, repo: Path) -> list[str]:
    """A brief által MEGNEVEZETT, a fán létező `lib/`–`test/` fájlok.

    Két forrás uniója, mert a brief kétféleképpen hivatkozik a mért alapra: az
    `allowed_paths` a birtokolt fájlokat sorolja, a §2 „mért tények" pedig
    backtickes útvonalakkal mutat rájuk (gyakran olyanokra is, amiket a kör NEM
    írhat át — épp ezek a legveszélyesebbek, mert a kör feltevése rájuk épül).
    """
    candidates = {path for path in allowed_paths if path.startswith(("lib/", "test/"))}
    candidates.update(REFERENCED_PATH.findall(text))
    return sorted(path for path in candidates if (repo / path).is_file())


def feature_roots(allowed_paths) -> list[str]:
    """A kör által érintett `lib/features/<feature>/` gyökerek."""
    roots = set()
    for path in allowed_paths:
        parts = PurePosixPath(path).parts
        if len(parts) >= 3 and parts[0] == "lib" and parts[1] == "features":
            roots.add(f"lib/features/{parts[2]}/")
    return sorted(roots)


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

    # S10 — a shell-destination navigációs őr (E13-R17/H3 önjavítás, ADR 0112,
    # 2026-08-25). MÉRT ok: az E13-R08 óta a `test/app/navigation/` három őre
    # pinneli, hogy az adaptív shell melyik route-ja melyik képernyő-TÍPUST
    # rendereli — az öt destination (`adaptive_scaffold_test.dart:196–216`), a
    # tizenegy alútvonal-adapter (`:223–235`), a tab-visszaállítás
    # (`tab_state_restoration_test.dart:105,134`) és a tizenegy legacy redirect
    # célja (`legacy_route_redirect_test.dart:156–166`). Egy kör, amelyik a
    # `lib/app/routing/` forrását átírhatja, ezeket a TÍPUS-állításokat
    # bármikor pirosra válthatja — az őrök viszont a kör `allowed_paths`-án
    # kívül élnek, tehát az implementer hozzájuk sem nyúlhat: a kör H3-ban áll
    # meg, és a felvételük az orchestrátornak TÁGÍTÁS (L478).
    #
    # SAJÁT MÉRÉS (az önjavító kör reprodukciója, `/tmp/ss-heal-probe-r17`,
    # `main @ 52df92b3`): a bázis `flutter test test/app/navigation/` → `+33 All
    # tests passed`; a shell HÁROM destination-builderét (`/today`, `/practice`,
    # `/profile`) új hub-képernyőkre átkötve → `+30 -3 Some tests failed`, a
    # három piros cella az `adaptive_scaffold_test.dart` A1-jében (kettő) és a
    # `tab_state_restoration_test.dart`-ban (egy).
    #
    # A SÁV-SZINTŰ kiterjedés (L482 osztály): a Ch13 sáv HÚSZ hátralévő
    # briefjéből egy sem sorolta fel a navigációs őrt, miközben három (R17,
    # R23, R28) a routert is engedi. Körönként javítva ez három külön H3
    # megállás, mindegyik emberi döntést kérve.
    #
    # A HAMIS RIASZTÁS elleni mércék:
    #   * `status == "done"` → néma. A 18 routert engedő briefből 15 már
    #     merge-elt, és 13 még az őr LÉTREJÖTTE (E13-R08) ELŐTT — ezek
    #     visszamenőleges riasztások lennének (ugyanaz az elv, mint az S5/S7
    #     `round_status != "done"` feltételénél);
    #   * az őr LÉTEZÉSE a fában (`existing_nav_guards`) — a szabály nem
    #     követel nemlétező fájlt;
    #   * a fedettség a router SAJÁT `_matches` előtag-szemantikájával mérve
    #     (`covered_by`), tehát a `test/app/navigation/` könyvtár-engedély
    #     ugyanúgy elég, mint a három fájlútvonal.
    #
    # AMIT SZÁNDÉKOSAN NEM SZŰRÜNK: az E13-R16 (`done`) alakját — routert
    # engedett, de nem destination-adaptert írt át, tehát zölden ment át őr
    # nélkül. Egy ilyen kör MA feleslegesen kapná meg a teendőt. Ezt vállaljuk:
    # a hamis riasztás ára két felsorolt teszt-fájl (a `gate_tests`-ben ráadásul
    # színtiszta ERŐSÍTÉS), a hamis negatívé egy teljes H3 halt. A megkülönböztetés
    # (átköti-e a kör valamelyik destination buildert) a brief PRÓZÁJÁBAN él,
    # nem az `allowed_paths`-ban — gépi mércét nem lehet rá kötni.
    routing_paths = routing_scope_paths(metadata.allowed_paths)
    nav_guards = existing_nav_guards(repo)
    round_status_for_s10 = {row[0].upper(): row[2] for row in queue_rows(repo)}.get(
        brief.task_id, ""
    )
    if routing_paths and nav_guards and round_status_for_s10 != "done":
        missing = [
            guard
            for guard in nav_guards
            if not (
                covered_by(guard, metadata.allowed_paths)
                and covered_by(guard, metadata.gate_tests)
            )
        ]
        if missing:
            listed_routing = ", ".join(f"`{path}`" for path in routing_paths)
            listed_missing = ", ".join(f"`{path}`" for path in missing)
            findings.append(
                Finding(
                    "strict",
                    "S10",
                    f"a kör a router forrását engedi ({listed_routing}), de a "
                    f"shell-destination navigációs őr ({listed_missing}) nem szerepel "
                    "egyszerre az `allowed_paths`-ban ÉS a `gate_tests`-ben — ezek az "
                    "őrök route-onként PINNELIK a renderelt képernyő típusát, tehát "
                    "egy destination-builder átkötése pirosra váltja őket, a "
                    "felvételük viszont az orchestrátornak tágítás, azaz H3 (mérve: "
                    "E13-R17 pre-flight, `flutter test test/app/navigation/` +33 → "
                    "+30 -3 három destination átkötésével); vedd fel a "
                    f"`{NAV_GUARD_DIR}` őrt mindkét listára, és a brief mondja ki, "
                    "hogy a jogosultság PONTOSAN a lecserélt adapter típusának "
                    "átírása — cella törlése, `skip`-je vagy gyengítése TILOS. Ha a "
                    "kör bizonyíthatóan egyetlen destination buildert sem köt át, a "
                    "§0.0 mondja ki ezt a mérést",
                )
            )

    # S11 — az örökség-képernyőt PINNELŐ, briefen kívüli tesztek (a Ch13
    # migrációs sáv mért defektje, 2026-08-25). Az S9/S10 két KONKRÉT esetet fed
    # (képernyő-leltár, shell-destination őr), mindkettőt UTÓLAG, HEAL-körben —
    # miközben a hibaosztály általános: egy migrációs kör lecserél egy
    # örökség-képernyőt, amit a fa MÁS pontján élő teszt a TÍPUSÁRA pinnel. Az őr
    # a kör `allowed_paths`-án kívül él, a felvétele az orchestrátornak tágítás
    # (L478) → H3, kör-megállással és emberi döntéssel.
    #
    # MÉRT előzmény: E13-R16/F9 (`ui_inventory_test.dart`, full-gate 32867296946)
    # és E13-R17/H3 (`test/app/navigation/`, +33 → +30 -3) — két egymást követő
    # kör, ugyanaz az osztály, két külön HEAL-kör ára.
    #
    # HAMIS RIASZTÁS elleni mércék, az S10 mintájára:
    #   * `status == "done"` → néma (visszamenőleges riasztás tilos);
    #   * csak a fában LÉTEZŐ képernyő számít (`owned_existing_screens`);
    #   * a pinnelés kettős feltétele import ÉS típusnév (`outside_screen_pins`);
    #   * a fedettség a router `_matches` előtag-szemantikájával mérve.
    #
    # A vállalt maradék hamis riasztás ugyanaz, mint az S10-nél: egy csak
    # MÓDOSÍTÓ (nem lecserélő) kör feleslegesen kapja a teendőt. Az ár
    # aszimmetrikus — néhány felsorolt teszt-fájl (a `gate_tests`-ben tiszta
    # erősítés) szemben egy teljes H3 megállással.
    round_status_for_s11 = {row[0].upper(): row[2] for row in queue_rows(repo)}.get(
        brief.task_id, ""
    )
    if round_status_for_s11 != "done":
        # A KIZÁRÓLAG útvonal-szinten cserélt képernyők pin-szűrője: ott a
        # teszt nevezze meg magát az útvonalat is (E16-R02 / 3. H3).
        screen_swap_require = _route_pin_requirement(
            route_level_swapped_screens(repo, metadata.allowed_paths, text),
            file_owned_screens(repo, metadata.allowed_paths),
        )
        pins = outside_screen_pins(
            repo,
            owned_existing_screens(repo, metadata.allowed_paths, text),
            metadata.allowed_paths,
            metadata.gate_tests,
            screen_swap_require,
        )
        if pins:
            detail = "; ".join(
                f"`{screen}` → " + ", ".join(f"`{test}`" for test in tests)
                for screen, tests in pins.items()
            )
            findings.append(
                Finding(
                    "strict",
                    "S11",
                    "a kör olyan MEGLÉVŐ képernyőt írhat át, amelynek a típusát a "
                    f"briefen KÍVÜL élő teszt pinneli ({detail}) — egy migrációs kör "
                    "ezeket pirosra váltja, a felvételük viszont az orchestrátornak "
                    "tágítás, azaz H3 (mérve: E13-R16/F9 full-gate 32867296946, "
                    "E13-R17/H3 `test/app/navigation/` +33 → +30 -3); vedd fel a "
                    "felsorolt teszteket az `allowed_paths`-ba ÉS a `gate_tests`-be, "
                    "és a brief mondja ki, hogy a jogosultság PONTOSAN a lecserélt "
                    "képernyő típusának átírása — cella törlése, `skip`-je vagy "
                    "gyengítése TILOS. Ha a kör a képernyőt bizonyíthatóan nem "
                    "cseréli le, a §0.0 mondja ki ezt a mérést",
                )
            )

    # S12 — a §7 gate-parancs TÜKRÖZZE a `gate_tests`-et (2026-08-25).
    # MÉRT ok, saját hibából: az S11 sáv-szintű eltakarítása a `gate_tests`
    # metaadatot bővítette, a §7-ben ténylegesen FUTTATOTT parancssort viszont
    # nem — a hat brief így olyan kaput ígért, amit sosem futtatott volna. A
    # korpuszon mérve ez nem egyedi baleset: a drift a nyitott briefek harmadát
    # érintette. A metaadat és a futtatott parancs szétcsúszása néma: a
    # `round-gate.sh` a parancssort futtatja, a scope-audit és a CI-terv viszont
    # a metaadatot olvassa, tehát semmi nem hozza össze a kettőt.
    #
    # A szabály `strict`, `done` körre néma (a CI-kapu `--level base`, tehát ez
    # sosem vált pirosra egy lezárt kört), és a hiányt SOROLJA, nem csak jelzi.
    round_status_for_s12 = {row[0].upper(): row[2] for row in queue_rows(repo)}.get(
        brief.task_id, ""
    )
    if metadata.gate_tests and round_status_for_s12 != "done":
        invocations = " ".join(
            match.group(1)
            for match in re.finditer(r"tools/round-gate\.sh([^\n`]*)", text)
            if match.group(1).strip()
        )
        if invocations:
            missing = [gate for gate in metadata.gate_tests if gate not in invocations]
            if missing:
                listed = ", ".join(f"`{gate}`" for gate in missing)
                findings.append(
                    Finding(
                        "strict",
                        "S12",
                        f"a §7 `{GATE_ARTIFACT}` parancsa nem tartalmazza a "
                        f"`gate_tests` minden elemét ({listed}) — a metaadatot a "
                        "scope-audit és a CI-terv olvassa, a kaput viszont a "
                        "PARANCSSOR futtatja, tehát a kettő szétcsúszása néma: a "
                        "brief olyan mércét ígér, amit a kör sosem futtat. Írd át "
                        "a §7 parancsot úgy, hogy tükrözze a `gate_tests` listát",
                    )
                )

    # S13 — az `allowed_paths` NEM LÉTEZŐ könyvtár-előtagjai ([L497](../../docs/LESSONS.md#l497)).
    # MÉRT, KÉTSZER visszatért hibaosztály (E13-R22 és E13-R23 pre-flightja): a
    # brief olyan könyvtárakat sorolt fel, amelyek a fán nem léteznek — az
    # E13-R22 esetében `lib/features/practice/{results,history,speed_builder}/`,
    # miközben a feature `application/data/domain/presentation` rétegzésű. A
    # lista így NULLA létező fájlt fedett: a kör egyetlen engedélyezett fájlon
    # sem dolgozhatott volna, a migrálandó `PracticeResultScreen` pedig kívül
    # esett rajta. A `brief-lint --level strict` mindkétszer „nincs lelet"-et
    # adott.
    #
    # Miért volt néma: az S9/S11/S12 mind a fán TALÁLT állapotból indul (leltár,
    # típus-pin, gate-parancs), tehát egy útvonal, ami semmire sem illeszkedik,
    # egyik predikátumot sem aktiválja. A hiány nem a szabályok gyengesége,
    # hanem egy hiányzó, triviális ELŐ-ellenőrzés: létezik-e egyáltalán, amit a
    # lista felsorol.
    #
    # A lelet a javítás ANYAGÁT is odaadja (legközelebbi létező ős + a valódi
    # gyerekkönyvtárai), mert a pre-flight enélkül `find`-dal keresi ki
    # ugyanezt. A szabály KIZÁRÓLAG könyvtár-előtagra lő: egy `*.dart`
    # fájlútvonal hiánya lehet a kör ÚJ fájlja (azt az S5 méri a
    # típusnév-ütközésre), egy nemlétező KÖNYVTÁR viszont a scope-audit
    # szemantikájában nulla fájlt fed.
    #
    # `strict`, `done` körre néma — a CI-kapu `--level base`, tehát ez sosem
    # vált pirosra egy lezárt kört.
    round_status_for_s13 = {row[0].upper(): row[2] for row in queue_rows(repo)}.get(
        brief.task_id, ""
    )
    if round_status_for_s13 != "done":
        tracked_prefixes = tracked_directory_prefixes(repo)
        if tracked_prefixes:
            phantom = [
                path
                for path in metadata.allowed_paths
                if path.endswith("/")
                and (path.startswith("lib/") or path.startswith("test/"))
                and path not in tracked_prefixes
            ]
            if phantom:
                details = []
                for path in phantom:
                    ancestor, children = nearest_existing_ancestor(path, tracked_prefixes)
                    if ancestor:
                        listed = ", ".join(f"`{child}`" for child in children[:8]) or "(üres)"
                        details.append(
                            f"`{path}` — a legközelebbi LÉTEZŐ ős `{ancestor}`, "
                            f"valódi gyerekei: {listed}"
                        )
                    else:
                        details.append(f"`{path}` — a fában egyetlen őse sem létezik")
                findings.append(
                    Finding(
                        "strict",
                        "S13",
                        "az `allowed_paths` olyan KÖNYVTÁR-előtagot sorol fel, ami a "
                        "verziókövetett fában nem létezik, tehát NULLA fájlt fed "
                        + "; ".join(details)
                        + " — mérve KÉTSZER (E13-R22, E13-R23 pre-flight, "
                        "[L497](../LESSONS.md#l497)): a lista így néma ellentmondás, "
                        "és a lint zöldje semmit nem bizonyít. Cseréld az útvonalat a "
                        "fán MÉRT rétegre (a csere szigorúan KEVESEBBET adjon, mint a "
                        "szomszéd kör user-jóváhagyott listája — a tágítás H3, L478), "
                        "vagy a §0.0 mondja ki, hogy a könyvtárat EZ a kör hozza létre",
                    )
                )

    # S14 — a briefen BELÜL élő, de a kör kapuján NEM futó pinnelő teszt
    # (E15-R09, `docs/LESSONS.md` L593, 2026-09-03).
    #
    # Az S11 a listán BELÜLI pint szándékosan lezártnak vette: „hogy bekerül-e a
    # célzott `gate_tests`-be is, az a brief szerzőjének mérlegelése, nem
    # lint-kérdés". A mérés ezt MEGCÁFOLTA. Az E15-R09 öt AI-Tutor képernyőt
    # cserélt le; az őket pinnelő tesztek az `allowed_paths`-on voltak, a
    # `gate_tests`-en NEM — a kör CÉLZOTT kapuja ezért ZÖLDEN ment át azon a fán,
    # amit a kör pirosra vitt. A lelet a 15 perces teljes CI-suite-ról érkezett,
    # javító kör árán. Ugyanaz a hibaosztály, mint az L592-é: amit csak a teljes
    # CI mér, arról a jelzés MINDIG későn jön.
    #
    # HAMIS RIASZTÁS elleni mércék, az S11-ével azonosak: `status == "done"` →
    # néma; csak a fában LÉTEZŐ képernyő számít; a pinnelés kettős feltétele
    # import ÉS típusnév; a fedettség a router `_matches` előtag-szemantikájával.
    round_status_for_s14 = {row[0].upper(): row[2] for row in queue_rows(repo)}.get(
        brief.task_id, ""
    )
    if round_status_for_s14 != "done":
        # A KIZÁRÓLAG útvonal-szinten cserélt képernyők pin-szűrője: ott a
        # teszt nevezze meg magát az útvonalat is (E16-R02 / 3. H3).
        screen_swap_require = _route_pin_requirement(
            route_level_swapped_screens(repo, metadata.allowed_paths, text),
            file_owned_screens(repo, metadata.allowed_paths),
        )
        unmeasured = unmeasured_screen_pins(
            repo,
            owned_existing_screens(repo, metadata.allowed_paths, text),
            metadata.allowed_paths,
            metadata.gate_tests,
            screen_swap_require,
        )
        if unmeasured:
            detail = "; ".join(
                f"`{screen}` → " + ", ".join(f"`{test}`" for test in tests)
                for screen, tests in unmeasured.items()
            )
            findings.append(
                Finding(
                    "strict",
                    "S14",
                    "a kör olyan MEGLÉVŐ képernyőt írhat át, amelynek a típusát a "
                    f"brief SAJÁT `allowed_paths`-án élő teszt pinneli ({detail}), de "
                    "ez a teszt NINCS a `gate_tests`-ben — a kör célzott kapuja így "
                    "zölden megy át azon a fán, amit a kör pirosra visz, és a lelet "
                    "csak a teljes CI-suite-ról érkezik, javító kör árán (mérve: "
                    "E15-R09, [L593](../LESSONS.md#l593)); vedd fel a felsorolt "
                    "teszteket a `gate_tests`-be ÉS a §7 gate-parancsba (az S12 ezt "
                    "külön méri). Ha a kör a képernyőt bizonyíthatóan nem cseréli le, "
                    "a §0.0 mondja ki ezt a mérést",
                )
            )

    # S15 — az ELŐRE MEGÍRT brief mért alapja azóta ELMOZDULT (E14-R10 / H3,
    # [L636](../LESSONS.md#l636)). MÉRT ok: az E14-R10 briefje 2026-08-20-án,
    # `main @ 88e08e65`-en készült, és egy ÚJ irány-abstention kaput írt elő
    # (margó 0,150, elfogadás-oldalon inkluzív) — miközben 2026-09-04-én
    # ugyanez a döntés MERGE-ELVE landolt az E14-R04 / ADR 0505 szerződésében
    # (`StrumPrediction.decision`, 0,05, ELUTASÍTÁS-oldalon inkluzív). A kör
    # célja így csak a brief tilos zónáján KÍVÜL volt teljesíthető: H3, egy
    # teljes orchestrátor-session árán, a dispatch előtt.
    #
    # Miért volt néma: az S9–S14 mind a brief és a JELEN fa viszonyát méri,
    # tehát egy önmagában konzisztens, csak ELAVULT brief mindet kielégíti. A
    # brief maga előírja a pre-flightot („olvasd újra … eltérésnél §0.0
    # revízió"), de ezt eddig csak FEGYELEM tartotta be — a szabály ebből
    # mércét csinál (ugyanaz a lépés, mint az S12-nél: gépi őr kell rá).
    #
    # A predikátum a brief SAJÁT hivatkozási felületére szűkít (birtokolt +
    # §2-ben megnevezett fájlok), és KÜLÖN jelzi a feature-gyökerek alatt
    # landolt ÚJ fájlokat — az E14-R10-et pontosan ez a második jel fogta volna
    # meg: a szerződés ÚJ fájlként érkezett, nem a megnevezettek módosításaként.
    # `strict`, `done` körre néma, és mérés hiányában (nincs git, sekély klón,
    # ismeretlen SHA) szintén néma — a CI-kapu `--level base`, tehát ez sosem
    # vált pirosra egy lezárt kört.
    round_status_for_s15 = {row[0].upper(): row[2] for row in queue_rows(repo)}.get(
        brief.task_id, ""
    )
    base_sha = brief_base_sha(text, repo) if round_status_for_s15 != "done" else None
    if base_sha is not None:
        referenced = referenced_tree_files(text, metadata.allowed_paths, repo)
        drifted = (
            _git_lines(repo, "diff", "--name-only", f"{base_sha}..HEAD", "--", *referenced)
            if referenced
            else []
        ) or []
        roots = feature_roots(metadata.allowed_paths)
        landed = (
            _git_lines(
                repo,
                "diff",
                "--name-only",
                "--diff-filter=A",
                f"{base_sha}..HEAD",
                "--",
                *roots,
            )
            if roots
            else []
        ) or []
        if drifted or landed:
            parts = []
            if drifted:
                parts.append(
                    f"a hivatkozott fájljai közül {len(drifted)} MÓDOSULT "
                    f"({_listed(drifted)})"
                )
            if landed:
                parts.append(
                    f"a kör feature-gyökerei alatt {len(landed)} ÚJ fájl landolt "
                    f"({_listed(landed)})"
                )
            findings.append(
                Finding(
                    "strict",
                    "S15",
                    f"a brief a `main @ {base_sha}` állapotra hivatkozik mért alapként, "
                    f"de azóta {' és '.join(parts)} — a §2 „mért tények” és a rájuk "
                    "épülő acceptance-cellák tehát ELAVULTAK lehetnek, és egy időközben "
                    "MERGE-ELT szerződés ugyanarra a döntésre már megszülethetett "
                    "(mérve: E14-R10 / H3, [L636](../LESSONS.md#l636) — a kör egy ÚJ "
                    "kaput írt elő egy két héttel korábban választott küszöbbel, "
                    "miközben a döntés már élt máshol, más értékkel és más "
                    "inkluzivitással). Olvasd újra a felsorolt fájlokat, és a §0.0 "
                    "revízió mondja ki a mérést: mi maradt igaz, mi nem, és hol van a "
                    "kör EGYETLEN döntési helye",
                )
            )

    # S16 — az `allowed_paths` a GENERÁLT l10n-aggregátumot engedi, a FORRÁS
    # szegmenst nem (E14-R13 / H3, ADR 0112 önjavító kör, 2026-09-05).
    #
    # MÉRT ok: az E14-R13 briefje `lib/l10n/app_{en,hu}.arb`-ot sorolt fel a négy
    # ok-szöveghez. Ezek viszont a `tool/gen_l10n_segments.dart` GENERÁLT
    # aggregátumai (ADR 0307 §4, `GENERATED-FILE-MARKER` a fájl fejlécében): a
    # forrás a `lib/l10n/base/app_<locale>.arb` szegmens (Live-kulcsokra mérve:
    # `grep -l '"liveWeakSignal"' lib/l10n/app_en.arb lib/l10n/base/app_en.arb`
    # MINDKETTŐT adja). A kör tehát a saját listáján belül nem tudott volna
    # kulcsot felvenni: minden kézzel írt aggregátum-diff a `--check` módban
    # elavul, a forrás pedig a TILOS zónában volt. A feloldás lista-TÁGÍTÁS,
    # ami nem az orchestrátor hatásköre → H3, a dispatch előtt.
    #
    # Miért volt néma a többi szabály: az S13 csak nemlétező KÖNYVTÁR-előtagra
    # lő (ezek a fájlok léteznek), az S5 új `.dart` fájl típusnevére, az S11/S14
    # tesztekre, az S15 pedig a mért alap elmozdulására — egy önmagában
    # konzisztens, csak FORRÁS NÉLKÜLI l10n-lista mindet kielégíti. A hiány egy
    # triviális kétirányú ellenőrzés: aki a generált uniót írhatja, írhassa azt
    # is, amiből az union készül.
    #
    # `strict`, `done` körre néma — a CI-kapu `--level base`, tehát ez sosem vált
    # pirosra egy lezárt kört.
    round_status_for_s16 = {row[0].upper(): row[2] for row in queue_rows(repo)}.get(
        brief.task_id, ""
    )
    if round_status_for_s16 != "done":
        orphan_locales = []
        for locale in sorted(
            {
                match.group(1)
                for match in (
                    GENERATED_ARB.fullmatch(item) for item in metadata.allowed_paths
                )
                if match
            }
        ):
            base_source = f"lib/l10n/base/app_{locale}.arb"
            fragment = re.compile(rf"^lib/l10n/features/[^/]+_{re.escape(locale)}\.arb$")
            has_source = any(
                item == base_source
                or fragment.fullmatch(item)
                or item in {"lib/l10n/", "lib/l10n/base/", "lib/l10n/features/"}
                for item in metadata.allowed_paths
            )
            if not has_source:
                orphan_locales.append((locale, base_source))
        if orphan_locales:
            details = "; ".join(
                f"`lib/l10n/app_{locale}.arb` → a forrása `{source}` "
                f"(vagy egy `lib/l10n/features/<feature>_{locale}.arb` fragmentum)"
                for locale, source in orphan_locales
            )
            findings.append(
                Finding(
                    "strict",
                    "S16",
                    "az `allowed_paths` a GENERÁLT l10n-aggregátumot engedi, a FORRÁS "
                    "szegmensét viszont nem: " + details + " — a `lib/l10n/app_*.arb` "
                    "fájlokat a `tool/gen_l10n_segments.dart` írja (ADR 0307 §4), "
                    "kézzel szerkeszteni tilos, és a `--check` mód a frissességüket "
                    "kapuzza, tehát a kör a saját listáján belül EGYETLEN kulcsot sem "
                    "tud felvenni (mérve: E14-R13 / H3 a dispatch előtt, "
                    "[L646](../LESSONS.md#l646)). Vedd fel a forrás-szegmenst az "
                    "`allowed_paths`-ba (a generált aggregátum MARADJON rajta, mert a "
                    "generátor kimenete a diffben megjelenik), és a §8 sorrend mondja "
                    "ki, hogy a kulcsfelvétel UTÁN `dart run tool/gen_l10n_segments.dart "
                    "--write` fut a gate ELŐTT",
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
