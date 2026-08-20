# E99-R18 (GOV-12) — Generált `public.dart` barrelek: a második fizikai ütközés-felület feloldása

- **Státusz:** READY FOR IMPLEMENTATION (pre-flight revised 2026-08-19, `main @ 1a051d85`)
- **Típus:** **governance-kör**
- **Kör-azonosító:** `E99-R18`. Emberi neve **GOV-12**.
- **Előfeltétel:** nincs technikai előfeltétel. Az E99-R17 emberi gate-holdon
  van; a jelen kör a saját `tools/round-slots.py`-módosításával vezeti be a
  public-barrel generált-útvonal kezelését.
- **Brief szerzője:** Claude (Opus 5, orchesztrátor) · **ADR:** [`0307`](../adr/0307-pipeline-throughput-program-v2.md) **§5**

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "tool/gen_public_barrel.dart",
  "tool/check_architecture.dart",
  "lib/features/practice_generator/public.dart",
  "lib/features/practice_generator/public/",
  "tools/round-slots.py",
  "tools/tests/test_round_slots_generated_barrels.py",
  "test/tooling/gen_public_barrel_test.dart",
  "test/core/architecture_dependency_test.dart",
  "docs/rounds/e99-r18-gov-12-generated-public-barrels.md",
]
gate_tests = [
  "test/tooling/gen_public_barrel_test.dart",
  "test/core/architecture_dependency_test.dart",
]
native_gate = false
```

> **Kockázat = high, indoklás:** a `public.dart` a feature-ek közötti
> KONTRAKTUS (SDD Ch8, ARCH-szabályok); egy elveszett export néma
> fordítási hibaként vagy — rosszabb — egy másik szimbólum árnyékolásaként
> jelentkezne. A mérce ezért az export-halmaz azonossága.

## 0.0 Pre-flight revízió (önjavítás, ADR 0112, 2026-08-19, `main @ 1a051d85`)

**Végrehajthatósági eredmény: a H3 halt oka NEM tartalmi hiányosság, hanem
igazoltan ártalmatlan implementer-debris — a feloldás REVERT, nem
`allowed_paths`-bővítés.**

### Mért tények

A MiniMax implementer (`/home/ubuntu/ss-minimax-e99-r18`, ág
`minimax/e99-r18-gov-12-generated-public-barrels`, HEAD `e9c4a26b`) a
fenti `allowed_paths`-on BELÜLI, öt commitban felépített D1/D2/D4 munkája
(a jelenlegi, commitolatlan diffben mérve hat fájl: a négy
`practice_generator/public/*.dart` fragmentum, `test/tooling/
gen_public_barrel_test.dart`, `tool/gen_public_barrel.dart`) MELLETT három
NYOMKÖVETETLEN (untracked) fájlt hagyott a munkapéldányban:

```
test_project/lib/features/demo/public.dart
test_project/lib/features/demo/public/application.dart
test_project/lib/features/demo/public/domain.dart
```

Ez a saját scope-audit-ja (`tools/scope-audit.py`, `.codex-round-status`)
szerint is sértés (`scope_audit=VIOLATION`,
`scope_audit_base=6a6344a07d2fcfcebeb4916e43179b110ea9b7d9`, a base-től az
öt commitot is számoló `scope_audit_changed=14`, ebből 3 a violation); az
implementer MAGA is `stopped`-ot jelzett (`implementer_status=stopped`) —
tehát a modell is észlelte, hogy valami kilóg. A Terra orchesztrátor-session
(`pipeline-E99-R18-fallback`) ezt követően `H3`-mal állt le,
`.pipeline/HALTED`-ben rögzítve: „A new brief-revision/human decision is
required before any continuation."

**A `test_project/` NEM legitim munka — ez mérve van, nem feltételezve:**

- `grep -rn "test_project" .` a teljes munkapéldányban (a stopped
  implementer worktree-jén) **nulla** találatot ad bármely tracked vagy
  untracked Dart/Python/shell forrásban — semmi nem hivatkozik rá, semmi nem
  generálja.
- A `test/tooling/gen_public_barrel_test.dart` SAJÁT, automatizált
  fixture-je már helyesen `Directory.systemTemp.createTempSync
  ('strumsight_public_barrel_')`-t használ (a fájl `setUp`/`tearDown`-ja) —
  a `test_project/` tehát funkcionálisan redundáns ezzel a fixture-rel.
- A `test_project/lib/features/demo/public.dart` +
  `public/{application,domain}.dart` tartalma **bájtra megegyezik** a fenti
  automatizált teszt `seedFreshBarrel()` segédfüggvénye által memóriában
  felépített fixture-tartalommal (`export '../application/port/a.dart';`
  stb.) — ez egy kézi, a repó fájlrendszerén kívülre nem szánt smoke-teszt
  lenyomata, nem egy elfelejtett deliverable.
- A brief D1–D4 feladatai és az 5. „Tilos zóna" (kizárólag a
  `practice_generator` barrel migrálható) egyike sem nevez meg semmilyen
  `demo`/`test_project` scaffoldot.

### Kötelező feloldás

`docs/execution/pipeline-orchestrator-prompt.md` VIOLATION-sorát idézve: „a
listán kívüli fájlokat **vissza kell állítani**, vagy H3 halt" — és ugyanott
a §2 „Önállóan dönthetsz és folytathatod a kört" felsorolása kifejezetten
tartalmazza „az engedélyezett-fájllista **szűkítését**" mint a kör saját
hatáskörét. A `test_project/` TÖRLÉSE (nem allow-listázása) éppen ez az
eset: a diffet az EREDETI `allowed_paths`-hoz igazítja, nem a tiltott zóna
feloldását kéri — tehát nem H3-t igénylő döntés, hanem a §2 alatt már
felhatalmazott revert. A fenti `ai-router` blokk **változatlan**: a
`test_project/`-hez (vagy bármely `demo`/scratch mintához) **nem** kerül
`allowed_paths`-bejegyzés.

A folytatás módja: a megállt implementer-worktree
(`/home/ubuntu/ss-minimax-e99-r18`) törölje a három fájlt, majd a hat,
ÉRDEMI, scope-on belüli fájl (D1/D2/D4 munka) a szokásos módon megy tovább
review/gate felé. Ezt a self-heal SZÁNDÉKOSAN nem hajtja végre saját kézzel
— a self-heal jogosultsága (ADR 0112 §2) a briefre és az
engedélyezett-fájllistára szól, nem a kör saját, még nem review-zott
implementer-ágára; a következő E99-R18 dispatch (friss
orchesztrátor-session) dolga eldönteni, hogy a meglévő worktree-t
újrahasznosítja-e (a törlés után) vagy frissen indul.

**Miért nem illik ide az E07-R29/H3 minta** (`tools/tests/
test_e07_r29_accessibility_privacy_scope.py`): ott a listán kívüli fájlok
IGAZOLTAN szükséges, meglévő storage-tulajdonosok voltak — a helyes
feloldás `allowed_paths`-bővítés volt. Itt a mérés az ELLENKEZŐJÉT mutatja
(nulla hivatkozás, redundáns az automatizált fixture-rel, kívül esik minden
D1–D4 cellán) — a helyes feloldás ezért a bővítés tükörképe: **revert, és
az allowlist érintetlenül hagyása**. A self-heal jelentése ezt a döntést a
regressziós teszttel (`tools/tests/test_e99_r18_scope_debris_revert.py`)
gépileg is rögzíti, mindkét irányban (a debris VIOLATION marad, amíg jelen
van; az allowlist nem bővül).

Lecke: `docs/LESSONS.md` [[L337]]. ADR: [`0112`](../adr/0112-self-healing-pipeline.md)
Módosítás (2026-08-19).

## 0.0b Pre-flight revízió (önjavítás, ADR 0112, H8, 2026-08-20, `main @ b1bab82a`)

**Mért tény.** Az E99-R17 (GOV-11) idő közben zöld kapuval `main`-re
merge-elődött (squash `8d7b6a67`, PR #343) — a fenti §0.0 R2 sorának
premisszája („E99-R17 nem merge-elt”) mára hamis. Az `origin/main`
szinkron (`git -C /home/ubuntu/ss-minimax-e99-r18 merge --no-ff
origin/main`) ezért a jelen brief mellett a `tools/round-slots.py`-ban is
tartalmi ütközést adott: az E99-R17 saját, EXACT-SET `GENERATED_PATHS`
frozensetje (`lib/l10n/app_en.arb`, `lib/l10n/app_hu.arb`) és a D4 saját,
GLOB-alapú `GENERATED_PATH_PATTERNS`/`is_generated_path` mechanizmusa
ugyanazt a két kódrészt (a konstans-blokkot és az `effective_paths` szűrő-
predikátumát) módosította.

**Feloldás.** A két mechanizmus additív, egymásnak NEM mond ellent — a
saját, már zöld-tesztelt regressziós csomagjaik (`tools/tests/
test_round_slots_generated_paths.py` az E99-R17, `tools/tests/
test_round_slots_generated_barrels.py` a jelen kör oldaláról) kizárólag a
SAJÁT oldalukat mérik, egyik sem hivatkozik a másikéra. A merge-feloldás
mindkét konstanst megtartja, és az `effective_paths` predikátumát unióvá
bővíti: egy útvonal akkor (és csak akkor) számít generáltnak, ha
`SERIALIZED_PATHS`-ban van, VAGY `GENERATED_PATHS`-ban van, VAGY illeszkedik
egy `GENERATED_PATH_PATTERNS` globra. Mindkét meglévő teszt-csomag
változtatás nélkül zöld marad; egy új, a self-heal által hozzáadott
`tools/tests/test_round_slots_generated_paths_and_patterns_coexist.py`
regressziós teszt méri a KOMBINÁLT esetet (mindkét mechanizmus egyszerre
aktív egyetlen `effective_paths` híváson belül), amit egyik eredeti csomag
sem fedett. A D1–D4 termékcél és a fenti `allowed_paths` VÁLTOZATLAN — a
`tools/round-slots.py` már a listán szerepelt.

**KRITIKUS, a self-heal saját kötelező gate-je által feltárt, NEM javított
lelet — a következő E99-R18 dispatch dolga, review előtt kötelező zárni.**
A teljes `python3 -m pytest tools/tests -q` (605 passed, 2 skipped, 1
FAILED, 565 subtests, ismételve mérve a resolved HEAD-en) egyetlen piros
cellát ad: `tools/tests/test_pipeline_throughput.py::SlotPlanningTest::
test_real_epic_four_rounds_are_correctly_rejected` —
`round_slots.paths_conflict` **üres listát** ad két, VALÓDI, már `done`
Epic-4 brief (`e04-r15-streaming-transport.md`, `e04-r16-orchestration-
state-machine.md`) között, holott a teszt mérve bizonyítja, hogy e két
brief ténylegesen ugyanazt a (nem-practice_generator) `public.dart`-ot
érinti — tehát VALÓDI ütközés, aminek a régi kódon detektálódnia KELLENE.

**Gyökérok (nem a self-heal merge-feloldása — a D4 SAJÁT, pre-merge
kódjában is jelen van):** a fenti `GENERATED_PATH_PATTERNS =
("lib/features/*/public.dart",)` glob SZÁNDÉKOSAN széles (lásd a kör saját
`tools/tests/test_round_slots_generated_barrels.py::
test_pattern_glob_is_not_narrowed_to_a_single_feature` cellát — a szűkítés
explicit TILOS), de ezzel MINDEN feature `public.dart`-ját generáltnak (=
NEM ütköző) minősíti, holott a D1–D3 pilot MÉRVE (§1, R3) kizárólag a
`practice_generator`-t migrálta a fragmentum-alapú, ténylegesen generált
rendszerre — a 75 nyitott brief közül **25** a `lib/features/gamification/
public.dart`-ot, **18** a `lib/core/design_system/public.dart`-ot érinti
(§1), ezek MA MÉG kézzel karbantartott, teljes értékű ütközési felületek.
A broad glob ezért NÉMÁN kikapcsolja az ütközés-detekciót minden nem
migrált feature-re — pontosan a brief saját `Kockázat = high` sora által
jósolt néma hiba, csak nem az export-halmazban, hanem a slot-tervezőben.

**Miért nem javította ezt a self-heal:** a hiba a D4 SAJÁT, review előtti
tervezési döntése (a glob hatóköre), nem a H8 merge-mechanika — az ADR 0112
§2 jogosultsága a briefre/eszközökre szól, nem a kör saját, még nem
review-zott tartalmi munkájára. A helyes feloldás (pl. explicit, migrált-
feature allowlist a blanket glob helyett) termékdöntés, aminek a kör saját
implementer+reviewer ciklusán kell átmennie — NEM egy 1-of-3 önjavító
kísérlet dolga. A self-heal SZÁNDÉKOSAN nem nyúlt `is_generated_path`
viselkedéséhez.

**Kötelező a folytatáshoz:** a következő E99-R18 dispatch (vagy a review)
zárja ezt a cellát — akár a glob szűkítésével egy migrált-feature
allowlistre (és a `test_pattern_glob_is_not_narrowed_to_a_single_feature`
cella ezzel összhangban lévő revíziójával), akár más, mérve bizonyítottan
biztonságos megoldással — MIELŐTT ez a brief review-ra megy. A review saját
gate-je (teljes `pytest tools/tests -q`) ezt a cellát úgyis blokkolná; ez a
feljegyzés csak a felesleges újra-felfedezés költségét spórolja meg.

Lecke: `docs/LESSONS.md` [[L343]]. ADR: [`0112`](../adr/0112-self-healing-pipeline.md)
Módosítás (ADR 0112 önjavító kör, 2026-08-20).

## 0.0c Pre-flight revízió — csak igazoltan generált barrel old fel slot-ütközést (2026-08-20)

**Mérés és döntés.** A §0.0b-ban előírt reprodukciót a jelenlegi kör-ágon
`python3 -m pytest tools/tests/test_pipeline_throughput.py::SlotPlanningTest::test_real_epic_four_rounds_are_correctly_rejected -q`
adja: a széles `lib/features/*/public.dart` glob miatt az E04-R15 és E04-R16
valódi, nem migrált `public.dart`-ütközése eltűnik. Ezzel szemben a
`find lib/features -path '*/public/*.dart' -type f` mérés kizárólag a
`practice_generator/public/{application,data,domain,presentation}.dart`
fragmentumait találja; csak ehhez a feature-höz létezik tényleges, D1 szerinti
generálási bizonyíték.

Ezért a D4 feloldás **nem blanket glob**, hanem explicit, migrált-output
nyilvántartás: ebben a körben kizárólag
`lib/features/practice_generator/public.dart` generált és nem ütköző. Minden
más feature gyökér `public.dart`-ja teljes értékű ütközési felület marad,
amíg a saját körében fragmentumokkal, generátor-frissesség teszttel és
nyilvántartási bejegyzéssel nem bizonyítottan generált. Ez scope-szűkítés a
pilot tényleges bizonyítékához, nem más feature barreljének módosítása.

**Falszifikáció.** A `tools/tests/test_round_slots_generated_barrels.py`
teszt egyszerre méri, hogy (a) két `practice_generator/public.dart` út nem
ütközik, és (b) két másik, nem regisztrált feature `public.dart` út ütközik;
így az első esetben túl szűk, a másodikban túl széles implementáció is piros.
A meglevő `SlotPlanningTest` az E04 valós brief-párján ugyanennek az utóbbi
hibás implementációnak a regressziós őre. A korábbi globot és annak
„nem szűkíthető” tesztcelláját e mért tény felülírja.

**Visszakeresett előzmények.** A pre-flight szűkített RAG-találatai: ADR 0176 (a barrel
contract maga a szabályozott feature-határ), lessons/L133 és lessons/L135
(a brief és a tényleges guard viselkedését együtt kell mérni), valamint
lessons/L343 (ez a pontos D4 túl-széles-glob lelet). A teljes korpusz a
közvetlen kör-briefet és az E99-R18/H8 leletet hozta vissza; ellentétes,
biztonságos precedens nincs. A döntés az ADR 0307 §5 körszintű,
determinista-generálhatósági elvének alkalmazása; új ADR nem szükséges.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. **STOP-protokoll:** listán kívüli fájl →
`stopped` + brief-revízió; az `allowed_paths` tágítása TILOS.

## 1. Cél — mit mértünk

A 75 nyitott briefből a `lib/features/gamification/public.dart` **25**-ben, a
`lib/core/design_system/public.dart` **18**-ban, a
`lib/features/practice_generator/public.dart` **8**-ban szerepel — kizárólag
azért, mert minden kör hozzáfűz egy `export` sort. Ez a második olyan
ütközés-felület (az ARB után), ami mechanikus, nem tartalmi.

A `practice_generator/public.dart` ma **100 sor**, ebből **94** export-direktíva
és két megőrzendő magyarázó komment; a publikus felület ettől még kézzel
karbantartott → ez a
pilot. (A `gamification` és a `design_system` barrel még nem létezik a fán; a
mechanizmus az ő születésükkor már készen áll.)

## 2. Jelenlegi állapot — mérve

- `lib/features/practice_generator/public.dart`: `library;` + **94** `export`
  direktíva, köztük egy `hide PracticeOutcome`, kézzel karbantartva.
- `tool/check_architecture.dart` gate-lépés őrzi a feature-határokat
  (cross-feature import csak `public.dart`-on át).
- `tools/round-slots.py`: csak `SERIALIZED_PATHS` létezik; a D4 itt vezeti be
  a public-barrel glob-alapú generált-útvonal szabályát.

## 3. Feladatok

### D1 — `tool/gen_public_barrel.dart`

- Bemenet: `lib/features/<feature>/public/*.dart` fragmentumok, mindegyik egy
  modul export-sorait tartalmazza (fájlonként egy témakör).
- Kimenet: `lib/features/<feature>/public.dart` — a fragmentumok
  **fájlnév szerint rendezett**, determinisztikus konkatenációja, változatlan
  fejléc-dokumentációval (`/// Public domain contract…` + `library;`).
- `--check` mód: a lemezen lévő barrel egyezik-e a generálttal (kilépési kód 1,
  ha nem).
- **Duplikált export** (ugyanaz az útvonal két fragmentumban) → hiba.

### D2 — A gate méri a frissességet (`tool/check_architecture.dart`)

A meglévő `architecture` gate-lépés kiegészül a `--check` hívással minden
generált barrelre. Új gate-LÉPÉS nem születik, tehát a `round-gate.sh` és a CI
composite lépéslistája változatlan (ADR 0171 paritás-őre sértetlen).

### D3 — Pilot: `practice_generator`

- A mai 60+ export témakörök szerinti fragmentumokra bomlik
  (`public/application.dart`, `public/data.dart`, `public/domain.dart`,
  `public/presentation.dart` — a MAI export-útvonalak könyvtár-előtagja szerint).
- **Acceptance:** a generált barrel **export-halmaza bitre azonos** a
  migráció előttivel (sorrend változhat, halmaz nem).

### D4 — `tools/round-slots.py`: a generált barrel nem ütközés

- A generált-barrel nyilvántartás csak a **bizonyítottan migrált**
  `lib/features/practice_generator/public.dart` outputtal bővül. Blanket
  `lib/features/*/public.dart` glob tilos: a még kézzel karbantartott feature
  barrelek nem regenerálhatók, ezért továbbra is ütköznek.
- A fragmentumok (`lib/features/*/public/*.dart`) TELJES ÉRTÉKŰ ütközési
  felületek maradnak.

## 4. Mérce-mátrix

| eset | bemenet | elvárt |
|---|---|---|
| export-halmaz **azonos** | migráció előtti vs. generált barrel | ZÖLD |
| export **hiányzik** | fixtúra: egy fragmentum kimarad | `--check` **PIROS** |
| export **duplikált** | ugyanaz az útvonal két fragmentumban | a generátor hibával áll meg (kilépési kód ≠ 0) |
| barrel **elavult** | kézi szerkesztés a generált fájlban | `--check` **PIROS** |
| `round-slots.py` | két brief, mindkettő `lib/features/practice_generator/public.dart` | NINCS ütközés |
| `round-slots.py` | két brief, mindkettő `lib/features/x/public.dart` | ÜTKÖZÉS |
| `round-slots.py` | két brief, mindkettő `lib/features/x/public/domain.dart` | ÜTKÖZÉS |

**Falszifikációs cella (kötelező):** a D2 `--check` hívás kiszedése az
`architecture` lépésből → a „barrel elavult" eset **PIROS** helyett zöld lenne,
ezért a `test/tooling/gen_public_barrel_test.dart` erre írt esete **PIROS** →
visszaállítás után zöld. Második falszifikáció: a D4 nyilvántartásának
blanket globra szélesítése → a `SlotPlanningTest` valós E04 brief-párja
**PIROS**; a practice-generator bejegyzés kihagyása → a saját „NINCS
ütközés” cella **PIROS**.

## 5. Tilos zóna

- `docs/adr/**`, `.ai/router.toml`, `docs/execution/pipeline-queue.tsv`,
  `.pipeline/**`, `tools/round-pipeline.sh`.
- **Csak a `practice_generator` barrel migrálható** — más feature barreljéhez
  nyúlni tilos (a mechanizmus bizonyítása a cél).
- A feature-határ szabály (cross-feature import csak `public.dart`-on át)
  NEM lazul: a fragmentumok a feature-en BELÜL élnek, kívülről nem importálhatók.
  Ezt a `test/core/architecture_dependency_test.dart` méri.

## 6. Definition of Done

1. D1–D4 kész; a `practice_generator` barrel generált, export-halmaza változatlan.
2. A §4 mind a hat cellája tesztelt.
3. `tools/round-gate.sh test/tooling/gen_public_barrel_test.dart test/core/architecture_dependency_test.dart` zöld
   (az `architecture` lépés a frissességet is méri).
4. `python3 -m pytest tools/tests -q` zöld.
5. Kör-jelzés `done`.

## 7. Gate

```bash
tools/round-gate.sh test/tooling/gen_public_barrel_test.dart test/core/architecture_dependency_test.dart
python3 -m pytest tools/tests -q
```

A teljes suite (minden `public.dart`-fogyasztó teszttel) + property gate a
CI-ban fut (ADR 0053).
