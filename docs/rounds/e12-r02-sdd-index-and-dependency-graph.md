# E12-R02 — SDD index és dependency graph

- **Státusz:** PREPARED (előre megírva 2026-08-27, kód olvasva: `main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 2
- **Kör-azonosító:** `E12-R02`
- **Branch:** `<motor>/e12-r02-sdd-index-and-dependency-graph`
- **Előfeltétel:** `E12-R01` merge-elve (a baseline adja az index `implementation progress` oszlopának bizonyítékait)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0443` — a szám FOGLALT (Chapter 12 batch-tartomány: `0443`–`0465`, driftre számítva).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "SDD index dependency graph chapter status validation tool"` → nincs közvetlenül releváns előzmény (a találatok — ADR 0068, ADR 0194 — más domain contractjai); a minta-forrás ezért a repó SAJÁT, működő ellenőrző-eszköze, a `tool/check_architecture.dart` + `test/tooling/architecture_allowlist_guard_test.dart` pár.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `docs/sdd/00-index.md` fejezet-tábláját és számold meg a fejezet-fájlok TÉNYLEGES kör-fejléceit (`grep -cE '^#{1,2} Kör [0-9]+' docs/sdd/<fájl>`). A megíráskor MÉRT eltérés: az index a Chapter 12-re **42** kört ír, a fájlban **36** `# Kör` fejléc van. Ha a pre-flight más számot mér, a §2 és az A3 cella értékét frissítsd.

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
- **MÉRT eltérés:** az index a Chapter 12-re „42" kört ír; `grep -cE '^# Kör [0-9]+' docs/sdd/12-release-roadmap-final-integration.md` → **36**. A Chapter 14 sorára ugyanez a mérés (`^## Kör`) **42**-t ad, tehát ott az index HELYES.
- `docs/sdd/dependency-graph.yaml` **nem létezik**; a függőségek ma ASCII-ábraként élnek az indexben.
- `tool/check_sdd_index.dart` **nem létezik**. A követendő minta: `tool/check_architecture.dart` (786 sor, allowlist-alapú, teszt-párja `test/tooling/architecture_allowlist_guard_test.dart`).
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

**Tilos zóna:** `docs/sdd/0*.md` és `docs/sdd/1[1-4]*.md` (a fejezet-fájlok) · `tools/**` · `lib/**` · `docs/adr/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0443)

### 5.1 A körszám FORRÁSA a fejezet-fájl, az index csak tükrözi

Az ellenőrző a fejezet-fájlból SZÁMOLJA a kör-fejléceket, és az indexet ahhoz méri. **NEM elfogadható gyengítés:** az index számának „hivatalossá" tétele és a fájl-mérés elhagyása, akár azzal az indoklással, hogy egy fejezet fejlécei nem egységesek (a Chapter 12 `# Kör`, a Chapter 14 `## Kör` — az ellenőrzőnek MINDKETTŐT kezelnie kell).

### 5.2 A dependency graph körmentessége gépi állítás, nem ábra

A `dependency-graph.yaml` az egyetlen forrás; az `00-index.md` ASCII-ábrája illusztráció. **NEM elfogadható gyengítés:** a körmentesség „szemre ellenőrzött" jelzése teszt nélkül.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Minden fejezet pontosan egyszer szerepel az indexben; duplikátum/hiány esetén a checker nem-nulla kóddal lép ki | `sdd_index_guard_test.dart` |
| A2 | Minden index-hivatkozás létező fájlra mutat | `sdd_index_guard_test.dart` |
| A3 | A tábla körszáma MINDEN fejezetre egyezik a fejezet-fájlban mért kör-fejlécek számával (a Chapter 12 sora 42 → 36-ra javítva) | `sdd_index_guard_test.dart` + a javított `00-index.md` |
| A4 | A `dependency-graph.yaml` körmentes; egy szándékosan bevitt kör a checkert pirosra váltja | `sdd_index_guard_test.dart` ciklus-fixture |
| A5 | A checker mindkét kör-fejléc alakot (`# Kör N`, `## Kör N`) felismeri | `sdd_index_guard_test.dart` mindkét alakra írt cellája |
| A6 | A kritikus út és a capability-gated fejezetek jelöltek a manifestben | `dependency-graph.yaml` + a séma-cella |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A checker az index számát fogadja el forrásként (nem számolja a fejezet-fájlt) | A3 |
| A checker csak a `# Kör` alakot ismeri, a `## Kör`-t nem (a Chapter 14 minden köre eltűnik) | A5 |
| A ciklus-detektálás kimarad, csak a csomópontok léte ellenőrzött | A4 |
| Egy hivatkozott, de nem létező fejezet-fájl átcsúszik | A2 |

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

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
