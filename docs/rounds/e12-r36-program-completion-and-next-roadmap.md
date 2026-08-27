# E12-R36 — Program completion report és következő roadmap

- **Státusz:** PREPARED (előre megírva 2026-08-27, kód olvasva: `main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 36 — a fejezet ZÁRÓ köre
- **Kör-azonosító:** `E12-R36`
- **Branch:** `<motor>/e12-r36-program-completion-and-next-roadmap`
- **Előfeltétel:** `E12-R35` merge-elve (és a Chapter 12 minden korábbi köre)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** nincs — záró/riport-kör.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "program completion report roadmap chapter matrix handoff"` → a `halts/round-status-E07-R30`, `E07-R23`, `E08-R26` merge-elt ZÁRÓ körök — a repóban van bevált minta az epic-záró completion reportra (`docs/sdd/epic-0X-completion-report.md`). Ez a kör azt a mintát emeli PROGRAM-szintre.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** futtasd a Kör 2 `tool/check_sdd_index.dart` ellenőrzőjét, és mérd meg minden fejezet TÉNYLEGES kör-státuszát a `docs/execution/pipeline-queue.tsv`-ből. A completion matrix ebből a KÉT forrásból készül, nem emlékezetből.

## 0.0 A záró kör őszinteségi feltétele

A program-riport akkor ér valamit, ha a NEM elkészült részeket is pontosan nevezi meg. A megíráskor MÉRT állapot szerint az Epic 10 (Offline AI) sáv `hold`-on, a Chapter 14 sáv `prepared` státuszban áll, és a Chapter 12 rounds 27–33 emberi kapuja külön jelölendő. A riport ezeket NEM írhatja késznek.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "docs/sdd/program-completion-report.md",
  "docs/roadmap/next-six-months.md",
  "docs/sdd/00-index.md",
  "HANDOFF.md",
  "test/tooling/program_completion_test.dart",
  "docs/rounds/e12-r36-program-completion-and-next-roadmap.md",
]
gate_tests = [
  "test/tooling/program_completion_test.dart",
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

**STOP-protokoll:** ha a completion matrix egy fejezet státuszához nem talál bizonyítékot (queue-sor, completion report vagy merge-elt PR), a kimenet a `stopped` jelzés — becsült státusz nem kerülhet a riportba.

## 1. Cél

A program állapotának átadható, bizonyíték-alapú lezárása és egy termékmetrikákból induló, outcome-alapú következő roadmap.

## 2. Jelenlegi állapot — mért tények

- `docs/sdd/`: fejezet-fájlok 01–14, `epic-0{1,2,3,6}-completion-report.md` — a completion report MÉRT mintája.
- `docs/execution/pipeline-queue.tsv`: körönként egy sor, `prepared | pending | running | done | halted | hold` státusszal — ez a státusz EGYETLEN gépi forrása.
- `docs/roadmap/` **nem létezik**.
- `HANDOFF.md` a mindenkori pillanatkép — a kör a záró bejegyzést írja bele.
- A `00-index.md` a Kör 2 óta gépileg ellenőrzött.

## 3. Scope

**Benne van:** `docs/sdd/program-completion-report.md` (fejezetenként: kör-szám, `done`/nyitott sorok, bizonyíték-hivatkozás, fő tanulságok, eltérések a tervtől) · `docs/roadmap/next-six-months.md` (outcome-alapú célok termékmetrikákkal, NEM feature-lista) · a `00-index.md` státusz-oszlopának frissítése a MÉRT queue-állapotra · `HANDOFF.md` záró bejegyzés · `test/tooling/program_completion_test.dart` (a riport minden fejezet-státusza egyezik a queue-val; minden hivatkozott fájl létezik; nyitott sáv nem jelölhető késznek).

**NINCS benne (tilos):**

- Bármely `lib/`, `backend/`, `tool/` kód módosítása.
- Fejezet-fájl tartalmának átírása.
- A `pipeline-queue.tsv` módosítása (olvasni kell, nem igazítani).
- `docs/adr/**`.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `docs/sdd/program-completion-report.md` | ÚJ — a program-szintű zárójelentés |
| `docs/roadmap/next-six-months.md` | ÚJ — outcome-alapú roadmap |
| `docs/sdd/00-index.md` | státusz-oszlop frissítés a MÉRT állapotra |
| `HANDOFF.md` | záró bejegyzés |
| `test/tooling/program_completion_test.dart` | a §6 cellái |

**Tilos zóna:** `lib/**` · `backend/**` · `tool/**` · `docs/sdd/0*.md` és `1[1-4]*.md` · `docs/execution/pipeline-queue.tsv` · `docs/adr/**`

## 5. Kötött architekturális döntések

Nincs ADR. Három kötelező szabály:

### 5.1 A státusz FORRÁSA a queue, nem a riport

**NEM elfogadható gyengítés:** a riportban „kész" jelölés olyan sávra, amelynek queue-sorai `hold` vagy `prepared` státuszúak (a megíráskor: Epic 10 és Chapter 14).

### 5.2 A roadmap OUTCOME-alapú

Minden tétel egy mérhető felhasználói/terméki eredményt nevez meg, nem funkciót. **NEM elfogadható gyengítés:** a hátralévő SDD-körök átmásolása feature-listaként.

### 5.3 Az emberi kapuk NEVESÍTVE maradnak

A Kör 27–33 user-műveletei és a valós gitáros APK-teszt a riportban EXPLICIT emberi kapuként szerepelnek. **NEM elfogadható gyengítés:** ezek „elvégzett lépésként" való feltüntetése.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A completion matrix minden fejezet-státusza egyezik a `pipeline-queue.tsv` MÉRT állapotával | `program_completion_test.dart` |
| A2 | Nyitott (`hold`/`prepared`) sávot a riport NEM jelöl késznek | `program_completion_test.dart` |
| A3 | Minden hivatkozott dokumentum létezik | `program_completion_test.dart` |
| A4 | A roadmap minden tétele mérhető outcome-ot nevez meg | `program_completion_test.dart` szerkezeti cellája |
| A5 | Az emberi kapuk (Kör 27–33, valós APK-teszt) explicit jelöléssel szerepelnek | a riport + a teszt cellája |
| A6 | A `00-index.md` a Kör 2 ellenőrzőjével továbbra is valid | `sdd_index_guard_test.dart` a §7 gate-ben |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A riport az Epic 10-et késznek jelöli, miközben a sorai `hold`-on állnak | A1/A2 |
| A roadmap a hátralévő SDD-körök feature-listája | A4 |
| Az emberi kapuk elvégzett lépésként szerepelnek | A5 |
| Az index-frissítés elrontja a körszám-egyezést | A6 |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** írd át a riportban az Epic 10 státuszát „kész"-re, futtasd a §7 gate-et → az **A1**/**A2** cellának PIROSNAK kell lennie → állítsd vissza a MÉRT állapotra.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/tooling/program_completion_test.dart test/tooling/sdd_index_guard_test.dart
```

## 8. Implementációs sorrend

1. A MÉRÉS: queue-státuszok fejezetenként + a meglévő completion reportok.
2. `docs/sdd/program-completion-report.md`.
3. `test/tooling/program_completion_test.dart`.
4. `docs/sdd/00-index.md` státusz-frissítés.
5. `docs/roadmap/next-six-months.md`.
6. `HANDOFF.md` záró bejegyzés + a valódi-sértés próba a §10-be.

## 9. Kockázatok

- **Kozmetikai zárójelentés.** A legnagyobb kockázat, hogy a riport késznek mutat egy el sem indult sávot (A2).
- **Feature-lista roadmap.** A SDD folytatása outcome helyett (A4).
- **Index-drift.** A státusz-oszlop frissítése elronthatja a Kör 2 gépi egyezését (A6).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
