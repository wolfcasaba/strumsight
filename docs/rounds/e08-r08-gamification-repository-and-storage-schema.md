# E08-R08 — Gamification repository és tároló-séma

- **Státusz:** PREPARED (előre megírva 2026-08-18, kód olvasva: `main @ ea6569fb`)
- **Típus:** Chapter 9 (Epic 8 — Gamification), Kör 8
- **Kör-azonosító:** `E08-R08`
- **Branch:** `<motor>/e08-r08-gamification-repository-and-storage-schema`
- **Előfeltétel:** `E08-R07` merge-elve (profil-projekció)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0306` — a szám FOGLALT. Az ADR-t a Claude írja meg a
  kör indítási pre-flightjában a §5 döntéseiből; az implementer a `docs/adr/`-t
  NEM érinti (TILOS zóna).

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** olvasd újra a `lib/core/storage/` TÉNYLEGES felületét (`json_document_store.dart`, `storage_keys.dart`, `storage_providers.dart`) és az R07 profil-pillanatképét — a séma ezekre épül. Eltérésnél
> §0.0 brief-revízió, NEM csendes lista-tágítás.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "lib/features/gamification/data/gamification_repository.dart",
  "lib/features/gamification/data/local_gamification_repository.dart",
  "lib/features/gamification/data/gamification_storage_schema.dart",
  "lib/features/gamification/public.dart",
  "test/features/gamification/data/gamification_repository_test.dart",
  "test/core/architecture_dependency_test.dart",
  "docs/rounds/e08-r08-gamification-repository-and-storage-schema.md",
]
gate_tests = [
  "test/features/gamification/data/gamification_repository_test.dart",
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

Központosítsd a gamifikáció perzisztenciáját verziózott, hamisítható (fake-elhető)
repositorykba: profil-pillanatkép, katalógus-verzió, jutalom-postaláda és migrációs
állapot — mind EGY helyen, atomikus cserével és sérülés-helyreállítással.

## 2. Jelenlegi állapot — mért tények

- Az R03 a főkönyvet, az R04 az outboxot, az R07 a profil-projekciót hozta; ez a kör a KÖZÖS tárolási réteget.
- `lib/core/storage/storage_keys.dart` a kulcsok kanonikus helye — az új kulcsok ide **nem** kerülhetnek ebben a körben (`lib/core/**` tilos zóna); a gamifikációs séma a saját fájljában él.
- A `streak_repository.dart` (47 sor) mintája: `JsonDocumentStore` + `legacyKey`, sérült bájtnál `null`, néma felülírás nélkül.
- `test/core/architecture_dependency_test.dart` (467 sor) tiltja a réteg-sértéseket — a `SharedPreferences` közvetlen használatát az application/presentation rétegben ide kell felvenni.

## 3. Scope

**Benne van:** a profil-pillanatkép, a katalógus-verzió, a postaláda és a migrációs állapot tárolásának
sémája · a Chapter 2 kulcs-érték absztrakciójának használata · **atomikus** pillanatkép-csere
és sérülés-helyreállítás · figyelő (watch) adatfolyam a Riverpod-kompatibilis frissítéshez ·
megőrzési és méretkorlátok dokumentálása · architektúra-guard a közvetlen `SharedPreferences`
használat ellen.

**NINCS benne (tilos):**

- Új kulcs felvétele a `lib/core/storage/storage_keys.dart`-ba — `lib/core/**` TILOS zóna ebben a körben.
- Legacy migráció (Kör 9/10), UI, hálózati szinkron (Kör 28).
- A meglévő `streak_repository.dart` vagy `practice_log_repository.dart` átírása.
- `docs/adr/**` — az ADR 0306-ot a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `lib/features/gamification/data/gamification_repository.dart` | **ÚJ** — az interfész |
| `lib/features/gamification/data/local_gamification_repository.dart` | **ÚJ** — a lokális implementáció |
| `lib/features/gamification/data/gamification_storage_schema.dart` | **ÚJ** — a séma, verziókkal és megőrzési korlátokkal |
| `lib/features/gamification/public.dart` | barrel-bővítés — CSAK export-sor |
| `test/features/gamification/data/gamification_repository_test.dart` | a §6 cellái |
| `test/core/architecture_dependency_test.dart` | a `SharedPreferences`-tilalom guardja |

**Tilos zóna:** `lib/features/` MINDEN más feature-e · `lib/core/**` · `lib/app/**` · `docs/adr/**` · `docs/sdd/**` · `tools/**` · `.github/**` · `backend/**`

## 5. Kötött architekturális döntések (ADR 0306)

### 5.1 A pillanatkép-csere ATOMIKUS — nincs félig írt profil

A profil cseréje vagy teljesen megtörténik, vagy egyáltalán nem. A megszakadt
írás után a KORÁBBI, ép pillanatkép marad érvényben.

**NEM elfogadható gyengítés:** helyben módosítás („előbb töröljük, aztán írjuk”).
Egy crash pontosan a kettő között hagyja a felhasználót profil nélkül.

### 5.2 NINCS adatvesztő fallback

Sérült vagy nem dekódolható tárolt adat esetén a válasz **nem** az újrainicializálás:
az ép bájtok érintetlenül maradnak, a hívó kap egy explicit „sérült” jelzést, és az állapot
diagnosztizálható. Ez a `streak_repository.dart` mai mintája.

**NEM elfogadható gyengítés:** `catch (_) { return Default(); }` — ez a projektben MÉRT
néma no-op hibaosztály (`CLAUDE.md`, Critical build gotchas).

### 5.3 A presentation és application réteg NEM lát `SharedPreferences`-t

A tárolás kizárólag a `data/` rétegen át megy. A guard ezt méri (A6) — enélkül a
kulcsok szétszóródnak, és a Kör 28 szinkronja nem tud egyetlen forrásból dolgozni.

### 5.4 Minden perzisztált modell VERZIÓZOTT

Minden tárolt dokumentumnak van `schemaVersion`-je; ismeretlen verzió explicit
hibát ad, nem csendes alapértelmezést (az R02 §5.1 elve, itt a tárolási rétegre).

### 5.5 Megőrzési és méretkorlátok KIMONDOTTAK

A séma megmondja, meddig és mekkora méretig tartunk adatot (postaláda, migrációs
napló). A korlátlan növekedés offline hónapok alatt tárhely-problémát okoz — és a korlátot
nem az implementáció „érzésre” választja, hanem a séma rögzíti.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A pillanatkép-csere atomikus: megszakított írás után a KORÁBBI ép profil marad | `gamification_repository_test.dart` — megszakítás-cella |
| A2 | Sérült tárolt adat NEM íródik felül, és explicit „sérült” jelzést ad | `gamification_repository_test.dart` |
| A3 | Minden perzisztált modell verziózott; ismeretlen verzió hibát ad | `gamification_repository_test.dart` — modellenként egy cella |
| A4 | A repository fake implementációval tesztelhető (az interfész nem szivárogtat tárolási típust) | `gamification_repository_test.dart` |
| A5 | Az application és presentation réteg NEM importál `SharedPreferences`-t | `architecture_dependency_test.dart` |
| A6 | A figyelő adatfolyam a változás után friss értéket ad | `gamification_repository_test.dart` |
| A7 | A megőrzési és méretkorlátok a sémában szerepelnek, és a korlát ÉRVÉNYESÜL | `gamification_repository_test.dart` — kapacitás-mátrix |
| A8 | A gamifikációs kulcsok EGY helyen (a sémában) definiáltak | review + `gamification_repository_test.dart` |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A csere „törlés + írás” párban | **A1** (a megszakítás-cella profil nélkül hagy) |
| `catch (_) { return Default(); }` a betöltésben | **A2** (a sérült adat felülíródik) |
| Az interfész `SharedPreferences` típust ad vissza | **A4** (nem fake-elhető) és **A5** |
| A postaláda korlátlan | **A7** (a kapacitás-mátrix fölső cellája) |
| A kulcsok a repository metódusaiba szórva | **A8** |
| Egy modell verzió nélkül tárolódik | **A3** |

**A küszöb három kötelező cellája** (a postaláda megőrzési korlátja (`inboxRetentionLimit`)):

| Cella | Bemenet | Elvárt |
|---|---|---|
| a küszöb **alatt** | `inboxRetentionLimit - 1` elem | mind megmarad, nincs nyesés |
| **rajta** (a küszöbön) | pontosan `inboxRetentionLimit` elem | **mind megmarad** — a korlát a MEGŐRZÖTT oldalhoz tartozik (inkluzív) |
| a küszöb **fölött** | `inboxRetentionLimit + 1` elem | a **legrégebbi** elem nyesődik; a nyesés ténye a diagnosztikában látszik |

A hármas tömören: **alatt** → elutasít · **rajta** → az §6.1 tábla dönti el · **fölött** → elfogad.

A határ **a **rajta** cellához tartozik (inkluzív) — a fenti táblázat „rajta” sora mondja ki, melyik oldal nyer**.

**Valódi-sértés próba (KÖTELEZŐ, §10-ben dokumentálva):** cseréld az atomikus pillanatkép-cserét „törlés + írás” párra, futtasd a gate-et →
az **A1** cellának PIROSNAK kell lennie → állítsd vissza.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/features/gamification/data/gamification_repository_test.dart test/core/architecture_dependency_test.dart
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

1. `gamification_storage_schema.dart` — dokumentum-típusok, verziók, megőrzési és méretkorlátok.
2. `gamification_repository.dart` — az interfész, tárolási típus szivárgása nélkül.
3. `local_gamification_repository.dart` — atomikus csere, sérülés-helyreállítás, figyelő adatfolyam.
4. A `SharedPreferences`-tilalom guardja az architektúra-tesztben.
5. A megőrzési korlát tényleges érvényesítése.
6. A `public.dart` export-sorai.
7. A valódi-sértés próba, §10-be dokumentálva.
8. `tools/round-gate.sh` a §7 szerint.

## 9. Kockázatok

- **A `catch (_) → Default()` reflex.** A projekt MÉRT néma no-op hibaosztálya; itt a felhasználó teljes gamifikációs előzményét jelenti (A2).
- **A `lib/core/storage/storage_keys.dart` „menet közbeni” bővítése.** Tilos zóna: a `lib/core/**` másik kör területe, és a scope-audit ezt fogja.
- **A korlátlan postaláda.** Nem itt fáj, hanem offline hónapok után, tárhely-panaszként (A7).

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
