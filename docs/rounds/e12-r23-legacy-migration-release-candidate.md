# E12-R23 — Legacy user migration release candidate

- **Státusz:** PREPARED (előre megírva 2026-08-27, kód olvasva: `main @ 9ca4a0dc`)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 23
- **Kör-azonosító:** `E12-R23`
- **Branch:** `<motor>/e12-r23-legacy-migration-release-candidate`
- **Előfeltétel:** `E12-R11` merge-elve (a frissítési folyam az e2e harness determinisztikus profilján fut)
- **Brief szerzője:** Claude (Opus 5)
- **Előre kiosztott ADR:** `ADR 0462` — a szám FOGLALT (Chapter 12 batch-tartomány).

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "legacy migration upgrade fixture interruption data loss recovery"` → **[ADR 0350](../adr/0350-legacy-practice-backfill-identity-zero-xp-and-checkpoint.md)** (stabil identitás, nulla XP, perzisztált checkpoint) és **[ADR 0117](../adr/0117-song-storage-migrator-boundary.md)** (song storage migrátor: legacy olvasási út, checkpoint, setlist scope). A megszakítás-tűrés MÁR eldöntött minta — a kör ezt MÉRI végig minden migrátoron.

> ⚠ **Pre-flight (indítás előtt KÖTELEZŐ):** listázd újra a fán MÉRT migrátorokat (a megíráskor: `lib/core/storage/storage_migrator.dart`, `features/gamification/data/migration/{gamification_migrator,legacy_streak_migrator,legacy_practice_adapter}.dart`, `features/audio_analysis/data/migration/legacy_library_migrator.dart`, `features/practice_generator/data/local/practice_plan_migrator.dart`) — a fixture-készletnek MINDEGYIKRE kell bemenetet adnia.

## 0.0 A recovery felület MÁR létezik

A `lib/app/bootstrap/recovery_screen.dart` a fán van, és a bootstrap-hiba útját szolgálja. A kör tehát NEM hoz új képernyőt (a `ui_inventory` szám nem mozdul); azt méri, hogy sikertelen migráció esetén a felhasználó ERRE az útra kerül, és nem üres profilra.

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "test/fixtures/migrations/README.md",
  "test/fixtures/migrations/legacy_v1_storage.json",
  "test/fixtures/migrations/legacy_v2_storage.json",
  "test/fixtures/migrations/corrupted_storage.json",
  "test/e2e/upgrade_migration_test.dart",
  "docs/release/client-migration.md",
  "docs/rounds/e12-r23-legacy-migration-release-candidate.md",
]
gate_tests = [
  "test/e2e/upgrade_migration_test.dart",
  "test/ui/ui_inventory_test.dart",
]
native_gate = false
```

**Kockázat = high, indoklás:** a kör tárgya a felhasználói adat migrációja — a mérce hibája adatvesztést hagyhat felfedezetlenül. A `security-reviewer` futtatása a review-ban KÖTELEZŐ (adat-integritás és tárolási határ).

## 0. Kör-jelzés és STOP-protokoll

```bash
tools/codex-signal.sh progress "<egy sor>"
tools/codex-signal.sh done "<egy sor>"
tools/codex-signal.sh stopped "<egy sor>"
tools/codex-signal.sh blocked "<egy sor>"
```

**STOP-protokoll:** ha egy fixture MÉRT adatvesztést mutat, a kimenet a `stopped` jelzés és jelentés — a migrátor javítása külön, review-zott kör.

## 1. Cél

Bizonyítani, hogy minden ismert legacy tárolási állapotból a frissítés adatvesztés nélkül, megszakítás után folytathatóan végigmegy — sikertelenség esetén pedig a felhasználó recovery-útra kerül, nem csendben üres profilra.

## 2. Jelenlegi állapot — mért tények

- **Hat** migrátor él a fán (lásd a pre-flight listát), mindegyik saját tesztekkel; **egységes, verzió szerinti legacy fixture-készlet NINCS**.
- `lib/app/bootstrap/recovery_screen.dart` **létezik** (bootstrap-hiba út).
- `test/fixtures/migrations/` **nem létezik**; `test/e2e/` a Kör 11 után igen.
- ADR 0350/0117: checkpoint-alapú, megszakítás-tűrő migráció a MÉRT minta.
- `test/ui/ui_inventory_test.dart` egzakt képernyőszámot pinnel — a kör nem mozdítja el.

## 3. Scope

**Benne van:** verzió szerinti legacy fixture-készlet (`legacy_v1_storage.json`, `legacy_v2_storage.json`, `corrupted_storage.json` + README a származásukról) · `test/e2e/upgrade_migration_test.dart`: minden fixture-ből teljes app-indítás → migráció → adat-invariánsok (rekordszám, azonosítók, XP-egyenleg VÁLTOZATLAN) · megszakítás (a migráció közepén megölt folyamat) → új indítás → FOLYTATÁS, nem újrakezdés · alacsony tárhely és sérült bemenet → recovery-út, NEM üres profil · `docs/release/client-migration.md` (mit migrálunk, mit nem, mi a rollback KORLÁTJA).

**NINCS benne (tilos):**

- Bármely migrátor vagy `lib/**` fájl módosítása.
- Új képernyő.
- Valódi felhasználói adat fixture-ként (a fixture-ök szintetikusak, a README rögzíti a származást).
- `docs/adr/**` — az ADR 0462-t a Claude írja.

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `test/fixtures/migrations/README.md` | ÚJ — a fixture-ök származása és sémája |
| `test/fixtures/migrations/legacy_v1_storage.json` | ÚJ — legacy v1 bemenet |
| `test/fixtures/migrations/legacy_v2_storage.json` | ÚJ — legacy v2 bemenet |
| `test/fixtures/migrations/corrupted_storage.json` | ÚJ — sérült bemenet |
| `test/e2e/upgrade_migration_test.dart` | a §6 cellái |
| `docs/release/client-migration.md` | ÚJ — a migrációs riport és korlátok |

**Tilos zóna:** `lib/**` · `test/fixtures/` egyéb könyvtárai · `test/ui/goldens/**` · `docs/adr/**` · `.github/**`

## 5. Kötött architekturális döntések (ADR 0462)

### 5.1 A „nincs adatvesztés" invariáns SZÁMSZERŰ

A cella a rekordszámot, az azonosító-halmazt és az XP-egyenleget hasonlítja össze migráció előtt/után. **NEM elfogadható gyengítés:** „az app elindul, tehát rendben" — a néma adatvesztés pontosan így marad rejtve.

### 5.2 A sikertelen migráció SOHA nem indít üres profilt

A felhasználó a `RecoveryScreen`-re kerül, a nyers adat érintetlenül marad. **NEM elfogadható gyengítés:** „tiszta lappal indulás" fallback.

### 5.3 A megszakítás után FOLYTATÁS van, nem újrakezdés

A checkpoint (ADR 0350/0117) érvényes marad. **NEM elfogadható gyengítés:** teljes újrafuttatás, ami duplikálná a már migrált rekordokat.

## 6. Acceptance criteria

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | Mindhárom fixture-ből a frissítés lefut, és az adat-invariánsok (rekordszám, azonosítók, XP) VÁLTOZATLANOK | `upgrade_migration_test.dart` |
| A2 | A migráció közbeni megszakítás után az új indítás FOLYTAT (nincs duplikáció) | `upgrade_migration_test.dart` |
| A3 | Sérült bemenet → `RecoveryScreen`, nem üres profil | `upgrade_migration_test.dart` |
| A4 | Alacsony tárhely szimulációja mellett a migráció kontrollált hibát ad, adat nélkül elveszve | `upgrade_migration_test.dart` |
| A5 | A migrációs riport exportálható és tartalmazza a migrált rekordszámokat | `upgrade_migration_test.dart` |
| A6 | A képernyőszám VÁLTOZATLAN | `test/ui/ui_inventory_test.dart` a §7 gate-ben |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA |
|---|---|
| A cella csak azt méri, hogy az app elindul | A1 |
| A megszakítás után a migráció elölről kezd (duplikáció) | A2 |
| A sérült bemenet üres profilt indít | A3 |
| A riport csak „sikeres" jelzést ad, számok nélkül | A5 |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** vedd ki az XP-egyenleg összehasonlítást az A1 cellából, és futtasd a §7 gate-et egy szándékosan hiányos fixture-rel → a cellának a hiánytól FÜGGETLENÜL zöldnek kell lennie, ami bizonyítja, hogy az invariáns-ellenőrzés valóban a mérce → állítsd vissza, és dokumentáld mindkét kimenetet.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/e2e/upgrade_migration_test.dart test/ui/ui_inventory_test.dart
```

## 8. Implementációs sorrend

1. A MÉRÉS: a hat migrátor bemeneti sémái.
2. A három fixture + README.
3. `test/e2e/upgrade_migration_test.dart` — A1 (számszerű invariánsok) ELŐSZÖR.
4. A2–A4 cellák (megszakítás, sérülés, tárhely).
5. `docs/release/client-migration.md` + a próba a §10-be.

## 9. Kockázatok

- **Néma adatvesztés.** A legsúlyosabb, és csak számszerű invariánssal fogható (A1).
- **Duplikáció resume-nál.** A checkpoint téves kezelése kétszer migrál (A2).
- **Fixture-hitelesség.** Egy kitalált legacy formátum semmit nem bizonyít — a README rögzítse, melyik kör/verzió írta azt a sémát.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
