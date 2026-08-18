# E08-R28 — Főkönyv-szinkron szerződés, összefésülés és igazolt státusz

- **Státusz:** PREPARED (előre megírva 2026-08-18, kód olvasva: `main @ ea6569fb`)
- **Típus:** Chapter 9 (Epic 8 — Gamification), Kör 28
- **Kör-azonosító:** `E08-R28`
- **Branch:** `<motor>/e08-r28-ledger-sync-contract-and-merge`
- **Előfeltétel:** `E08-R27` merge-elve (a11y és beállítások)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0319` — a szám FOGLALT. Az ADR-t a Claude írja meg a
  kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t
  NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `backend/` TÉNYLEGES szerkezetét (`backend/app/`, Alembic migrációk, `backend/tests/`) és a `lib/features/auth/` + `settings_sync.dart` mintáját — a fiók-kikapcsolt állapot ellenőrzése onnan jön. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/gamification/data/sync/gamification_sync_contract.dart",
  "lib/features/gamification/data/sync/ledger_merge_policy.dart",
  "lib/features/gamification/public.dart",
  "backend/app/gamification/schemas.py",
  "backend/app/gamification/service.py",
  "test/features/gamification/data/ledger_merge_policy_test.dart",
  "backend/tests/test_gamification_ledger.py",
  "docs/rounds/e08-r28-ledger-sync-contract-and-merge.md",
]
gate_tests = [
  "test/features/gamification/data/ledger_merge_policy_test.dart",
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

Offline-first, **duplikációmentes** szinkron-szerződés a későbbi fiók- és közösségi
használathoz — a legfontosabb szabállyal: a **szerver soha nem fogad el kliens-oldali
összesített XP-t**.

## 2. Jelenlegi állapot — mért tények

- A `backend/` FastAPI + SQLite + JWT szolgáltatás (CLAUDE.md); ma login + felhő-beállítás szinkront kezel, a felismerés 100%-ban eszközön marad.
- A `settings_sync.dart` mért mintája: szinkronizáltnak jelölés CSAK szerver-megerősítés után, sikertelen küldés újrapróbálva.
- Az R03 főkönyve immutable, `sourceEventId`-re dedupál; az R07 profilja PROJEKCIÓ, nem forrás.
- `backend/app/gamification/` **nem létezik** — ez a kör hozza létre.

## 3. Scope

**Benne van:** az immutable nyugta fel- és letöltési szerződése · összefésülés a főkönyv-azonosító ÉS
a forrás-esemény azonosító alapján · a lokális **nem igazolt** és a szerver által **igazolt**
státusz szétválasztása · **nincs** teljes profil last-write-wins felülírás · policy-verzió
eltérés és felülíró (superseding) nyugta kezelése · fiók-kikapcsolt állapotban SEMMILYEN
hálózati kérés.

**NINCS benne (tilos):**

- A `backend/` bármely más moduljának módosítása; meglévő Alembic migráció átírása.
- Közösségi funkciók (Epic 9) — ez a kör csak a szerződést készíti elő.
- A felismerés vagy bármely gyakorlási adat felhőbe küldése — csak jutalom-nyugták mennek.
- `docs/adr/**` — az ADR 0319-et a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/gamification/data/sync/gamification_sync_contract.dart` | **ÚJ** — a verziózott szerződés |
| `lib/features/gamification/data/sync/ledger_merge_policy.dart` | **ÚJ** — az összefésülés |
| `lib/features/gamification/public.dart` | barrel-bővítés — CSAK export-sor |
| `backend/app/gamification/schemas.py` | **ÚJ** — a szerver-oldali sémák |
| `backend/app/gamification/service.py` | **ÚJ** — a szerver-oldali logika |
| `test/features/gamification/data/ledger_merge_policy_test.dart` | a §6 Dart cellái |
| `backend/tests/test_gamification_ledger.py` | a §6 backend cellái |

**Tilos zóna:** `backend/` MINDEN más fájlja (meglévő migráció, auth, settings) · `lib/features/` többi feature-e · `lib/features/gamification/` nem felsorolt fájljai · `lib/core/**` · `lib/app/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0319)

### 5.1 A SZERVER NEM FOGAD EL KLIENS-OLDALI ÖSSZESÍTETT XP-T

A kliens **nyugtákat** küld, nem összeget. A szerver a nyugtákból SAJÁT MAGA
számol összesítést. Egy `totalXp` mező elfogadása triviálisan hamisítható.

**NEM elfogadható gyengítés:** „gyorsítótárazott összeg” mező a kérésben, akár csak
ellenőrzésre. Ami a kérésben van, arra a szerver támaszkodni fog.

### 5.2 AZ ÖSSZEFÉSÜLÉS AZONOSÍTÓ-ALAPÚ, NEM last-write-wins

A két oldal főkönyve **unióként** fésülődik össze a főkönyv-azonosító és a
forrás-esemény azonosító alapján. A teljes profil felülírása a friss oldal javára
adatvesztést okoz — pontosan azt a hibaosztályt, amit a projekt a beállítás-szinkronon
már megmért.

**NEM elfogadható gyengítés:** „az újabb `updatedAt` nyer” a teljes profilra.

### 5.3 IGAZOLT ÉS NEM IGAZOLT — két külön státusz

A lokálisan keletkezett nyugta `unverified`; a szerver által visszaigazolt
`verified`. A felület mindkettőt mutathatja, de a különbség **auditálható** marad.
Ez a Kör 22 közösségi felhasználásának feltétele.

### 5.4 FIÓK KIKAPCSOLVA → NULLA HÁLÓZATI KÉRÉS

Ha a felhasználó nincs bejelentkezve vagy kikapcsolta a szinkront, a réteg
**egyetlen** kérést sem indít — nem is próbálkozik és nem sorol be. A termék offline
teljes értékű.

### 5.5 A SZERZŐDÉS VERZIÓZOTT; a policy-eltérés kezelt

Eltérő policy-verziójú nyugta nem dobódik el és nem számolódik újra: megőrződik,
és a felülíró (superseding) nyugta explicit hivatkozással váltja le.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A szinkron kétszeri futtatása után az összes XP VÁLTOZATLAN (nincs duplázás) | `ledger_merge_policy_test.dart` — idempotencia-cella |
| A2 | A szerver ELUTASÍTJA a kliens által küldött összesített XP-t | `backend/tests/test_gamification_ledger.py` |
| A3 | Az összefésülés unió-alapú: egyik oldal bejegyzése sem vész el | `ledger_merge_policy_test.dart` — unió-mátrix |
| A4 | A lokális `unverified` és a szerver `verified` státusz megkülönböztethető és auditálható | `ledger_merge_policy_test.dart` |
| A5 | Kijelentkezett / kikapcsolt szinkron esetén NULLA hálózati kérés indul | `ledger_merge_policy_test.dart` — hálózat-cella |
| A6 | Eltérő policy-verziójú nyugta megőrződik; a felülíró nyugta explicit hivatkozással vált le | `ledger_merge_policy_test.dart` |
| A7 | A szerződés verziózott; ismeretlen verzió hibát ad | `ledger_merge_policy_test.dart` + `backend/tests/test_gamification_ledger.py` |
| A8 | A lokális offline működés teljes marad (a szinkron nem előfeltétel) | `ledger_merge_policy_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A kérés `totalXp` mezőt tartalmaz, és a szerver elfogadja | **A2** |
| A profil last-write-wins felülírással szinkronizál | **A3** (az unió-mátrix elveszít bejegyzést) |
| A `verified` státusz lokálisan is beállítható | **A4** |
| Kijelentkezve is indul kérés (akár csak „ellenőrzésre”) | **A5** |
| Az eltérő policy-verziójú nyugta eldobódik | **A6** |
| A szinkron dedupja csak a főkönyv-azonosítón | **A1** (a forrás-esemény azonosító nélkül duplikál) |

**A küszöb három kötelező cellája** (az összefésülés dedup-kulcsa (főkönyv-azonosító ÉS forrás-esemény azonosító)):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb **alatt** | csak a főkönyv-azonosítóra dedupolunk | **DUPLIKÁL**: két eszközön külön azonosítóval keletkezett, de UGYANARRA az eseményre mutató nyugta kétszer számít — A1 PIROS |
| **rajta** (a küszöbön) | mindkét kulcsra dedupolunk (a specifikált állapot) | **HELYES**: az azonos forrás-eseményű nyugták egyesülnek, az összes XP nem nő |
| a küszöb **fölött** | csak a forrás-esemény azonosítóra dedupolunk | **ADATVESZTÉS**: két legitim, eltérő forrás-eseményű nyugta egyesülne, ha az azonosító ütközik — A3 PIROS |

A hármas tömören: **alatt** → elutasít · **rajta** → az §6.1 tábla dönti el · **fölött** → elfogad.

A határ **a **rajta** cellához tartozik (inkluzív) — a fenti táblázat „rajta” sora mondja ki, melyik oldal nyer**.

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** dedupolj csak a főkönyv-azonosítóra, futtasd a Dart gate-et → az **A1**
idempotencia-cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/gamification/data/ledger_merge_policy_test.dart
```

A backend oldal külön, önálló parancs (NEM láncolva):

```bash
python3 -m pytest backend/tests/test_gamification_ledger.py -q
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

1. `gamification_sync_contract.dart` — a verziózott fel-/letöltési szerződés (nyugták, NEM összegek).
2. `ledger_merge_policy.dart` — unió-alapú összefésülés kettős dedup-kulccsal.
3. Az `unverified` / `verified` státusz szétválasztása.
4. A fiók-kikapcsolt ág: nulla hálózati kérés.
5. `backend/app/gamification/schemas.py` — a sémák, `totalXp` bemenet NÉLKÜL.
6. `backend/app/gamification/service.py` — szerver-oldali összegzés a nyugtákból.
7. A backend teszt (`backend/tests/test_gamification_ledger.py`).
8. A valódi-sértés próba §10-be; a §7 mindkét parancsa KÜLÖN futtatva.

## 9. Kockázatok

- **A kliens-összeg elfogadása.** Kényelmes és triviálisan hamisítható; a főkönyv teljes hitelességét viszi (A2).
- **A last-write-wins profil.** A projekt által MÉRT néma adatvesztés-osztály, most a jutalmakon (A3).
- **A „csak egy ellenőrző kérés” kijelentkezve.** Az offline ígéret megsértése, és a hálózat-cella fogja (A5).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
