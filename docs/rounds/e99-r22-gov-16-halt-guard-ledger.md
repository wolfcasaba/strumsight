# E99-R22 (GOV-16) — Halt-főkönyv: ismétlődő halt-osztály őrteszt nélkül

- **Státusz:** READY FOR IMPLEMENTATION (pre-flight 2026-08-20, `main @ 8687ea61`)
- **Típus:** **governance-kör** — a lánc SAJÁT tanulási hurka
- **Kör-azonosító:** `E99-R22`. Emberi neve **GOV-16**.
- **Előfeltétel:** `E99-R20` merge-elve (ugyanaz a fájl: `docs/execution/pipeline-orchestrator-prompt.md`)
- **Brief szerzője:** Claude (Opus 5, orchesztrátor) · **ADR:** [`0315`](../adr/0315-halt-guard-ledger.md) — az ADR MÁR MEGÍRVA, a `docs/adr/` TILOS zóna.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "tools/halt-ledger.py",
  "tools/tests/test_halt_ledger.py",
  "docs/execution/pipeline-orchestrator-prompt.md",
  # ".github/workflows/router-ci.yml" — TÁRGYTALAN (mérve 2026-08-19).
  # A kör CSAK `tools/` alá hoz létre fájlt, a workflow `paths:` blokkja
  # pedig már `tools/**` családi globot használ (PR #324), tehát a CI
  # lefedettség automatikus. A védett fájl ezért kikerült a listáról:
  # így a mérce-őr pre-flightja nem teszi hold-ra a kört.
  "docs/rounds/e99-r22-gov-16-halt-guard-ledger.md",
]
gate_tests = [
  "test/tooling/architecture_allowlist_guard_test.dart",
]
native_gate = false
```

> **Kockázat = normal, indoklás:** a kör egy READ-ONLY jelentő eszközt ad és egy
> dokumentum-konvenciót ír le. Nem nyúl a kapuhoz, a lánc vezérléséhez, a
> merge-úthoz, sem futásidejű viselkedéshez; a jelentés nem blokkol semmit.

## 0.0 Pre-flight revízió (2026-08-20)

- A brief-lint elsőként futott: `python3 tools/brief-lint.py --brief
  docs/rounds/e99-r22-gov-16-halt-guard-ledger.md --level strict` → nincs
  lelet. A mérce-őr pre-flightja szintén tiszta:
  `tools/gateguard-scan.py --brief docs/rounds/e99-r22-gov-16-halt-guard-ledger.md`
  → nincs ütközés.
- Az indító prompt „a pre-flightban írd meg” szövegével szemben az
  [`ADR 0315`](../adr/0315-halt-guard-ledger.md) már elfogadva és commitolva
  van, a brief eredeti 7. sora pedig kifejezetten tilos zónának nevezi a
  `docs/adr/**`-t. Az örökség-ellenőrzési szabály szerint a meglévő ADR-t
  használjuk fel, nem írjuk újra. A foglaló ma `0373`-at adott; ez nem ennek
  a körnek az ADR-je, és a kör diffjébe nem kerül.
- A tényleges, verziókövetett `.pipeline/halted-*.txt` korpusz ma 10 rekord:
  `H-INDEP = 4`, `H-GATEGUARD = 2`, `H3 = 2`, `H8 = 1`,
  `H-NOSIGNAL = 1`. A mezőket a rekordokból mértük (`round=`, `halt=`,
  `halted_at=`, egyes rekordokban `outcome=`), nem a régi összesítőből.
- A géppel olvasható, félkövér `**Őrteszt:**` konvencióra továbbra is 0
  találat van. Egy régi lecke (`L324`) tartalmaz nem félkövér `Őrteszt:` sort;
  ez szándékosan nem teljesíti az ADR 0315 gépi alakját.
- A kötelező, előbb szűkített, majd teljes korpuszos visszakeresés releváns
  találatai: `adr/0315` (a főkönyv normatív döntése), `halts/E99-R16/H3`
  (a fájlonkénti Router-CI szűrő korábbi néma rése) és `lessons/L323`
  (a védett mérceútvonalak körüli hamis feloldás veszélye). A jelenlegi
  `.github/workflows/router-ci.yml` már `tools/**` családi globot használ,
  ezért D4 teljesíthető workflow-módosítás nélkül. Az index két committal
  elavult volt; az ADR 0312 szerinti merge-horgony frissíti, ebben a körben
  nem reindexeljük kézzel.

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

Lezáró jelzés nélkül a kör bukott. **STOP-protokoll:** listán kívüli fájl →
`stopped` + brief-revízió kérése; az `allowed_paths` tágítása TILOS.

## 0.1 Visszakeresett előzmény (tudás-index, ADR 0312 §4.1)

Az eredeti brief visszakeresése:
`node tools/knowledge-rag.mjs --top 4 "ugyanaz a hiba másodszor fordult elő őrteszt hiánya ismétlődő halt"`:

- **`lessons/L315`** — a címében kimondva: *„E07-R23 H6, **2. előfordulás**"*.
  Ugyanaz a hibaosztály másodszor futott le, mert az elsőből nem lett gépi őr.
- **`lessons/L313`** (E99-R14 H3) — a gyökérok órákkal korábban le volt írva,
  és egy kör mégis belefutott; a javítás akkor kapott falszifikációs őrtesztet.
- **`rounds/e99-r15`** (GOV-09) — a szomszédos kör: az **eszkalációt** kezeli
  (motorváltás + ismételt riasztás). Határ: az R15 azzal foglalkozik, mi
  történjen egy NYITOTT halttal; ez a kör azzal, mi maradjon utána.

Mérve a pre-flightban:
`rg -c '\*\*Őrteszt:\*\*' docs/LESSONS.md` → **0**. Vagyis az ADR 0315
géppel olvasható alakjában őrteszt-hivatkozás jelenleg egyetlen leckében sincs.

## 1. Cél

A lánc tanul — minden mért tanulság bekerül a `docs/LESSONS.md`-be, és a jó
körökben őrtesztet is kap (L312 → `test_slot_lock_inheritance.py`, L313 →
`AmbientEnvironmentLeakTest`). Ez ma **fegyelem**, nem rendszer, és a fegyelem
mérve elromlik (L315: 2. előfordulás). Kell egy jelentés, ami megmutatja,
mely ismétlődő halt-osztály maradt gépi őr nélkül.

## 2. Jelenlegi állapot — mérve a kódban

- `.pipeline/halted-*.txt` rekordok mezői: `round=`, `halt=`, `summary=`,
  `detail=`, `session_log=`, `halted_at=`, egyeseken `outcome=`.
- Halt-kód eloszlás mérve a verziókövetett korpuszon: H-INDEP 4,
  H-GATEGUARD 2, H3 2, H8 1, H-NOSIGNAL 1.
- `docs/LESSONS.md`: `## L<szám> — <cím>` szakaszok; az ADR 0315 szerinti
  félkövér, géppel olvasható őrteszt-hivatkozás **nincs** (0 találat).

## 3. Feladatok

### D1 — `tools/halt-ledger.py`

READ-ONLY jelentő eszköz:

```
tools/halt-ledger.py [--repo <út>] [--format markdown|json]
```

- Beolvassa a `.pipeline/halted-*.txt` rekordokat → (halt-kód, kör, időbélyeg).
- Beolvassa a `docs/LESSONS.md` szakaszait, és kigyűjti a géppel olvasható
  hivatkozásokat: a lecke törzsében egy `**Őrteszt:** <útvonal>::<név>` alakú sor.
- A lecke akkor tartozik egy halt-osztályhoz, ha a címe vagy törzse tartalmazza
  a halt-kódot (`H3`, `H6`, `H8`, `H-NOSIGNAL`, …) szóhatáron.
- Kimenet: halt-osztályonként előfordulás-szám, a hivatkozott őrtesztek listája,
  és az állapot: `fedett` (van hivatkozás) / `hiányzik` (nincs).
- Kilépési kód **mindig 0**: ez jelentés, nem kapu (ADR 0315 §2.1).

### D2 — A figyelmeztetés szabálya

Az a halt-osztály kap `hiányzik` jelölést, amiből **kettő vagy több**
előfordulás van, és nincs hozzá hivatkozott őrteszt. Egyetlen előfordulás nem
jelölt: egy egyszeri eset még nem osztály.

### D3 — A konvenció kimondása

`docs/execution/pipeline-orchestrator-prompt.md` záró rituálék szakasza: ha a
kör halt után zárul, a `docs/LESSONS.md`-be írt lecke tartalmazzon egy
`**Őrteszt:** <útvonal>::<név>` sort, vagy egy kimondott
`**Őrteszt:** nincs — <indok>` sort. A régi leckék visszamenőleg NEM kötelesek.

### D4 — CI-szűrő

`.github/workflows/router-ci.yml` `paths:` blokkja fedje le a
`tools/halt-ledger.py` és `tools/tests/test_halt_ledger.py` fájlokat. A fedés
**nő, sosem szűkül** (mérve: PR #309 piros CI-kapuja).

## 4. Mérce-mátrix (`tools/tests/test_halt_ledger.py`)

Hermetikus fixture: ideiglenes repó saját `.pipeline/halted-*.txt` és
`LESSONS.md` fájlokkal — az élő fát nem érinti.

| eset | bemenet | elvárt viselkedés |
|---|---|---|
| fedett osztály | 3 db `H8` rekord + egy `H8`-at említő lecke `**Őrteszt:** tools/tests/x.py::T` sorral | `fedett`, nincs figyelmeztetés |
| hiányzó osztály | 3 db `H6` rekord, egyik lecke sem hivatkozik őrtesztet | `hiányzik` |
| kimondott hiány | 2 db `H2` rekord + lecke `**Őrteszt:** nincs — <indok>` sorral | `fedett` (a kimondott hiány is döntés) |
| lecke halt-kód nélkül | `H3` rekordok + `H30`-at említő lecke | NEM számít fedésnek (szóhatár!) |
| üres bemenet | nincs halt-rekord | üres jelentés, kilépési kód 0 |
| json alak | `--format json` | gépi alak, ugyanazok a mezők |

**Előfordulás-hármas** (a D2 szabálya, a határ két oldala és maga a határ):

| cella | eset | elvárt |
|---|---|---|
| a határ **alatt** | 1 előfordulás, nincs őrteszt | NEM jelölt |
| a határon (**rajta**) | pontosan 2 előfordulás, nincs őrteszt | `hiányzik` |
| a határ **fölött** | 5 előfordulás, nincs őrteszt | `hiányzik` |

**Falszifikációs cellák (kötelezők):**

1. A D1 szóhatáros illesztés lecserélése egyszerű részszöveg-keresésre → a
   „lecke halt-kód nélkül" cella **PIROS** (a `H30` fedésnek látszana) →
   visszaállítás után zöld.
2. A D2 két-előfordulásos szabály lecserélése egyre → az „alatt" cella
   **PIROS** (egyszeri eset is jelölt lenne) → visszaállítás után zöld.

## 5. Tilos zóna — amit ez a kör NEM tesz

- **Nem blokkol.** A jelentés kilépési kódja mindig 0; a halt lezárása,
  az önjavítás menete (ADR 0112) és a merge-kapu érintetlen.
- **Nem ír tesztet automatikusan** és nem módosítja a `docs/LESSONS.md`-et:
  hiányt MUTAT, nem tölt ki.
- Nem módosítja a halt-kódokat és a `tools/round-pipeline.sh`-t — így nem
  ütközik az E99-R14…R21 körökkel.
- Fájlok: `docs/adr/**`, `docs/LESSONS.md`, `.ai/router.toml`, `.pipeline/**`,
  Dart források — tilos.

## 6. Definition of Done

1. D1–D4 kész; a `tools/halt-ledger.py` futtatható és READ-ONLY.
2. `tools/tests/test_halt_ledger.py` lefedi a §4 mind a hat celláját és az
   előfordulás-hármast, hermetikus fixture-ön.
3. `python3 -m pytest tools/tests -q` zöld.
4. `tools/round-gate.sh test/tooling/architecture_allowlist_guard_test.dart` zöld.
5. Kör-jelzés `done`.

## 7. Gate

```bash
tools/round-gate.sh test/tooling/architecture_allowlist_guard_test.dart
python3 -m pytest tools/tests -q
```

A gate-lépések külön processzben futnak; a csonkítatlan kimenet a bizonyíték.
A teljes suite + property gate a CI-ban fut (ADR 0053).

## Implementation handoff

- `tools/halt-ledger.py`: stdlib-only, READ-ONLY CLI a halt-rekordok számlálására,
  a szóhatáros lecke-illesztésre és a gépi őrteszt-hivatkozások jelentésére
  Markdown vagy JSON alakban. A jelentés minden sikeres futásnál 0-val tér vissza.
- `tools/tests/test_halt_ledger.py`: hermetikus fixture-ök a §4 teljes
  mátrixára, a 1/2/5 előfordulási küszöbre, a `H3`/`H30` szóhatárra, a
  kimondott `nincs` döntésre és mindkét kimeneti alakra.
- `docs/execution/pipeline-orchestrator-prompt.md`: a merge utáni záró
  rituálékban rögzíti az új `**Őrteszt:**` konvenciót halt után.

Futtatott parancsok:

```text
python3 -m py_compile tools/halt-ledger.py
# sikeres (exit 0)

python3 -m pytest tools/tests/test_halt_ledger.py -q
# 7 passed in 0.47s

python3 -m pytest tools/tests -q
# sikeres (exit 0)

tools/round-gate.sh test/tooling/architecture_allowlist_guard_test.dart
# sikeres (exit 0): format, analyze, célzott teszt, architecture és secret scan zöld
```

Eltérés nincs. Nem futtatott ellenőrzés: a teljes Flutter/property suite és
CI-dispatch a CI/orchestrátor felelőssége; a kör implementere nem dispatch-el.
