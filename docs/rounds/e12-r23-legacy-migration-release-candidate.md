# E12-R23 — Legacy user migration release candidate

- **Státusz:** READY (pre-flight ÚJRAMÉRVE 2026-09-01, `main @ dcb73fa8` — lásd §0.0)
- **Típus:** Chapter 12 (Release Roadmap, Sprint Planning & Final Integration), Kör 23
- **Kör-azonosító:** `E12-R23`
- **Branch:** `<motor>/e12-r23-legacy-migration-release-candidate`
- **Előfeltétel:** `E12-R11` merge-elve (a frissítési folyam az e2e harness determinisztikus profilján fut)
- **Brief szerzője:** Claude (Opus 5)
- **ADR:** **`ADR 0487`** — a foglalótól kapott szám (`tools/round-slots.py reserve-adr`).
  A brief eredeti `0462`-je elavult batch-előfoglalás volt; lásd §0.0/R1.

**Visszakeresett előzmény:** `node tools/knowledge-rag.mjs --corpus lessons,halts,adr --top 5 "legacy migration upgrade fixture interruption data loss recovery"` → **[ADR 0350](../adr/0350-legacy-practice-backfill-identity-zero-xp-and-checkpoint.md)** (stabil identitás, nulla XP, perzisztált checkpoint) és **[ADR 0117](../adr/0117-song-storage-migrator-boundary.md)** (song storage migrátor: legacy olvasási út, checkpoint, setlist scope). A megszakítás-tűrés MÁR eldöntött minta — a kör ezt MÉRI végig minden migrátoron.

> ⚠ **A pre-flight MEGTÖRTÉNT (2026-09-01) — az eredménye a §0.0.** A migrátor-leltár
> újramérve (§0.0/R6): 12+ migrátor/adapter él a fán, de boot-időben CSAK az
> `appStorageMigrations` fut, ezért a fixture-készlet a boot-úti legacy kulcsokat eteti.

## 0.0 Pre-flight brief-revízió (Claude, 2026-09-01, `main @ dcb73fa8`)

A brief 2026-08-27-én készült; az alábbi hat állítását a pre-flight ÚJRAMÉRTE a fán, és
négy közülük megdőlt. A revízió az ADR 0087 §2 szerint a kör SAJÁT, még nem merge-elt
artefaktumát érinti, tehát az orchestrátor hatáskörében van.

### R1 — Az ADR száma `0462` → **`0487`**

```
tools/round-slots.py reserve-adr --round E12-R23   →  0487   (exit 0)
ls docs/adr/ | grep -E '^0462'                     →  (üres)
ls docs/adr/ | sort | tail -1                      →  0486-beta-distribution-consent-…
```

A Chapter 12 batch előre kiosztott számai elcsúsztak (E12-R21 brief `0460` → valóság
`0485`, E12-R22 brief `0461` → valóság `0486`). A prompt §1.0.1 szerint a sorszám
forrása a **foglaló**, nem az `ls` és nem a brief. A kör ADR-je: **`ADR 0487`**.

### R2 — A három ÚJ fixture a release fixture-manifest kapuját BUKTATNÁ (blokkoló)

Mérve: `test/tooling/fixture_manifest_test.dart` A1 cellája a valós fán futtatja a
`checkFixtureManifest`-et, és **egzakt 48 adatfájlt** pinnel
(`expect(report.entries, hasLength(48))`), a manifestet pedig a fa ellen tisztának várja
(ADR 0473 D1/D2: „a korpuszt a fájlfa definiálja, nem a manifest"). A bejáró
(`tool/check_fixture_manifest.dart:435,438`) a `*.dart`-ot és a `README.md`-t kihagyja, a
`*.json`-t NEM. A brief három ÚJ `.json` fixture-t ír elő `test/fixtures/` alá →
`48 → 51`, és három `fixtureMissingManifestEntry` lelet → a kör a **teljes CI-suite-ban
garantáltan piros** lenne, miközben a brief `allowed_paths`-a sem a manifestet, sem a
pinnelt cellát nem engedte.

**Feloldás (precedens: [L296](../LESSONS.md), E07-R15 — a szűk, dispatch ELŐTTI
allowlist-bővítés a szentesített út, nem a halt):** az `allowed_paths` szűken bővül a
`test/fixtures/manifest.json` és a `test/tooling/fixture_manifest_test.dart` fájlokkal,
a `gate_tests` pedig a manifest-cellával — a kör tehát **MÉRI** a regisztrációt, nem
megkerüli. Ez nem a mérce lazítása: az ADR 0473 szerződése épp azt írja elő, hogy minden
új fixture manifest-bejegyzést kapjon (`sha256`, `bytes`, `license`, `source`,
`containsUserData: false`).

### R3 — Az A3 „sérült bemenet → `RecoveryScreen`" a fán ELÉRHETETLEN (blokkoló)

Ez a prompt §1/1. mintája: a cél-státuszt az ÁLLAPOTGÉP inputjain kell mérni, nem a
réteg-diagramon. A mért hívási lánc **három** ponton mond ellent a briefnek:

1. **`StorageMigrator.migrate()` SOHA nem dob** (`lib/core/storage/storage_migrator.dart:265-283`):
   migrációnként `try/catch`, és hiba esetén `StorageMigrationReport(failure: …)`-t ad
   vissza. A doc-comment ki is mondja: *„a broken migration must never be a broken app"*.
2. **`AppBootstrap.run` eldobja a report visszatérési értékét**
   (`lib/app/bootstrap/app_bootstrap.dart:84`: `await StorageMigrator(…).migrate();`),
   ezért sérült migrációs bemenet esetén is **`BootstrapSuccess`** keletkezik. A
   `BootstrapFailure` ÁLTAL produkált inputok mérve kizárólag: ismeretlen environment
   define, `openStore` → `Failure`, és a try-blokk váratlan kivétele.
3. **`BootstrapFailure` esetén sem a `RecoveryScreen` jön**: `lib/main.dart:57-58` a
   **`BootstrapFailureApp`**-ot futtatja. A `RecoveryScreen`-t egyedül az
   `AppRoutes.recovery` GoRoute építi (`app_router.dart:245`), és a `lib/` fában
   **egyetlen** navigáció sem mutat rá (`grep -rn "AppRoutes.recovery" lib/` → csak a
   route-definíció és egy doc-comment).

A brief §3 a `lib/**` MINDEN módosítását tiltja, tehát az A3 eredeti szövege csak
tilos-zóna-sértéssel (H3) vagy egy lezárt kör viselkedésének átírásával (H2) lenne
teljesíthető. **Az A3 ezért újraszabva** — a §5.2 VALÓDI védelmét (soha nem üres profil,
a nyers adat érintetlen) számszerű invariánssá téve, a `RecoveryScreen`-t pedig a MÉRT
elérhetőségén pinnelve. A gyengítés tilalma megmarad: az „elindul, tehát rendben"
továbbra sem elfogadható.

### R4 — Az e2e harness NEM futtat bootstrapot és migrációt

`test/support/e2e_harness.dart`-ban nincs `AppBootstrap`, nincs `StorageMigrator`
(`grep` → 0 találat): a `bootE2eApp` közvetlenül a `StrumSightApp`-ot pumpálja egy
`InMemoryKeyValueStore` fölé. A harness NINCS az `allowed_paths`-on, és nem is kerül rá.
**A kör tesztfájlja maga hívja** az `AppBootstrap.run(openStore:, migrations:,
loadVersion:, loadOnboardingSeen:)` injektálható belépőjét a fixture-ből feltöltött
store-ral, és csak UTÁNA bootol appot ugyanazon a store-on a meglévő harnesszel
(`InMemoryKeyValueStore` a harnessből re-exportált: `preference_store.dart:9`). Így sem
`lib/**`, sem a harness nem módosul.

### R5 — Az A5 „exportálható riport": nincs export-felület, a riport in-memory

`StorageMigrationReport` (`storage_migrator.dart:210-231`) mezői: `fromVersion`,
`toVersion`, `applied` (id-lista), `failure` — **nincs** `toJson`/export. A
`LegacyMigrationReport` (song_trainer) issue-alapú, szintén nem export. Új export
`lib/**`-ot igényelne → tilos. **Az A5 újraszabva:** a riport SZÁMSZERŰ tartalmát méri
(migrált rekordszám kulcsonként, `fromVersion`/`toVersion`, az `applied` id-lista), és a
dokumentált kimeneti felület a `docs/release/client-migration.md`. A §6.1 sértése
(„csak »sikeres« jelzés, számok nélkül") ettől változatlanul PIROS.

### R6 — A migrátor-leltár nem „hat", és csak EGY fut boot-időben

A fán mérve 12+ migrátor/adapter fájl él. A **boot-úton** azonban kizárólag az
`appStorageMigrations` lista fut (`StorageMigrator`, 22 lépés, E01-R06/R07); a
gamification-, song-storage-, library- és practice-plan-migrátorok provider/use-case
úton, nem bootstrapból indulnak. A fixture-készletnek ezért a **boot-úti** legacy
kulcsokat (`LegacyStorageKeys`, `storage_keys.dart:167-188`) kell etetnie; a
feature-migrátorok bemenete a v1/v2 fixture user-content dokumentumaiban utazik, és a
kör NEM vállalja mind a 12 migrátor külön meghajtását — azt a saját tesztjeik mérik.

### R7 — Ami a briefből VÁLTOZATLANUL igaz

- `lib/app/bootstrap/recovery_screen.dart` létezik; a kör NEM hoz új képernyőt.
- `test/fixtures/migrations/` nem létezik; `test/e2e/` létezik (3 folyam a Kör 11 után).
- `test/ui/ui_inventory_test.dart` egzakt képernyőszámot pinnel — nem mozdul.
- ADR 0350/0117 checkpoint-mintája a mérce alapja.

**Visszakeresés (ADR 0312, szűkítve ELŐSZÖR):**
`--corpus lessons,halts,adr` → ADR 0350 (emb#1), ADR 0239 (emb#2: „a migráció részleges
hiba után folytatható… az ismételt futás nem duplikál ID alapján"), ADR 0117 (emb#3);
`--corpus lessons,halts` → E12-R12 (a fixture-manifest kör, R2 gyökere), E12-R11 (a
harness kör, R4 gyökere), **L296** (a fixture-scope pre-flight bővítés precedense).

```ai-router
schema_version = 1
risk = "high"
allowed_paths = [
  "test/fixtures/migrations/README.md",
  "test/fixtures/migrations/legacy_v1_storage.json",
  "test/fixtures/migrations/legacy_v2_storage.json",
  "test/fixtures/migrations/corrupted_storage.json",
  "test/fixtures/manifest.json",
  "test/tooling/fixture_manifest_test.dart",
  "test/e2e/upgrade_migration_test.dart",
  "docs/release/client-migration.md",
  "docs/rounds/e12-r23-legacy-migration-release-candidate.md",
]
gate_tests = [
  "test/e2e/upgrade_migration_test.dart",
  "test/tooling/fixture_manifest_test.dart",
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

> A §0.0 revízió az alábbi lista négy pontját ÚJRAMÉRTE; ami ott másképp szerepel, ott a §0.0 az érvényes.

- 12+ migrátor/adapter él a fán, de **boot-időben csak az `appStorageMigrations` fut**
  (`StorageMigrator`, §0.0/R6); **egységes, verzió szerinti legacy fixture-készlet NINCS**.
- `lib/app/bootstrap/recovery_screen.dart` **létezik**, de a `lib/` fában **semmi nem
  navigál rá**, és a bootstrap-hiba a `BootstrapFailureApp`-ot futtatja (§0.0/R3).
- `StorageMigrator.migrate()` **nem dob**, riportot ad vissza; `AppBootstrap` eldobja azt
  → sérült migráció esetén is `BootstrapSuccess` (§0.0/R3).
- `test/fixtures/migrations/` **nem létezik**; `test/e2e/` a Kör 11 után igen, de a
  harness **nem futtat bootstrapot/migrációt** (§0.0/R4).
- `test/tooling/fixture_manifest_test.dart` **egzakt 48 fixture-fájlt** pinnel, és a
  manifestet a fa ellen tisztának várja (§0.0/R2).
- ADR 0350/0117/0239: checkpoint-alapú, megszakítás-tűrő, ID-alapon nem duplikáló
  migráció a MÉRT minta.
- `test/ui/ui_inventory_test.dart` egzakt képernyőszámot pinnel — a kör nem mozdítja el.

## 3. Scope

**Benne van:** verzió szerinti legacy fixture-készlet (`legacy_v1_storage.json`, `legacy_v2_storage.json`, `corrupted_storage.json` + README a származásukról, manifest-regisztrációval) · `test/e2e/upgrade_migration_test.dart`: fixture-enként `AppBootstrap.run` → migráció → adat-invariánsok (rekordszám, azonosítók, XP/streak-egyenleg VÁLTOZATLAN), majd app-boot ugyanazon a store-on · megszakítás (az N-edik íráson dobó store) → új indítás → FOLYTATÁS, nem újrakezdés · sérült bemenet → kontrollált riport-hiba, érintetlen nyers adat, NEM üres profil (§0.0/R3) · alacsony tárhely (`openStore` → `Failure`) → `BootstrapFailure`, adatvesztés nélkül · `docs/release/client-migration.md` (mit migrálunk, mit nem, mi a rollback KORLÁTJA).

**NINCS benne (tilos):**

- Bármely migrátor vagy `lib/**` fájl módosítása.
- Új képernyő.
- Valódi felhasználói adat fixture-ként (a fixture-ök szintetikusak, a README rögzíti a származást).
- `docs/adr/**` — az ADR 0487-et a Claude írja (a pre-flightban megírva).
- `test/support/**` — az e2e harness NEM módosul (§0.0/R4).
- `tool/check_fixture_manifest.dart` — a bejáró logikája nem módosul (§0.0/R2).

## 4. Engedélyezett fájlok

| Útvonal | Indok |
|---|---|
| `test/fixtures/migrations/README.md` | ÚJ — a fixture-ök származása és sémája |
| `test/fixtures/migrations/legacy_v1_storage.json` | ÚJ — legacy v1 bemenet |
| `test/fixtures/migrations/legacy_v2_storage.json` | ÚJ — legacy v2 bemenet |
| `test/fixtures/migrations/corrupted_storage.json` | ÚJ — sérült bemenet |
| `test/fixtures/manifest.json` | §0.0/R2 — a három ÚJ fixture ADR 0473 szerinti regisztrációja (`bytes`, `sha256`, `license`, `source`, `containsUserData: false`) |
| `test/tooling/fixture_manifest_test.dart` | §0.0/R2 — **kizárólag** a pinnelt darabszám `48` → `51`; a cellák logikája NEM módosulhat |
| `test/e2e/upgrade_migration_test.dart` | a §6 cellái |
| `docs/release/client-migration.md` | ÚJ — a migrációs riport és korlátok |

**Tilos zóna:** `lib/**` · `test/support/**` (a harness NEM módosul, §0.0/R4) ·
`test/fixtures/` egyéb könyvtárai · `test/ui/goldens/**` · `docs/adr/**` · `.github/**` ·
`tool/check_fixture_manifest.dart` (a bejáró LOGIKÁJA nem módosul, csak a manifest tartalma)

## 5. Kötött architekturális döntések (ADR 0487)

### 5.1 A „nincs adatvesztés" invariáns SZÁMSZERŰ

A cella a rekordszámot, az azonosító-halmazt és az XP-egyenleget hasonlítja össze migráció előtt/után. **NEM elfogadható gyengítés:** „az app elindul, tehát rendben" — a néma adatvesztés pontosan így marad rejtve.

### 5.2 A sikertelen migráció SOHA nem indít üres profilt

**A §0.0/R3 mérése szerint újraszabva.** A mért, merge-elt szerződés: a hibás migráció
NEM töri el az appot — a `StorageMigrator` riportot ad (`failure != null`), a
`schemaVersion` a bukott lépés ELŐTTI értéken marad, a nyers legacy adat **bitre
érintetlen**, és az app a már meglévő értékein indul. **NEM elfogadható gyengítés:**
„tiszta lappal indulás" fallback, néma kulcs-törlés, vagy egy olyan cella, amely csak az
app elindulását nézi. A `RecoveryScreen`/safe-mode felület a MÉRT elérhetőségén
pinnelendő (`AppRoutes.recovery` route létezik; bootstrap-hibán a `BootstrapFailureApp`
jön) — a felület megváltoztatása KÜLÖN, review-zott kör, `lib/**` érintéssel.

### 5.3 A megszakítás után FOLYTATÁS van, nem újrakezdés

A checkpoint (ADR 0350/0117) érvényes marad. **NEM elfogadható gyengítés:** teljes újrafuttatás, ami duplikálná a már migrált rekordokat.

## 6. Acceptance criteria

A cellák a §0.0/R3–R5 mérése szerint a MÉRT belépőket hajtják: a teszt maga hívja az
`AppBootstrap.run(openStore:, migrations:, loadVersion:, loadOnboardingSeen:)`
injektálható belépőjét a fixture-ből feltöltött `InMemoryKeyValueStore` fölött, majd —
ahol a cella az app viselkedését is méri — ugyanazon a store-on bootol a meglévő
`bootE2eApp` harnesszel. Sem `lib/**`, sem `test/support/**` nem módosul.

| # | Kritérium | Bizonyíték |
|---|---|---|
| A1 | A `legacy_v1` és `legacy_v2` fixture-ből a frissítés VÉGIGFUT (`report.isComplete`, `toVersion == appStorageMigrations.last.version`), és az adat-invariánsok SZÁMSZERŰEN változatlanok: a felhasználói dokumentumok **rekordszáma**, az **azonosító-halmaz** és az **XP/streak-egyenleg** migráció előtt/után azonos | `upgrade_migration_test.dart` |
| A2 | A migráció közepén megszakadó futás (a store az N-edik írásnál dob) után az ÚJ indítás a `schemaVersion`-tól FOLYTAT: a már migrált kulcsok nem íródnak újra, az azonosító-halmaz duplikátum-mentes, a rekordszám ugyanaz, mint a megszakítás nélküli futásé | `upgrade_migration_test.dart` |
| A3 | Sérült bemenet (`corrupted_storage.json`) esetén a migráció kontrollált hibát ad (`report.failure != null`, `toVersion == fromVersion`), a **nyers legacy adat bitre érintetlen** marad, és a rákövetkező app-boot NEM üres profilt mutat, hanem a meglévő értékeket; a safe-mode felület a mért elérhetőségén pinnelve (`AppRoutes.recovery` route létezik, bootstrap-hibán `BootstrapFailureApp`) | `upgrade_migration_test.dart` |
| A4 | Alacsony tárhely / megnyithatatlan store szimulációja (`openStore` → `Failure`) esetén a bootstrap **`BootstrapFailure`**-t ad a storage-unavailable indokkal, és a store egyetlen kulcsa sem íródik/törlődik | `upgrade_migration_test.dart` |
| A5 | A migrációs riport SZÁMSZERŰ: `fromVersion`, `toVersion` és az `applied` id-lista fixture-enként pinnelve, és a migrált rekordszámok kulcsonként ellenőrizve; a dokumentált kimeneti felület a `docs/release/client-migration.md` | `upgrade_migration_test.dart` |
| A6 | A képernyőszám VÁLTOZATLAN | `test/ui/ui_inventory_test.dart` a §7 gate-ben |
| A7 | A három ÚJ fixture regisztrálva van a `test/fixtures/manifest.json`-ban (helyes `bytes`/`sha256`, `containsUserData: false`), a fa-bejáró tiszta, és a pinnelt darabszám `48` → `51` | `test/tooling/fixture_manifest_test.dart` a §7 gate-ben |

### 6.1 Mérce-mátrix — melyik hibás implementációt melyik cella fogja pirosra

| Hibás implementáció | Melyik cella vált PIROSRA | Melyik őr méri |
|---|---|---|
| A cella csak azt méri, hogy az app elindul / a bootstrap nem dob | A1 | rekordszám + id-halmaz + XP-egyenleg egyenlőség |
| A migráció elveszít egy user-content dokumentumot (néma adatvesztés) | A1 | rekordszám-egyenlőség kulcsonként |
| A megszakítás után a migráció elölről kezd (duplikáció) | A2 | id-halmaz duplikátum-mentessége + rekordszám a nem-megszakított futáshoz mérve |
| A megszakítás után a `schemaVersion` visszaáll 0-ra | A2 | `report.fromVersion` a folytatásnál == a megszakításkori `toVersion` |
| A sérült bemenet üres profilt indít / törli a nyers kulcsot | A3 | a nyers legacy érték bitre azonos + a boot utáni olvasás nem üres |
| A sérült bemenet csendben „sikeresnek" jelenti magát | A3 | `report.failure != null` ÉS `toVersion == fromVersion` |
| A megnyithatatlan store mellett az app mégis elindul | A4 | `BootstrapFailure` típus-cella |
| A riport csak „sikeres" jelzést ad, számok nélkül | A5 | `applied` id-lista + `from/toVersion` pinnelve |
| Egy új fixture manifest-bejegyzés nélkül kerül a fába | A7 | `fixtureMissingManifestEntry` + a pinnelt `51` |

**Valódi-sértés próba (KÖTELEZŐ, a §10-ben dokumentálva):** az A1 cellából vedd ki az
XP/streak-egyenleg összehasonlítást, és futtasd a §7 gate-et egy szándékosan
XP-vesztő fixture-variánssal (a fixture-t NE commitold) → a megcsonkított cellának
**ZÖLDNEK** kell lennie (ez bizonyítja, hogy az adatvesztést pontosan az invariáns-
összehasonlítás fogja, nem a boot), a visszaállított cellának ugyanazon a bemeneten
**PIROSNAK**. Állítsd vissza, és a §10-ben dokumentáld MINDKÉT kimenetet, szó szerinti
gate-kimenettel.

## 7. Kötelező ellenőrzések

```bash
tools/round-gate.sh test/e2e/upgrade_migration_test.dart test/tooling/fixture_manifest_test.dart test/ui/ui_inventory_test.dart
```

## 8. Implementációs sorrend

1. A MÉRÉS: `appStorageMigrations` 22 lépése és a `LegacyStorageKeys` → `StorageKeys`
   párok (`lib/core/storage/storage_keys.dart`), valamint a user-content dokumentumok
   burkoló-sémája (`schemaVersion` + body).
2. A három fixture + README (a README rögzíti: szintetikus, melyik kör/verzió sémája,
   `containsUserData: false`).
3. A fixture-ök regisztrálása a `test/fixtures/manifest.json`-ban + a pinnelt darabszám
   `48` → `51` a `test/tooling/fixture_manifest_test.dart`-ban (§0.0/R2) — ezt FUTTASD
   is, mielőtt továbbmész.
4. `test/e2e/upgrade_migration_test.dart` — A1 (számszerű invariánsok) ELŐSZÖR.
5. A2–A5 cellák (megszakítás, sérülés, tárhely, riport-számok).
6. `docs/release/client-migration.md` + a valódi-sértés próba a §10-be.

## 9. Kockázatok

- **Néma adatvesztés.** A legsúlyosabb, és csak számszerű invariánssal fogható (A1).
- **Duplikáció resume-nál.** A checkpoint téves kezelése kétszer migrál (A2).
- **Fixture-hitelesség.** Egy kitalált legacy formátum semmit nem bizonyít — a README rögzítse, melyik kör/verzió írta azt a sémát.

## 10. Implementation handoff — az implementer tölti ki

## 11. Review — a Claude tölti ki
