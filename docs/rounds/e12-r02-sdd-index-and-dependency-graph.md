# E12-R02 — SDD index és dependency graph

- **Státusz:** READY — pre-flight elvégezve 2026-08-28 (`main @ 3467a37e`); előre megírva 2026-08-27 (`main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 2
- **Kör-azonosító:** `E12-R02`
- **Branch:** `<motor>/e12-r02-sdd-index-and-dependency-graph`
- **Előfeltétel:** `E12-R01` merge-elve (a baseline adja az index `implementation progress` oszlopának bizonyítékait)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0443` — a szám FOGLALT (Chapter 12 batch-tartomány: `0443`–`0465`, driftre számítva).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "SDD index dependency graph chapter status validation tool"` → nincs közvetlenül releváns előzmény (a találatok — ADR 0068, ADR 0194 — más domain contractjai); a minta-forrás ezért a repó SAJÁT, működő ellenőrző-eszköze, a `tool/check_architecture.dart` + `test/tooling/architecture_allowlist_guard_test.dart` pár.

## 0.0.A Pre-flight — MÉRT tények (orchestrátor, 2026-08-28, `main @ 3467a37e`)

A pre-flight elvégezve; az alábbi hét mérés a brief kötelező bemenete. Ahol a
PREPARED szöveg mást állított, **ez a szakasz az irányadó**.

### P1 — Kör-fejléc-számlálás MINDEN fejezet-fájlra

```
$ for f in docs/sdd/*.md; do echo "$f h1=$(grep -cE '^# Kör [0-9]+' "$f") h2=$(grep -cE '^## Kör [0-9]+' "$f")"; done
```

| Chapter | Fájl | `# Kör` | `## Kör` | Mért összeg | Index ma | Egyezik? |
|---:|---|---:|---:|---:|---|:--:|
| 1 | `01-architecture-engineering-principles.md` | 0 | 0 | **0** | `—` | ✅ |
| 2 | `02-epic-01-core-platform.md` | 16 | 0 | **16** | 16 | ✅ |
| 3 | `03-epic-02-practice-engine.md` | 20 | 0 | **20** | `20 (lezárva …)` | ✅ |
| 4 | `04-epic-03-song-trainer.md` | 22 | 0 | **22** | `22 — implementation …` | ✅ |
| 5 | `05-epic-04-ai-guitar-teacher.md` | 24 | 0 | **24** | 24 | ✅ |
| 6 | `06-epic-05-computer-vision.md` | 30 | 0 | **30** | 30 | ✅ |
| 7 | `07-epic-06-audio-analysis-2.md` | 30 | 0 | **30** | `30 — implementation …` | ✅ |
| 8 | `08-epic-07-ai-practice-generator.md` | 30 | 0 | **30** | 30 | ✅ |
| 9 | `09-epic-08-gamification.md` | 30 | 0 | **30** | 30 | ✅ |
| 10 | `10-epic-09-community-platform.md` | 32 | 0 | **32** | 32 | ✅ |
| 11 | `11-epic-10-offline-ai.md` | 32 | 0 | **32** | 32 | ✅ |
| 12 | `12-release-roadmap-final-integration.md` | 36 | 0 | **36** | **42** | ❌ |
| 13 | `13-chapter-13-ui-ux-design-system.md` | 36 | 0 | **36** | 36 | ✅ |
| 14 | `14-chapter-14-recognition-ui-recovery.md` | 0 | 42 | **42** | 42 | ✅ |

**A PREPARED állítás megerősítve:** a Chapter 12 az EGYETLEN eltérés (42 → **36**),
és a Chapter 14 az EGYETLEN `## Kör` alakú fejezet. Az A3 cella értéke
változatlan; a kör **egyetlen** szám-javítást hoz, nem tömeges átírást.

### P2 — Az index-tábla cellaszáma NEM egységes (a parser kötelező elvárása)

```
$ awk 'NR>=15 && NR<=28' docs/sdd/00-index.md | awk -F'|' '{print $2, NF-2}'
```

- **6 cella** (a `Zárójelentés` oszloppal): Chapter 1, 2, 3, 4, 7
- **5 cella** (a `Zárójelentés` oszlop LEHAGYVA): Chapter 5, 6, 8, 9, 10, 11, 12, 13, 14

A fejléc 6 oszlopot deklarál. A parser **nem** feltételezhet fix cellaszámot: a
hiányzó, záró `Zárójelentés` cellát üresként kell kezelnie — különben a 14
sorból 9-en ma elhasal.

### P3 — A körszám-cella NEM tiszta egész szám

Négy soron próza vagy jel áll a szám helyén/után:

| Chapter | A cella nyers tartalma |
|---:|---|
| 1 | `—` (em-dash — nincs kör; a mért fejléc-szám **0**) |
| 3 | `20 (lezárva E02-R20, 2026-08-01)` |
| 4 | `22 — implementation evidence recorded; release blockers remain` |
| 7 | `30 — implementation evidence recorded; rollout stays at shadow, release blockers remain` |

A parser a **vezető egész számot** olvassa ki, az `—` értéket pedig „nincs kör"
(elvárt fejléc-szám: 0) jelentéssel kezeli. A prózai utótagot érintetlenül kell
hagynia — az index szövegének megőrzése a kör scope-ján kívül van.

### P4 — `package:yaml` NEM használható (ADR 0443 D3)

```
$ grep -nE "^\s*(yaml|yaml_edit):" pubspec.yaml     # NINCS TALÁLAT
$ grep -nA3 '^  yaml:' pubspec.lock
1261:  yaml:
1262-    dependency: transitive
```

A `yaml` csak **transitive** dependency, a `pubspec.yaml`-ben nincs deklarálva. Az
`analysis_options.yaml:10` `package:flutter_lints/flutter.yaml`-t include-ol, ami
tartalmazza a `depend_on_referenced_packages` szabályt → egy
`import 'package:yaml/yaml.dart'` **pirosra váltaná a `flutter analyze`-t (H7)**.
A `pubspec.yaml` az `allowed_paths`-on **kívül** van, tehát a dependency
deklarálása **H3**.

**Következmény:** a `dependency-graph.yaml` egy szándékosan **szűkített
YAML-részhalmaz**, amit a checker saját, sor-alapú, hibára beszédes parserrel
olvas. A szűkített alakot a manifest fejléc-kommentjében és a checker
hibaüzenetében ki kell mondani.

### P5 — A checker magja legyen tesztelhető, gyökér-paraméteres (ADR 0443 D4)

A repó saját mintája:

```dart
// test/tooling/architecture_allowlist_guard_test.dart
import '../../tool/check_architecture.dart';
```

A teszt **relatív importtal** éri el a tool top-level szimbólumait. Az A1/A2/A4
cellák hibás bemenetekre mérnek (duplikált fejezet, nem létező hivatkozás,
ciklikus graph), amiket a repó valódi tartalmán nem lehet előállítani — ezért a
checker top-level, **gyökér- vagy tartalom-paraméteres** függvényeket exportál,
és a `main()` csak vékony, `exitCode`-ot állító burkoló.

### P6 — A hivatkozás-ellenőrzés EGYIRÁNYÚ (ADR 0443 D6)

Az index mind a 18 hivatkozott `.md` fájlja **létezik** (mérve). A `docs/sdd/`-ben
viszont **nyolc** `epic-NN-completion-report.md` van, az index **négyet** linkel
(01, 02, 03, 06). Az A2 cella tehát a `hivatkozás → létező fájl` irányt méri; a
fordított irányt (minden fájl legyen hivatkozva) **NEM** követeljük meg — az
tartalmi döntés a zárójelentések státuszáról, külön kör tárgya.

### P7 — Javított/aktualizált számok a PREPARED szöveghez képest

| Állítás a PREPARED briefben | MÉRT valóság |
|---|---|
| `tool/check_architecture.dart` **786** sor | **850** sor (`wc -l`) |
| Előre kiosztott ADR: `0443` | **`0443` marad** — lásd lent |
| `docs/sdd/dependency-graph.yaml` nem létezik | megerősítve (`ls` → `No such file`) |
| `tool/check_sdd_index.dart` nem létezik | megerősítve |

**ADR-szám — mért ütközés a foglaló és a commitolt queue között.** A
`tools/round-slots.py reserve-adr --round E12-R02` **`0432`**-t adott (a lemezen a
legnagyobb ADR `0426`), a commitolt `docs/execution/pipeline-queue.tsv` viszont
az E12 sáv EGÉSZÉRE előre kiosztott tartományt hordoz: `E12-R02 → 0443`,
`E12-R03 → 0444`, … `E12-R34 → 0465` (22 sor). A foglaló célja a NÉMA ütközés
kizárása; `0443` a lemezen és a foglaló vízjelénél is szabad, tehát ütközni nem
tud, viszont a `0432` elfogadása a 22 downstream kör kiosztását bontaná meg.
**Döntés: `0443`**, a commitolt program-szintű kiosztás szerint. (A foglaló nem
idempotens — az ellenőrző második hívás `0433`-at adott; a `0432`/`0433` markerek
felhasználatlanul maradnak. A számhézag ártalmatlan: a
`tools/tests/test_adr_numbering.py` duplikátumot mér, nem hézagot.)

### Visszakeresés (ADR 0312 §4.9)

```
node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "SDD index fejezet tábla körszám ellenőrző dependency graph"
node tools/knowledge-rag.mjs --corpus lessons,halts --top 5 "markdown tábla parse ellenőrző dart tool guard teszt fixture"
node tools/knowledge-rag.mjs --corpus lessons,halts --top 5 "dokumentáció és kód szétcsúszása gépi ellenőrzés dokumentum konzisztencia"
node tools/knowledge-rag.mjs --top 5 "SDD index 00-index.md fejezet tábla kör fejléc számlálás check_sdd_index.dart dependency-graph.yaml"
```

- **Nincs közvetlenül releváns előzmény** erre a domainre (a szűkített találatok
  — ADR 0246/0238/0253/0218 — más domain contractjai).
- **Releváns, átvitt lecke:** [L476](../LESSONS.md#l476) — *„a sor-alapú
  forrás-guard szerkezetileg vak arra az alakra, amit a projekt formázója
  előállít"*. Ez a kör **kétszeresen** sor-alapú parsert ír (Markdown-tábla +
  szűkített YAML), tehát a mérce-mátrix (§6.1) és a valódi-sértés próba (§6)
  KÖTELEZŐ: a zöld gate önmagában nem bizonyíték. A `docs/` és `docs/sdd/`
  Markdownját a `dart format` nem érinti, ezért az L476 konkrét mechanizmusa itt
  nem áll fenn — a hibaosztály (sor-alapú guard vakfoltja) viszont igen.
- **Releváns, átvitt lecke:** [L116](../LESSONS.md#l116) — *„az ellenőrzéshez
  szükséges adat megvolt, az ellenőrzés hiányzott"*. Pontosan ez a kör kiváltó
  oka: a körszámok mérhetőek voltak, csak senki nem kötötte be a mérést.

## 0.0 A kör MÉRT kiváltó oka

Az index tábla és a fejezet-fájlok szétcsúsztak: a Chapter 12 sora 42 kört ígér, a fájl 36-ot tartalmaz. A footnote ma ezt szövegesen kezeli („végrehajtáskor a fájl tartalma az irányadó"), ami pontosan az a hibaosztály, amit ez a kör gépi ellenőrzésre cserél: a prózai mentesítés nem mérce.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "docs/sdd/00-index.md",
  "docs/sdd/dependency-graph.yaml",
  "tool/check_sdd_index.dart",
  "test/tooling/sdd_index_guard_test.dart",
  "docs/rounds/e12-r02-sdd-index-and-dependency-graph.md",
]
gate_tests = [
  "test/tooling/sdd_index_guard_test.dart",
]
native_gate = false
```

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha a §3 scope-jához olyan fájl kellene, ami a §4 listáján nincs rajta (pl. egy fejezet-fájl TARTALMÁNAK javítása), a kimenet a `stopped` jelzés és brief-revízió kérése — a lista csendes tágítása TILOS ([L478](../LESSONS.md#l478)).

## 1. Cél

A 14 fejezet egyetlen, gépileg ellenőrzött indexbe és körmentes dependency-manifestbe rendezése, hogy az „aktuális fejezet / következő kör" kérdés emberi olvasás nélkül is eldönthető legyen.

## 2. Jelenlegi állapot — mért tények

- `docs/sdd/00-index.md` létezik: 14 soros fejezet-tábla (Chapter 1–14), „Függőségi kép" ASCII-blokk és ajánlott végrehajtási sorrend. **Gépileg ellenőrizhető formája nincs.**
- **MÉRT eltérés:** az index a Chapter 12-re „42" kört ír; `grep -cE '^# Kör [0-9]+' docs/sdd/12-release-roadmap-final-integration.md` → **36**. A Chapter 14 sorára ugyanez a mérés (`^## Kör`) **42**-t ad, tehát ott az index HELYES. **A pre-flight mind a 14 sort újramérte (§0.0.A P1): a Chapter 12 az EGYETLEN eltérés.**
- **A tábla alakja NEM egységes** (§0.0.A P2–P3): a 14 sorból 9 lehagyja a záró `Zárójelentés` cellát, és 4 soron a körszám-cella prózát vagy `—`-t tartalmaz szám helyett. A parser egyik feltevést sem teheti meg.
- `docs/sdd/dependency-graph.yaml` **nem létezik**; a függőségek ma ASCII-ábraként élnek az indexben.
- **`package:yaml` NEM használható** (§0.0.A P4, ADR 0443 D3): transitive-only dependency + `depend_on_referenced_packages` → piros `flutter analyze`; a `pubspec.yaml` az `allowed_paths`-on kívül.
- `tool/check_sdd_index.dart` **nem létezik**. A követendő minta: `tool/check_architecture.dart` (**850** sor, allowlist-alapú, teszt-párja `test/tooling/architecture_allowlist_guard_test.dart`, amit **relatív importtal** ér el).
- A `tools/round-gate.sh` `architecture` lépése MA a `check_architecture.dart`-ot futtatja — a `check_sdd_index.dart` a gate-be NEM kerül bele ebben a körben (a gate-sor módosítása külön, ADR 0052 hatálya alatti döntés).

## 3. Scope

**Benne van:** a `00-index.md` fejezet-táblájának kiegészítése státusz + implementation-progress + dependency oszloppal, és a MÉRT körszámok javítása · `docs/sdd/dependency-graph.yaml` (fejezet-csomópontok, élek, `critical_path` és `capability_gated` jelölés) · `tool/check_sdd_index.dart` (minden fejezet pontosan egyszer; minden hivatkozott fájl létezik; a graph körmentes; a táblázat körszáma egyezik a fejezet-fájlban mért kör-fejlécek számával) · `test/tooling/sdd_index_guard_test.dart` (a checker mint teszt, fixture-alapú hibás bemenetekkel).

**NINCS benne (tilos):**

- A `docs/sdd/01-…14-…` fejezet-fájlok TARTALMÁNAK átírása — ha egy fejezet szövege hibás, az a `stopped` jelzés esete.
- A `tools/round-gate.sh` módosítása — a gate-sor bővítése nem ennek a körnek a döntése.
- `docs/adr/**` — az ADR 0443-at a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `docs/sdd/00-index.md` | a tábla bővítése és a körszámok javítása |
| `docs/sdd/dependency-graph.yaml` | ÚJ — a géppel olvasható függőség-manifest |
| `tool/check_sdd_index.dart` | ÚJ — az ellenőrző |
| `test/tooling/sdd_index_guard_test.dart` | ÚJ — a §6 cellái |
| `docs/rounds/e12-r02-sdd-index-and-dependency-graph.md` | a §10 implementation handoff kitöltése (a gépi `allowed_paths` blokk már tartalmazza) |

**Tilos zóna:** `docs/sdd/0*.md` és `docs/sdd/1[1-4]*.md` (a fejezet-fájlok) · `tools/**` · `lib/**` · `docs/adr/**` · `.github/**` · **`pubspec.yaml` / `pubspec.lock`** (§0.0.A P4 — a `yaml` dependency deklarálása H3 lenne)

> A `docs/sdd/00-index.md` **NEM** tilos zóna (`0*.md`-re illeszkedne, de tételesen engedélyezett a fenti táblában); a `docs/adr/0443-…md`-t az orchestrátor MÁR megírta és commitolta a pre-flightban — az implementer hozzá ne nyúljon.

## 5. Kötött architekturális döntések (ADR 0443)

### 5.1 A körszám FORRÁSA a fejezet-fájl, az index csak tükrözi

Az ellenőrző a fejezet-fájlból SZÁMOLJA a kör-fejléceket, és az indexet ahhoz méri. **NEM elfogadható gyengítés:** az index számának „hivatalossá" tétele és a fájl-mérés elhagyása, akár azzal az indoklással, hogy egy fejezet fejlécei nem egységesek (a Chapter 12 `# Kör`, a Chapter 14 `## Kör` — az ellenőrzőnek MINDKETTŐT kezelnie kell).

### 5.2 A dependency graph körmentessége gépi állítás, nem ábra

A `dependency-graph.yaml` az egyetlen forrás; az `00-index.md` ASCII-ábrája illusztráció. **NEM elfogadható gyengítés:** a körmentesség „szemre ellenőrzött" jelzése teszt nélkül, vagy a ciklus-detektálás elhagyása azzal, hogy a csomópontok léte ellenőrzött.

### 5.3 A manifestet SAJÁT, szűkített parser olvassa — `package:yaml` TILOS (ADR 0443 D3)

Mérve (§0.0.A P4): a `yaml` transitive-only, és a `depend_on_referenced_packages`
lint miatt a közvetlen import pirosra váltaná a `flutter analyze`-t; a
`pubspec.yaml` az `allowed_paths`-on kívül van. A `dependency-graph.yaml` ezért
**szándékosan szűkített YAML-részhalmaz**, sor-alapú, hibára beszédes parserrel.
**NEM elfogadható gyengítés:** (a) `package:yaml` import; (b) a `pubspec.yaml`
módosítása — az **H3**, a helyes kimenet a `stopped` jelzés; (c) a manifest
formátumának JSON-ra cserélése (az SDD Ch12 Kör 2 „Fő érintett fájlok" blokkja
`dependency-graph.yaml`-t nevez meg).

A szűkített alakot a manifest fejléc-kommentjében ÉS a parser hibaüzenetében ki
kell mondani — egy alakhibás manifest hibaüzenete mutassa meg a sort és azt,
milyen alakot várt.

### 5.4 A checker magja gyökér-paraméteres, tesztelhető API (ADR 0443 D4)

A `main()` nem tartalmazhatja az üzleti logikát: az A1/A2/A4 cellák hibás
bemenetekre mérnek, amiket a repó valódi tartalmán nem lehet előállítani. A
checker top-level, gyökér- vagy tartalom-paraméteres függvényeket exportál (a
minta: `test/tooling/architecture_allowlist_guard_test.dart` relatív importja),
a `main()` pedig ezek vékony, `exitCode`-ot állító burkolója. **NEM elfogadható
gyengítés:** a fixture-tesztek helyettesítése a valódi `docs/sdd/` egyetlen
zöld futtatásával — az csak azt bizonyítja, hogy a mai állapot jó, nem azt, hogy
a checker meg tudja fogni a hibát.

### 5.5 Az ellenőrző ebben a körben NEM kerül a gate-be (ADR 0443 D5)

A `tools/round-gate.sh` bővítése ADR 0052 hatálya alá tartozik, és a `tools/**`
a kör tilos zónája. A gépi mércét a `test/tooling/sdd_index_guard_test.dart`
adja, ami a teljes CI-suite része.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Minden fejezet pontosan egyszer szerepel az indexben; duplikátum/hiány esetén a checker nem-nulla kóddal lép ki | `sdd_index_guard_test.dart` |
| A2 | Minden index-hivatkozás létező fájlra mutat | `sdd_index_guard_test.dart` |
| A3 | A tábla körszáma MINDEN fejezetre egyezik a fejezet-fájlban mért kör-fejlécek számával (a Chapter 12 sora 42 → 36-ra javítva) | `sdd_index_guard_test.dart` + a javított `00-index.md` |
| A4 | A `dependency-graph.yaml` körmentes; egy szándékosan bevitt kör a checkert pirosra váltja | `sdd_index_guard_test.dart` ciklus-fixture |
| A5 | A checker mindkét kör-fejléc alakot (`# Kör N`, `## Kör N`) felismeri | `sdd_index_guard_test.dart` mindkét alakra írt cellája |
| A6 | A kritikus út és a capability-gated fejezetek jelöltek a manifestben | `dependency-graph.yaml` + a séma-cella |
| **A7** | A checker a MAI, valódi `docs/sdd/`-n **zölden** fut le a javított index mellett, mind a 14 sorra (a §0.0.A P1 táblázatának megfelelően) | `sdd_index_guard_test.dart` „valódi repó" cellája + a §10-be másolt `dart run tool/check_sdd_index.dart` kimenet |
| **A8** | A parser tolerálja az 5- és 6-cellás sort EGYARÁNT (§0.0.A P2), és a körszám-cellából kiolvassa a vezető egész számot próza mellől, az `—`-t pedig 0 körnek veszi (§0.0.A P3) | `sdd_index_guard_test.dart` külön cellái mind a négy alakra: `16`, `20 (lezárva …)`, `30 — implementation …`, `—` |
| **A9** | A `dependency-graph.yaml`-t SAJÁT parser olvassa; a diff **nem** tartalmaz `package:yaml` importot és **nem** módosítja a `pubspec.*`-ot (ADR 0443 D3) | `grep -rn "package:yaml" tool/ test/` → 0 találat; `git diff --name-only` → nincs `pubspec` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A checker az index számát fogadja el forrásként (nem számolja a fejezet-fájlt) | A3 |
| A checker csak a `# Kör` alakot ismeri, a `## Kör`-t nem (a Chapter 14 minden köre eltűnik) | A5 |
| A ciklus-detektálás kimarad, csak a csomópontok léte ellenőrzött | A4 |
| Egy hivatkozott, de nem létező fejezet-fájl átcsúszik | A2 |
| A parser fix 6 cellát vár → a 14 sorból 9-en (Ch5, 6, 8–14) elhasal | A8 + A7 |
| A parser `int.parse`-ol a körszám-cellán → a Ch1 (`—`), Ch3, Ch4, Ch7 sorokon dob | A8 + A7 |
| A checker `package:yaml`-t importál → piros `flutter analyze` a §7 gate-ben | A9 + §7 gate |
| A logika a `main()`-be kerül, beégetett `docs/sdd/` úton → a hibás-bemenet cellák megírhatatlanok | A1/A2/A4 (nem írható meg) |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** írd vissza a `00-index.md` Chapter 12 sorába a `42`-t, futtasd a §7 gate-et → az **A3** cellának PIROSNAK kell lennie → állítsd vissza a mért `36`-ot.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling/sdd_index_guard_test.dart
```

A checker közvetlen futtatása (a §10-be másolt kimenettel):

```bash
dart run tool/check_sdd_index.dart
```

## 8. Implementációs sorrend

1. Kör-fejléc-mérés minden `docs/sdd/*.md` fejezet-fájlra.
2. `docs/sdd/dependency-graph.yaml`.
3. `tool/check_sdd_index.dart` (index-parse → fájl-lét → körszám → ciklus).
4. `test/tooling/sdd_index_guard_test.dart` — fixture-alapú hibás bemenetek.
5. `docs/sdd/00-index.md` javítása a MÉRT számokra.
6. A valódi-sértés próba a §10-be.

## 9. Kockázatok

- **A fejlécalak-változatosság.** A `# Kör` / `## Kör` kettősség mérve létezik; egyetlen alak támogatása némán nulla kört mérne a Chapter 14-re (A5).
- **A checker túltervezése.** A Markdown-tábla parse-olása legyen szigorúan sor-alapú és hibára beszédes; egy általános Markdown-parser bevezetése ebben a körben indokolatlan.
- **A gate-sor csábítása.** A `check_sdd_index.dart` gate-be emelése ADR 0052 hatálya alá tartozik — ebben a körben tilos.
- **A `pubspec.yaml` csábítása.** A YAML-parse-hoz kézenfekvő lenne a `yaml` csomagot dev_dependencyként felvenni. Ez **H3** (§0.0.A P4): a `pubspec.*` a tilos zónán van, és a `native_gate = false` is elesne. A helyes kimenet ilyen igény esetén a `stopped` jelzés — de a §5.3 szerint az igény fel sem merül: a manifest alakja szűkített, saját parserrel olvasható.
- **A tábla alakjának heterogenitása.** Mérve (§0.0.A P2–P3): 5- és 6-cellás sorok keverve, próza a körszám mellett, `—` a Chapter 1-en. Egy „szép" táblát feltételező parser MA, az első futáson elhasal — ezt az A7 (valódi repó zölden) és az A8 (alak-cellák) EGYÜTT fogja meg.
- **A zöld gate nem bizonyíték** ([L476](../LESSONS.md#l476)): ez a kör két sor-alapú parsert ír. A §6.1 mérce-mátrix minden sorához tartozzon TÉNYLEGESEN megírt cella, és a §6 valódi-sértés próbája fusson le.

## 10. Implementation handoff — az implementer tölti ki

**Implementer:** Claude Sonnet 5 (`sonnet-impl`), munkapéldány
`/home/ubuntu/ss-sonnet-impl-e12-r02`, branch
`sonnet-impl/e12-r02-sdd-index-and-dependency-graph`.

### 10.1 Mit írtam

Commitok (időrendben, a pre-flight `4437fdb6` után):

1. `5190128c` — `docs/sdd/dependency-graph.yaml` (ÚJ) + `tool/check_sdd_index.dart` (ÚJ)
2. `1aca7df1` — `docs/sdd/00-index.md` javítása (Chapter 12: 42→36, 3 új oszlop,
   footnote csere) + `test/tooling/sdd_index_guard_test.dart` (ÚJ)
3. `cb24b01a` — A9 önteszt javítás: a `test/tooling/sdd_index_guard_test.dart`
   eredeti A9 cellája szó szerint tartalmazta a `"package:yaml"` sztringet
   (a saját asszerciójában és a csoport címében), ami **saját magát** buktatta
   volna el a §6 A9 evidence-parancsán (`grep -rn "package:yaml" tool/
   test/`). Javítás: a self-guard mostantól import-direktívából kinyert
   csomagnevet hasonlít össze a `'yaml'` literállal (sosem ír egymás mellé
   `"package:"` prefixet és a csomagnevet a saját forrásában).

**`docs/sdd/dependency-graph.yaml`** — 14 csomópont (ch01–ch14), 31 él. Az
élek iránya `from -> to` = „`to` függ `from`-tól" (megegyezik az index ASCII-
ábrájának nyíl-irányával). A `critical_path` (ch01, ch02, ch03, ch07, ch12) és
`capability_gated` (ch05, ch06, ch10, ch11, ch14) jelölés az index „Fő
előfeltétel" oszlopának és az „Ajánlott végrehajtási sorrend" szövegének
levezetése — ítélet, nem mérés, mert a §6.1 mérce-mátrixban nincs hozzá önálló
cella (a checker csak a mezők KÖTELEZŐ jelenlétét kényszeríti ki, ld. A6
teszt: `parseDependencyGraph` dob, ha egy node-ról hiányzik a `critical_path`
vagy `capability_gated`).

**`tool/check_sdd_index.dart`** (D4 minta követve, top-level/tartalom-
paraméteres API, `main()` csak vékony burkoló):
- `parseChapterTable` / `parseKorokCount` — a Markdown-tábla sor-alapú
  parsere; a "Zárójelentés" oszlopot NÉV szerint keresi meg a fejlécben (nem
  pozíció szerint), ezért egyaránt kezeli az 5/6-cellás (jelenlegi) ÉS a
  8/9-cellás (a 3 új oszloppal bővített) sorváltozatot ugyanazzal a
  logikával.
- `countKorHeaders` — `^#{1,2} Kör \d+` soronkénti minta, mindkét fejléc-alak.
- `parseDependencyGraph` — a `dependency-graph.yaml` fejléc-kommentjében
  dokumentált szűkített alakot olvassa, kézzel írt sor-alapú state-machine-
  nel; `package:yaml` NINCS importálva.
- `findCycle` — DFS szín-jelöléssel (fehér/szürke/fekete), a ciklust node-id
  lista formájában adja vissza.
- `validateSddIndex` — a tiszta, tartalom-paraméteres kereszt-ellenőrző
  (A1–A4 + az edge-konzisztencia); `checkSddIndexAtRoot` a vékony,
  `Directory`-paraméteres burkoló, ami a valódi `docs/sdd/`-t olvassa be.

**`docs/sdd/00-index.md`** — a Chapter 12 sorának `42`→`36` javítása; a
táblázat mind a 14 sora kapott 3 új cellát (Státusz / Implementation
progress / Dependency); a fejléc és az elválasztó sor 6→9 oszlopra bővült. A
meglévő 5/6-cellás heterogenitás (a `Zárójelentés` oszlop hiánya 9 sorban)
**szándékosan megmaradt** — ez maga a §0.0.A P2 mérés, és az A7/A8 teszt
pontosan ez ellen a valódi alak ellen fut. A footnote (eredeti 30. sor) a
prózai mentesítés helyett a checkerre mutat. A „Függőségi kép" ASCII-blokk
elé egy mondat került, ami a `dependency-graph.yaml`-t nevezi meg gépi
forrásként (ADR 0443 D2) — az ASCII-ábra tartalma NEM lett ez ellen
verifikálva ebben a körben (a brief ezt nem is kéri).

**`test/tooling/sdd_index_guard_test.dart`** — 35 teszt, csoportosítva a
§6.1 mérce-mátrix soraira (lásd 10.3).

### 10.2 Milyen parancsokat futtattam, tényleges kimenettel

**A valódi-sértés próba (§6, KÖTELEZŐ):**

```
$ (docs/sdd/00-index.md Chapter 12 sorát 36 -> 42-re írtam vissza)
$ tools/round-gate.sh test/tooling/sdd_index_guard_test.dart
...
00:00 +32 -1: checkSddIndexAtRoot — A7 (the real, checked-in docs/sdd/ tree) the real index and dependency graph are clean [E]
  Expected: true
    Actual: <false>
  SDD index check failed:
  - [korokMismatch] Chapter 12: az index tábla 42 kört ír ("42"), a fejezet-fájlban mért kör-fejlécek száma 36.
...
    → [3] test test/tooling/sdd_index_guard_test.dart: PIROS (kilépési kód 1)
Exit code 10 (round-gate.sh, code_failure)
```

Az A3 cella (a `checkSddIndexAtRoot — A7 … the real index and dependency
graph are clean` teszt) a várt módon PIROSRA váltott, pontosan a
`korokMismatch` kóddal és a `42`/`36` értékekkel az üzenetben. Ezután a sort
visszaírtam `36`-ra (`git diff --stat` a visszaírás után: nincs eltérés a
commitolt állapothoz képest).

**A kötelező záró ellenőrzés (§7, szó szerint, csővezeték/csonkítás
nélkül):**

```
$ tools/round-gate.sh test/tooling/sdd_index_guard_test.dart
═══ [1] format  → ZÖLD
═══ [2] analyze → ZÖLD (Analyzing 3 items... No issues found!)
═══ [3] test test/tooling/sdd_index_guard_test.dart → ZÖLD (00:00 +35: All tests passed!)
═══ [4] architecture → ZÖLD (Architecture dependencies OK (12 allowlisted deviation(s)).)
═══ [5] secrets → ZÖLD (Secret scan OK (3931 file(s) scanned, 0 finding(s)).)
═══ [6] l10n → ZÖLD (L10n aggregate freshness OK; L10n parity OK (en → hu, 2289 message(s)).)
Gate-összegzés: format zöld · analyze zöld · test … zöld · architecture zöld · secrets zöld · l10n zöld
MINDEN GATE ZÖLD.
```

Kilépési kód: `0`.

**A checker közvetlen futtatása (§7):**

```
$ dart run tool/check_sdd_index.dart
SDD index OK (0 issue(s)).
```

Kilépési kód: `0`.

**A9 evidencia (§6, szó szerint):**

```
$ grep -rn "package:yaml" tool/ test/
(nincs találat, kilépési kód 1)
$ git diff --name-only 4437fdb6 HEAD -- 'pubspec*'
(üres)
```

### 10.3 A §6.1 mérce-mátrix ↔ a ténylegesen megírt tesztcellák

| Mátrix-sor (hibás implementáció) | Cella | Megírt teszt |
|---|---|---|
| Az index számát fogadja el forrásként | A3 | `validateSddIndex … A3 — the checker measures the round count from the chapter file, not from the index cell` (42 vs mért 36 → `korokMismatch`) |
| Csak a `# Kör` alakot ismeri | A5 | `countKorHeaders — A5 …` mindkét alakra (single-#, double-##, kevert) |
| Ciklus-detektálás kimarad | A4 | `findCycle — A4 …` (direkt és hosszabb ciklus) + `validateSddIndex … A4 — a cyclic dependency graph is flagged …` |
| Nem létező fejezet-fájl átcsúszik | A2 | `validateSddIndex … A2 — a dangling Fájl/Zárójelentés reference is flagged` |
| Fix 6 cellát vár → 9-ből 9 elhasal | A8+A7 | `parseChapterTable — A8 (5- és 6-cellás tolerancia)` öt cella + a valódi `checkSddIndexAtRoot` A7 teszt a MAI (heterogén) fájlon |
| `int.parse` a körszám-cellán → Ch1/3/4/7 dob | A8+A7 | `parseKorokCount — A8 …` mind a 4 mért alakra (`16`, `20 (lezárva…)`, `30 — …`, `—`) |
| `package:yaml`-t importál | A9 | `A9 — the checker never depends on the restricted YAML pub package …` (import-direktíva csomagnév-kivonat) |
| A logika a `main()`-be kerül, beégetett úttal | A1/A2/A4 | Mindhárom `validateSddIndex`-teszt kézzel épített fixture-objektumokkal fut (nincs lemez-hozzáférés) — ez önmagában bizonyítja, hogy a logika NEM a `main()`-ben van |

Extra (a mátrixon felüli, de olcsó és releváns): egy graph-él, ami nem
létező node-ra hivatkozik (`unknownGraphNode`), és a `parseDependencyGraph`
két hibás-alak fixture-je (hiányzó kötelező mező, rossz indentálás, YAML
flow-collection).

### 10.4 Amit NEM futtattam, és miért

- **`gh workflow run build-apk.yml`** — a brief §7 / AGENTS.md szerint ezt az
  orchestrátor indítja, nem az implementer.
- **A teljes `flutter test` suite** — a round-gate a brief §7 szerint csak a
  kör saját tesztjét futtatja (`test/tooling/sdd_index_guard_test.dart`); a
  teljes suite + randomizált property gate a CI-ban fut (ADR 0053).
- **`tools/round-gate.sh` szerkesztése** a `check_sdd_index.dart` gate-be
  emeléséhez — ADR 0443 D5 / a brief §5.5 kifejezetten tiltja ebben a
  körben, és a `tools/**` a kör tilos zónája.

### 10.5 Ismert korlátok / jövőbeli kör tárgya

- A „Státusz" / „Implementation progress" / „Dependency" oszlopok tartalmát
  a checker NEM ellenőrzi (a brief §6 A1–A9 egyike sem követeli) — ezek a
  cellák a linkelt zárójelentésekből és az E12-R01 baseline-ból (
  `docs/release/program-baseline.md`, `docs/release/blockers.md`)
  származnak, ahol nincs ilyen bizonyíték, ott „specifikálva" / „nincs
  önálló mérés ebben a körben" szerepel — szándékosan nem találtam ki
  státuszt olyan fejezetre, amire nincs mérés.
- A „Függőségi kép" ASCII-ábra tartalmának a `dependency-graph.yaml` ellen
  való gépi verifikálása nincs ebben a körben (a brief nem kéri; az ábra
  ember-olvasó illusztráció marad, a kommentben jelölve).
- A `critical_path` / `capability_gated` konkrét igazságértékei ítéletek
  (ld. 10.1), nem mérés — egy jövőbeli kör felülbírálhatja őket anélkül,
  hogy a checker bármelyik acceptance cellája pirosra váltana (csak a mezők
  KÖTELEZŐ jelenlétét kényszeríti ki A6 alatt).

### 10.6 Javító kör (a `docs/reviews/e12-r02-review.md` F1/F2 leletei)

**F1a — a valódi tábla rendbetétele.** A 14 sorból 9-en (Chapter 5, 6, 8, 9,
10, 11, 12, 13, 14) explicit `—` cellát kaptak a `Zárójelentés` oszlopba,
pontosan úgy, ahogy a Chapter 1 sora ezt már a pre-flight óta teszi. A
Chapter 12 sorában ez azt jelentette, hogy a `folyamatban (10 nyitott
blocker…)` szöveg — ami korábban tévesen a `Zárójelentés` HELYÉRE csúszott —
most a helyes `Státusz` cellába kerül, a `—` pedig a `Zárójelentés`-be. A
`parseChapterTable` toleranciáját (a `header.length - 1` ág) NEM távolítottam
el — az továbbra is a régi, 5/6-cellás alakú sorokra védőháló, csak a valódi
fájlban most már egyik sor sem használja ki.

**F1b — gépi őr a valódi fájlra.** Új teszt-csoport
(`test/tooling/sdd_index_guard_test.dart`, „F1 (e12-r02 review) — the real
chapter table has no GFM cell-count drift"): saját, a `parseChapterTable`
NÉV-szerinti beszúrásától FÜGGETLEN GFM-hű cellaszámlálóval olvassa be a
valódi `docs/sdd/00-index.md`-t, és pirosra vált, ha bármely adatsor
cellaszáma eltér a fejlécétől.

Valódi-sértés próba (KÖTELEZŐ, ténylegesen lefuttatva — nem a régi Chapter 12
próba megismétlése, hanem az ÚJ F1b cellára):

```
$ (docs/sdd/00-index.md Chapter 5 sorából ideiglenesen kivettem az
   újonnan beírt "—" Zárójelentés-cellát, visszaállítva az eredeti,
   8-cellás alakra)
$ tools/round-gate.sh test/tooling/sdd_index_guard_test.dart
...
00:00 +32 -1: F1 (e12-r02 review) — the real chapter table has no GFM cell-count drift every data row in docs/sdd/00-index.md has the same cell count as the table header [E]
  Expected: empty
    Actual: [
              'line 19: 8 cell(s), expected 9: "| 5 | Epic 4: AI Guitar Teacher | 24 | Chapter 2; Chapter 3 és 7 evidenciakontraktusai | [`05-epic-04-ai-guitar-teacher.md`](05-epic-04-ai-guitar-teacher.md) | specifikálva | nincs önálló mérés ebben a körben | ch07 |"'
            ]
    → [3] test test/tooling/sdd_index_guard_test.dart: PIROS (kilépési kód 1)
Exit code 10 (round-gate.sh, code_failure)
```

A cella a várt módon PIROSRA váltott, a hibás sort és a pontos cellaszám-
eltérést névvel (`line 19: 8 cell(s), expected 9`) megnevezve. Ezután a `—`
cellát visszaírtam (`diff` az eredeti, javított fájllal: nincs eltérés), és a
gate újra lefutott — lásd alább.

A záró gate a visszaállítás UTÁN (§7, szó szerint, csővezeték/csonkítás
nélkül):

```
$ tools/round-gate.sh test/tooling/sdd_index_guard_test.dart
═══ [1] format  → ZÖLD
═══ [2] analyze → ZÖLD (Analyzing 3 items... No issues found!)
═══ [3] test test/tooling/sdd_index_guard_test.dart → ZÖLD (00:00 +36: All tests passed!)
═══ [4] architecture → ZÖLD (Architecture dependencies OK (12 allowlisted deviation(s)).)
═══ [5] secrets → ZÖLD (Secret scan OK (3932 file(s) scanned, 0 finding(s)).)
═══ [6] l10n → ZÖLD (L10n aggregate freshness OK; L10n parity OK (en → hu, 2289 message(s)).)
Gate-összegzés: format zöld · analyze zöld · test … zöld · architecture zöld · secrets zöld · l10n zöld
MINDEN GATE ZÖLD.
```

```
$ dart run tool/check_sdd_index.dart
SDD index OK (0 issue(s)).
```

Egy Python-szimulációval (GFM-hű pipe-splitter, a repóba nem került be) is
megerősítettem, hogy a javított táblán mind a 14 sor 0 eltéréssel
renderelődik, és a `Zárójelentés` / `Státusz` / `Dependency` cellák a
szándékolt tartalmat hordozzák (pl. Chapter 12: `Zárójelentés='—'`,
`Státusz='folyamatban (10 nyitott blocke…'`, `Dependency='ch01–ch11'`).

**F2 — a `Dependency` oszlop illusztráció, nem szerződés.** A (b) utat
választottam (olcsóbb, nem hizlalja a diffet): a `00-index.md` jegyzet-
blokkjába új bekezdés került, ami kimondja, hogy a `Dependency` oszlop — az
ASCII-ábrához hasonlóan — ember-olvasó illusztráció, az EGYETLEN géppel
ellenőrzött forrás a `dependency-graph.yaml` `edges:` blokkja, és hogy a
checker ma nem veti össze a kettőt (a Chapter 12 sor eltérő jelölése —
`ch01–ch11` tartomány a többi sor vesszős felsorolásához képest — miatt ma
nem is lenne egyenesen összevethető). A checker kódja és a `Dependency` cella
tartalma nem változott.

**F3 / F4 (NOTE) — nem nyúltam hozzájuk**, a review kifejezett utasítása
szerint.

**Scope.** Ugyanaz az öt fájl, mint az eredeti körben:
`docs/sdd/00-index.md`, `docs/sdd/dependency-graph.yaml` (változatlan ebben a
javító körben), `tool/check_sdd_index.dart` (változatlan), `test/tooling/
sdd_index_guard_test.dart`, `docs/rounds/e12-r02-sdd-index-and-dependency-
graph.md`.

## 11. Review — a Claude tölti ki
