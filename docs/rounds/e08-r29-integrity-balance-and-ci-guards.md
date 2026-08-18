# E08-R29 — Integritás, balance-szimuláció és CI-őrök

- **Státusz:** PREPARED (előre megírva 2026-08-18, kód olvasva: `main @ ea6569fb`)
- **Típus:** Chapter 9 (Epic 8 — Gamification), Kör 29
- **Kör-azonosító:** `E08-R29`
- **Branch:** `<motor>/e08-r29-integrity-balance-and-ci-guards`
- **Előfeltétel:** `E08-R28` merge-elve (főkönyv-szinkron)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0320` — a szám FOGLALT. Az ADR-t a Claude írja meg a
  kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t
  NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `.github/workflows/` TÉNYLEGES tartalmát (melyik workflow futtatja a Dart teszteket) és a `test/property/` meglévő `PROPERTY_SEED` mintáját — az új property-teszt ugyanazt a konvenciót követi. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "tool/check_gamification_catalog.dart",
  "tool/simulate_gamification_balance.dart",
  "test/features/gamification/property/gamification_invariants_test.dart",
  ".github/workflows/full-gate.yml",
  "docs/rounds/e08-r29-integrity-balance-and-ci-guards.md",
]
gate_tests = [
  "test/features/gamification/property/gamification_invariants_test.dart",
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

Automatizáld a katalógus-, policy- és integritás-ellenőrzéseket, és **bizonyítsd
szimulációval**, hogy az ismétlés-farmoló profil nem dominál.

## 2. Jelenlegi állapot — mért tények

- `test/property/` MA létezik és `PROPERTY_SEED` környezeti változóból dolgozik (hiányában 42); a CI külön HARD lépést futtat véletlen maggal (`CLAUDE.md`, HORIZON konvenciók).
- `tool/` alatt ma nincs gamifikációs script.
- Az R13 katalógusa és az R06 balance-konfigurációja a szimuláció bemenete.
- A `.github/workflows/` módosítása KIEMELTEN kockázatos kör (a merge-kapu maga) — a bizonyíték a kör-branchre dispatchelt ZÖLD futás az ÚJ kapukkal.

## 3. Scope

**Benne van:** achievement- és küldetés-katalógus validátor script · szimuláció kezdő, rendszeres,
intenzív és **ismétlés-farmoló** profilra · a szintgörbe várható idejének és a jutalom-
koncentrációnak az ellenőrzése · property-alapú invariáns tesztek · a CI blokkolja a duplikált
azonosítót, a hiányzó lokalizációs kulcsot és a negatív jutalmat.

**NINCS benne (tilos):**

- **A gate MÉRCÉJÉNEK gyengítése** — a `full-gate.yml` meglévő lépései nem törölhetők és nem lazíthatók (H-GATEGUARD).
- Bármely `lib/**` fájl módosítása — ez a kör eszközöket és őröket ad.
- Analitikai adat tényleges küldése — a szolgáltatás funkció-kapcsoló mögött, alapból KI.
- `docs/adr/**` — az ADR 0320-at a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `tool/check_gamification_catalog.dart` | **ÚJ** — katalógus-validátor |
| `tool/simulate_gamification_balance.dart` | **ÚJ** — balance-szimuláció |
| `test/features/gamification/property/gamification_invariants_test.dart` | **ÚJ** — property-invariánsok |
| `.github/workflows/full-gate.yml` | CSAK ÚJ lépések HOZZÁADÁSA — meglévő lépés NEM módosítható |

**Tilos zóna:** `lib/**` (a TELJES alkalmazáskód) · `test/` minden más fájlja · `tools/round-gate.sh` · `.github/workflows/` MINDEN más fájlja · `docs/adr/**` · `backend/**`

## 5. Kötött architekturális döntések (ADR 0320)

### 5.1 A MEGLÉVŐ GATE-LÉPÉSEK SÉRTHETETLENEK

Ez a kör a `full-gate.yml`-hez CSAK hozzáad. Meglévő lépés törlése, feltételessé
tétele vagy küszöbének lazítása **tilos** — ez a H-GATEGUARD határa, és emberi döntést
igényel.

**NEM elfogadható gyengítés:** egy meglévő lépés `continue-on-error: true` jelölése „amíg
az új őrök stabilizálódnak”.

### 5.2 AZ ISMÉTLÉS-FARMOLÓ NEM DOMINÁLHAT

A szimuláció bizonyítja, hogy az ugyanazt a gyakorlatot ismétlő profil nem szerez
lényegesen több XP-t, mint a változatosan gyakorló — az R06 csökkenő hozama miatt. Ez
számszerű acceptance-cella (A3), nem benyomás.

### 5.3 A PROPERTY-TESZT a `PROPERTY_SEED` konvenciót követi

Hiányzó környezeti változó esetén a mag 42 (determinisztikus fejlesztői hurok);
a CI külön lépésben véletlen maggal is futtatja. A küszöbök **százalék-alapúak**, hogy ne
legyenek flakyk — ez a projekt HORIZON konvenciója.

### 5.4 AZ ANALITIKA NEM SZIVÁROGTAT, és alapból KI van kapcsolva

A privacy-safe analitikai adapter funkció-kapcsoló mögött él, alapértéke
kikapcsolt, és soha nem továbbít nyers eseményt vagy azonosítható tartalmat — csak
összesített, azonosító nélküli mutatókat.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A katalógus-validátor pirosra vált duplikált azonosítón, hiányzó lokalizációs kulcson és negatív jutalmon | `dart run tool/check_gamification_catalog.dart` — három szándékos rontással |
| A2 | A szimuláció mind a négy profilra lefut és számszerű kimenetet ad | `dart run tool/simulate_gamification_balance.dart` |
| A3 | Az ismétlés-farmoló profil XP-je NEM haladja meg a változatosan gyakorlóét | `gamification_invariants_test.dart` — farmolás-cella, számszerű küszöbbel |
| A4 | A szintgörbe várható ideje dokumentált és a szimuláció kimenetével egyezik | `simulate_gamification_balance.dart` kimenete + review |
| A5 | A property-tesztek `PROPERTY_SEED`-ből dolgoznak; hiányában 42 | `gamification_invariants_test.dart` |
| A6 | Nincs negatív jutalom SEMMILYEN bemenetre | `gamification_invariants_test.dart` — property-invariáns |
| A7 | A CI ÚJ lépéseket kapott; a MEGLÉVŐ lépések bitre változatlanok | `git diff .github/workflows/full-gate.yml` — csak hozzáadás |
| A8 | Az analitikai adapter alapból kikapcsolt, és nem továbbít nyers eseményt | `gamification_invariants_test.dart` + review |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A validátor a duplikált azonosítót figyelmen kívül hagyja | **A1** |
| A csökkenő hozam kikerülhető ismétléssel | **A3** (a farmolás-cella) |
| A property-teszt fix maggal, környezeti változó nélkül | **A5** |
| Negatív jutalom keletkezhet szélsőséges bemenetre | **A6** |
| Egy meglévő CI-lépés `continue-on-error`-t kap | **A7** — H-GATEGUARD, emberi döntés kell |
| Az analitika alapból bekapcsolt | **A8** |

**A küszöb három kötelező cellája** (az ismétlés-farmoló profil XP-je a változatosan gyakorlóéhoz képest (`farmRatio`)):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb **alatt** | `farmRatio < 1,0` — a farmoló KEVESEBB XP-t szerez | **ELFOGADVA**: a csökkenő hozam működik |
| **rajta** (a küszöbön) | `farmRatio == 1,0` — pontosan annyit | **MÉG ELFOGADVA** — a küszöb az ELFOGADÓ oldalhoz tartozik (inkluzív): azonos ráfordításért azonos jutalom nem visszaélés |
| a küszöb **fölött** | `farmRatio > 1,0` — a farmoló TÖBBET szerez | **ELUTASÍTVA**: a csökkenő hozam nem hat, az A3 cella PIROS |

A hármas tömören: **alatt** → elutasít · **rajta** → az §6.1 tábla dönti el · **fölött** → elfogad.

A határ **a **rajta** cellához tartozik (inkluzív) — a fenti táblázat „rajta” sora mondja ki, melyik oldal nyer**.

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** állítsd a napi csökkenő hozamot semlegesre a szimuláció bemenetében, futtasd a
gate-et → az **A3** farmolás-cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/gamification/property/gamification_invariants_test.dart
```

A katalógus-ellenőrző és a szimuláció külön, önálló parancsként fut:

```bash
dart run tool/check_gamification_catalog.dart
```

```bash
dart run tool/simulate_gamification_balance.dart
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

1. `check_gamification_catalog.dart` — duplikált azonosító, hiányzó lokalizációs kulcs, negatív jutalom.
2. `simulate_gamification_balance.dart` — négy profil, számszerű kimenet.
3. `gamification_invariants_test.dart` — property-invariánsok `PROPERTY_SEED`-del.
4. A farmolás-arány számszerű cellája.
5. A `full-gate.yml` bővítése ÚJ lépésekkel (meglévő érintése nélkül).
6. Az analitikai adapter kapcsolójának alapértéke KI.
7. A valódi-sértés próba §10-be; a §7 három parancsa KÜLÖN futtatva.

## 9. Kockázatok

- **A gate lazítása.** A legkomolyabb határ: `continue-on-error` vagy lépés-törlés emberi döntést igényel (H-GATEGUARD), és a self-heal sem oldhatja fel (A7).
- **A benyomás-alapú balance.** „Elég jónak tűnik” — a farmolás-arány számszerű cella nélkül nem bizonyíték (A3).
- **A flaky property-teszt.** Abszolút küszöbökkel véletlen magon bukdácsol; a projekt konvenciója százalék-alapú küszöb (A5).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
