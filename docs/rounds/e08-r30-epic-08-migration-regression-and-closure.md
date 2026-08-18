# E08-R30 — Teljes migráció, regresszió és az Epic 8 lezárása

- **Státusz:** PREPARED (előre megírva 2026-08-18, kód olvasva: `main @ ea6569fb`)
- **Típus:** Chapter 9 (Epic 8 — Gamification), Kör 30
- **Kör-azonosító:** `E08-R30`
- **Branch:** `<motor>/e08-r30-epic-08-migration-regression-and-closure`
- **Előfeltétel:** `E08-R29` merge-elve (CI-őrök)
- **Brief szerzője:** Claude (Opus 5)
- **ADR:** nincs — ez a kör nem hoz kötött architekturális döntést.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a MIND A 29 korábbi kör §10 handoffját (mi maradt nyitva), és futtasd le a `gh run list` parancsot a legutóbbi CI-futásokra — a lezárás bizonyítéka a ZÖLD CI, nem a lokális futás. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "normal"
allowed_paths = [
  "docs/sdd/epic-08-completion-report.md",
  "HANDOFF.md",
  "README.md",
  "lib/app/routing/app_route.dart",
  "test/app/routing/app_router_test.dart",
  "docs/rounds/e08-r30-epic-08-migration-regression-and-closure.md",
]
gate_tests = [
  "test/app/routing/app_router_test.dart",
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

Lezáró jelzés nélkül a kör bukott. **Listán kívüli fájl kellene → `stopped`**,
és a kimenet a brief-revízió kérése, nem az `allowed_paths` csendes tágítása.
Meglévő, ma zöld teszt elbukása → `blocked`, nem a teszt átírása.

## 1. Cél

Zárd le az Epicet teljes rendszerellenőrzéssel, az ÚJ útvonalak élesítésével,
dokumentációval és a legacy kód **kivezetési tervével**.

## 2. Jelenlegi állapot — mért tények

- A Kör 2–29 létrehozta a teljes gamifikációs réteget; az ÚJ képernyők (Hub, achievements, quests, streak V2, postaláda) elkészültek, de **útvonalon még nem elérhetők** — minden korábbi kör tilos zónája volt a `lib/app/routing/**`.
- A Kör 24 migrációs kapcsolója KIKAPCSOLVA vagy kettős írás állásban van — a végállapotra váltás ennek a körnek a dolga.
- A legacy `streak`, `progress` és `learn` rendszerek változatlanul élnek.
- A teljes tesztcsomag és az APK **CI-ban** fut (ADR 0053) — a lokális futás csak az érintett területekre.

## 3. Scope

**Benne van:** az ÚJ képernyők útvonalainak élesítése (Hub, achievements, quests, streak V2, postaláda) ·
a Kör 24 migrációs kapcsoló végállapotba állítása · a legacy migrációk ellenőrzése VALÓS
fixture-ökkel · offline újraindítás, időzóna, óra-visszaállítás és több eszközös összefésülés
próba · a `README.md` gamifikáció / adatvédelem / offline szakaszai · a kettős írás és a legacy
adapter **kivezetési feltételeinek** dokumentálása · az Epic completion report.

**NINCS benne (tilos):**

- Bármely `lib/features/**` fájl módosítása — ez a kör útvonalat élesít és dokumentál.
- A legacy `streak`/`progress` képernyők TÖRLÉSE — a kivezetés terve készül el, nem a végrehajtása.
- Új funkció bevezetése.
- A gate mércéjének bármilyen módosítása.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `docs/sdd/epic-08-completion-report.md` | **ÚJ** — az Epic lezáró jelentése |
| `HANDOFF.md` | a kötelező állapot-frissítés |
| `README.md` | a gamifikáció / adatvédelem / offline szakaszok |
| `lib/app/routing/app_route.dart` | az ÚJ képernyők útvonalainak élesítése — CSAK hozzáadás |
| `test/app/routing/app_router_test.dart` | az új útvonalak cellái |

**Tilos zóna:** `lib/features/**` (MINDEN feature) · `lib/core/**` · `backend/**` · `tools/**` · `.github/**` · `docs/adr/**` · `docs/sdd/` minden más fájlja

## 5. Kötött architekturális döntések

### 5.1 A RÉGI ÚTVONALAK TOVÁBB MŰKÖDNEK

Az új útvonalak **hozzáadódnak**; a `/streak` és `/progress` mélylink változatlanul
működik. A legacy képernyők kivezetése külön, későbbi döntés — ez a kör a FELTÉTELEIT írja le.

**NEM elfogadható gyengítés:** a régi útvonal átirányítása az újra „hogy egységes legyen”.
A meglévő mélylinkek és tesztek elbuknának.

### 5.2 A LEZÁRÁS BIZONYÍTÉKA A ZÖLD CI, nem a lokális futás

A teljes tesztcsomag, a property-kapu és az APK a CI-ban fut (ADR 0053). A
completion report **futás-linket** hivatkozik, nem lokális kimenetet.

**NEM elfogadható gyengítés:** „lokálisan minden zöld” állítás futás-link nélkül.

### 5.3 A KIVEZETÉS FELTÉTELEI SZÁMSZERŰEK

A kettős írás és a legacy adapter kivezetéséhez tartozó feltételek konkrétak
(mennyi ideig kell hibamentesen futnia, milyen mérőszám mellett), nem „amikor stabilnak
tűnik”.

### 5.4 A VALÓS FIXTURE-ÖK a legacy formátumból származnak

A migrációs ellenőrzés a `practice_streak_v1`, `practice_log_v1`,
`daily_goal_min_v1` és `lesson_progress_v1` kulcsok VALÓS alakjával dolgozik, nem
idealizált mintaadattal.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Az öt új képernyő útvonalon elérhető, és a régi `/streak` + `/progress` mélylink VÁLTOZATLANUL működik | `app_router_test.dart` — útvonal-mátrix |
| A2 | A legacy migrációk valós fixture-ökkel ellenőrizve: nincs adatvesztés | a §7 gate + a completion report |
| A3 | Offline újraindítás, időzóna-váltás és óra-visszaállítás után nincs dupla jutalom és nincs törött széria | a completion report próba-jegyzőkönyve |
| A4 | A `README.md` gamifikáció / adatvédelem / offline szakaszai frissültek | review |
| A5 | A kettős írás és a legacy adapter kivezetési feltételei SZÁMSZERŰEK | review |
| A6 | A completion report ZÖLD CI futás-linket hivatkozik (nem lokális kimenetet) | review — a link megnyitható |
| A7 | A `HANDOFF.md` az Epic 8 lezárását tükrözi | review |
| A8 | A `lib/features/**` ÉRINTETLEN | `git diff --stat` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A `/streak` átirányítva az új képernyőre | **A1** (a meglévő útvonal-teszt elbukik) |
| A completion report lokális kimenetre hivatkozik | **A6** |
| A kivezetési feltétel „amikor stabilnak tűnik” | **A5** |
| A migráció idealizált mintaadattal ellenőrizve | **A2** |
| A kör „gyorsan javít” egy feature-hibát | **A8** (`git diff --stat` `features/` útvonalat mutat) |
| Az új útvonalak regisztrálva, de teszt nélkül | **A1** |

**A küszöb három kötelező cellája** (a lezárás bizonyíték-szintje (mi számít elfogadható evidenciának)):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb **alatt** | lokális `flutter test` kimenet a jelentésben | **NEM elegendő** — a projekt mércéje a CI (ADR 0053) |
| **rajta** (a küszöbön) | a kör-branchre dispatchelt, ZÖLD CI-futás linkje | **ELEGENDŐ** — ez a kötelező minimum |
| a küszöb **fölött** | zöld CI + valós eszközön futtatott APK-próba | **a teljes bizonyíték**; az eszközös próba a user hatásköre, NEM merge-kapu |

A hármas tömören: **alatt** → elutasít · **rajta** → az §6.1 tábla dönti el · **fölött** → elfogad.

A határ **a **rajta** cellához tartozik (inkluzív) — a fenti táblázat „rajta” sora mondja ki, melyik oldal nyer**.

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** a completion report írásakor hivatkozz szándékosan egy PIROS futásra → a review
**A6** cellájának el kell utasítania → cseréld a zöld futás linkjére.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/app/routing/app_router_test.dart test/features/gamification test/features/streak test/features/progress
```

A gate artefaktum a mérce (`tools/round-gate.sh`) — a parancssorban
reprodukált parancslista NEM bizonyíték (AGENTS.md §12, L09). A script
`format` → `analyze` → `test <minden útvonal külön>` → `architecture`
lépéseket KÜLÖN processzként futtat, csonkítatlan kimenettel. **Tilos**
bármilyen szűrés vagy kézi lánc a promptban (OOM, L05). A kötelező gate-et
**TILOS háttérbe küldeni** (`run_in_background`) — az egy-fordulós harness a
forduló végén megöli, mielőtt eredmény érkezne (L183/L254). CI-dispatch, PR és
merge mindig Claude-oldal: az implementer `gh`-t NEM hív.

## 8. Implementációs sorrend

1. Az öt új útvonal regisztrálása (CSAK hozzáadás), a régiek érintése nélkül.
2. Az útvonal-tesztek bővítése.
3. A Kör 24 migrációs kapcsolójának végállapotba állítása.
4. Legacy migráció ellenőrzése valós fixture-ökkel.
5. Offline / időzóna / óra-visszaállítás / több eszköz próbák jegyzőkönyve.
6. `README.md` frissítés; a kivezetési feltételek számszerűsítése.
7. `docs/sdd/epic-08-completion-report.md` + `HANDOFF.md`.
8. CI-dispatch (Claude-oldal), majd a ZÖLD futás linkjének beemelése a jelentésbe.

## 9. Kockázatok

- **A régi útvonal átirányítása.** „Egységes” és a meglévő mélylinkeket + teszteket töri (A1).
- **A lokális zöld mint bizonyíték.** A projekt mércéje kifejezetten a CI (ADR 0053); a lokális kimenet nem lezárás (A6).
- **A „gyorsan javítom” kísértés.** 29 kör után lesznek látszó apróságok; a `lib/features/**` ebben a körben tilos zóna (A8).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
