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
| A3b *(javító kör, MAJOR-1)* | Egy TÉNYLEGESEN malformált legacy dokumentummal (`corrupted_storage.json`, `user_setlists_v1` csonkolva) a migráció `report.failure == null`-t és a végső `schemaVersion`-t ad — a korrupció-átlátszóság kimondva és mérve; a nyers legacy érték bitre azonos marad; a `JsonDocumentStore.readBody()` mai kimenete (`null`) explicit `expect`-tel, „ISMERT KORLÁT (ADR 0487)" jelöléssel rögzítve | `upgrade_migration_test.dart` |
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
| A sérült bemenet csendben „sikeresnek" jelenti magát | A3b *(javító kör, MAJOR-1 — korábban ŐRIZETLEN, lásd `docs/reviews/e12-r23-review.md`)* | `report.failure == null` ÉS `schemaVersion` a végértékre lép, a nyers legacy érték bitre azonos, ÉS a `JsonDocumentStore.readBody()` mai `null` kimenete explicit pinnelve (ISMERT KORLÁT) |
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

**Motor:** Claude Sonnet 5 (`sonnet-impl`). **Ág:**
`sonnet-impl/e12-r23-legacy-migration-release-candidate`. A §0.0 revízió
(R1–R7) mérése változatlan maradt — az implementáció abból dolgozott, nem
mérte újra.

### 10.1 Mit épített

- **`test/fixtures/migrations/`** — három szintetikus, `LegacyStorageKeys`
  kulcsnevekre épülő `KeyValueStore`-pillanatkép + README:
  - `legacy_v1_storage.json` — pre-E01-R06 (`fromVersion 0`, mind a 22 lépés
    függőben, mind a hat legacy content dokumentum eredeti, boríték nélküli
    alakban).
  - `legacy_v2_storage.json` — E01-R06/E01-R07 közötti valós történelmi rés
    (`fromVersion 16`, csak a hat `r07.*` content-lépés függőben) —
    `storage_migrator.dart` saját doc-commentjéből mérve, nem kitalálva.
  - `corrupted_storage.json` — legacy adatkészlet (`fromVersion 0`); **a javító
    körig** minden mezője érvényes volt, a "sérülés" kizárólag a tesztben
    injektált store-írási hiba volt (lásd 10.3), mert a fán élő két
    migráció-típus (`RenameKeyMigration`, `WrapJsonDocumentMigration`)
    doc-commentje szerint SOHA nem dob adat-alakú hibán. **A javító kör
    (§10.8, MINOR-1) egy mezőt (`user_setlists_v1`) ténylegesen malformálttá
    tett**, hogy a fájl neve igazat állítson és az A3b cella (§10.8, MAJOR-1)
    egy VALÓDI sérült dokumentumon mérhessen — ezt a README és a §10.5/§10.8
    dokumentálja mért tényként.
  - Manifest-regisztráció (`test/fixtures/manifest.json`, ADR 0473 D6-nak
    megfelelően `bytes`/`sha256`/`license`/`source`/`containsUserData: false`)
    és a pinnelt darabszám `test/tooling/fixture_manifest_test.dart`-ban
    `48 → 51` (KIZÁRÓLAG a szám és a teszt-reason szövege módosult, a cellák
    logikája nem).
- **`test/e2e/upgrade_migration_test.dart`** — új fájl, öt csoport (A1–A5).
  Minden cella közvetlenül hívja `StorageMigrator(store:, logger:,
  [migrations: appStorageMigrations]).migrate()`-et a riportért (publikus
  `lib/**` API, változatlan), és — ahol az acceptance ezt kéri — ugyanazon a
  store-on `AppBootstrap.run(openStore:, loadVersion:, loadOnboardingSeen:)`-t
  is az app-boot bizonyítékáért. Sem `lib/**`, sem `test/support/**` nem
  módosult; az egyetlen `test/support/**`-importált szimbólum az
  `InMemoryKeyValueStore` (`test/core/storage/in_memory_key_value_store.dart`,
  ami VALÓJÁBAN `test/core/storage/`, nem `test/support/` alatt van — nem
  tilos zóna, meglévő teszt-dupla, nem új fake).
- **`docs/release/client-migration.md`** — ÚJ, a migrációs kör hatóköre,
  invariáns-mérés, megszakítás/resume, fail-safe vs. fail-closed, és az
  explicit no-rollback korlát.

### 10.2 Melyik cella melyik acceptance-pontot fedi

| Acceptance | Teszt-csoport | Mit bizonyít |
|---|---|---|
| A1 | `upgrade_migration_test.dart` "A1" (2 teszt: v1, v2) | `report.isComplete`, `toVersion == appStorageMigrations.last.version`, és a hat content-dokumentum rekordszáma/id-halmaza + a streak-egyenleg (`current`/`longest`/`last`/`freezes`/`total`) migráció előtt/után bit-azonos; utána `AppBootstrap.run` → `BootstrapSuccess` |
| A2 | `upgrade_migration_test.dart` "A2" | `nudgeEnabled` (version 10) írási hibája → `toVersion == 9`, `applied` 9 elem; a hiba törlése után az ÚJ `migrate()` `fromVersion == 9`-től folytat, csak a maradék 13 lépést alkalmazza (`applied` egzakt lista), és a végállapot (id-halmazok, streak) megegyezik egy megszakítás nélküli, azonos fixture-ön futó referenciafuttatással; a `writeLog` közvetlenül bizonyítja, hogy a hibázó kulcs pontosan egyszer íródott sikeresen |
| A3 | `upgrade_migration_test.dart` "A3" | `themeMode` (version 1, az ELSŐ függő lépés) írási hibája → `report.failure != null`, `toVersion == fromVersion == 0`, `applied` üres; a store teljes tartalma bájtra megegyezik a migráció előtti pillanatképpel; `AppBootstrap.run` utána is `BootstrapSuccess`; a `songs` dokumentum `JsonDocumentStore.readBody()`-n (a termelési legacy-fallback úton) keresztül a fixture eredeti id-listáját adja vissza — nem üres |
| A4 | `upgrade_migration_test.dart` "A4" | `openStore` → `Failure(StorageFailure(storageUnavailable))` ⇒ `BootstrapFailure`, a `problems` tartalmazza a `storage.unavailable` kódot, és a `loadOnboardingSeen` (tehát bármilyen store-hozzáférés) SOHA nem fut le |
| A5 | `upgrade_migration_test.dart` "A5" (2 teszt) | `report.fromVersion`/`toVersion` és az `applied` id-lista EGZAKT egyenlőséggel pinnelve mindkét fixture-re (`appStorageMigrations.map((m) => m.id)`, illetve a `version > 16` szűrt lista), és a migrált dokumentumok rekordszáma kulcsonként (`hasLength`) |
| A6 | `test/ui/ui_inventory_test.dart` a §7 gate-ben | változatlan — a kör nem érintette a `lib/` fát |
| A7 | `test/tooling/fixture_manifest_test.dart` a §7 gate-ben | a három új fixture manifest-bejegyzése tiszta bejárást ad, a pinnelt darabszám `51` |

### 10.3 Mért tény, ami a briefben implicit volt, de dokumentálásra szorult

A `corrupted_storage.json` fixture ÖNMAGÁBAN nem tudja megbuktatni
`StorageMigrator.migrate()`-et: `RenameKeyMigration.apply` és
`WrapJsonDocumentMigration.apply` doc-commentje szerint SOHA nem dob
adat-alakú hibán (olvashatatlan típus, parse-hiba, alak-eltérés — mindegyik
logol és visszatér, nem dob). Az egyetlen módja a
`StorageMigrationReport.failure != null`-nak a fán egy `KeyValueStore`
ÍRÁSI hiba (`StorageException`). Az A3 cella ezért a fixture-t egy
test-only `InMemoryKeyValueStore.failingKeys` hibainjektálással párosítja
(meglévő teszt-dupla, `test/core/storage/in_memory_key_value_store.dart` —
nem új fake, nem `lib/**`/`test/support/**` érintés). Ez a `test/fixtures/
migrations/README.md`-ben és a `docs/release/client-migration.md` §6-ban is
rögzítve van.

### 10.4 A2 tervezési döntés: hiba-injektálás kulcs, nem "N-edik írás" számláló

Az `InMemoryKeyValueStore` (nem módosítható, `test/core/storage/`) a hibát
KULCS szerint szimulálja (`failingKeys`), nem egy globális írásszámláló
szerint. Mivel az `appStorageMigrations` minden lépése determinisztikusan,
sorban, EGY konkrét célkulcsra ír, egy adott lépés célkulcsának
hibássá tétele funkcionálisan pontosan azt adja, amit egy "az N-edik írás
dob" mechanizmus adna (a lépés-sorrend fixált) — csak a meglévő test-dupla
API-ján keresztül, új teszt-infrastruktúra nélkül.

### 10.5 A valódi-sértés próba (§6.1, KÖTELEZŐ) — mindkét kimenet

**Módszer:** az A1 `_LegacyContent.expectPreservedIn` metódusából
IDEIGLENESEN eltávolítva a streak-egyenleg `expect(after.streak,
equals(streak), ...)` sora; a `legacy_v1_storage.json`-hoz IDEIGLENESEN
(soha nem commitolva) hozzáadva egy `"ss.streak.state":
"{\"schemaVersion\":1,\"data\":{\"current\":0,...,\"total\":0}}"` kulcs — ez
a mérce SZERINT MÁR-migrált stub, ezért a 22. lépés (`r07.streak`,
`WrapJsonDocumentMigration`) a `store.contains(to)` ág miatt eldobja a
valódi (`total: 40`) legacy egyenleget és a hamis nullát hagyja állva: valódi,
mért adatvesztés, `lib/**` módosítása nélkül. Mindkét futtatás a §7 gate
egzakt parancsával történt (`tools/round-gate.sh test/e2e/upgrade_migration_test.dart
test/tooling/fixture_manifest_test.dart test/ui/ui_inventory_test.dart`);
a `fixture_manifest_test.dart` lépés mindkét körben PIROS volt (a
checksum-pin a szándékos, nem commitolt fixture-mutáció ellen — ez a
művelet MELLÉKTERMÉKE, a próba tárgya kizárólag az `upgrade_migration_test.dart`
lépés).

**1. kimenet — megcsonkított cella, mérgezett fixture → ZÖLD** (a `[3] test
test/e2e/upgrade_migration_test.dart` lépés szó szerint):

```
00:00 +0: A1 — full run from a legacy snapshot: numeric no-loss invariants (ADR 0487 D1) legacy_v1_storage.json (pre-E01-R06, fromVersion 0): record count, id-set and streak balance are identical before/after, migration reaches the last version, and the app boots on the migrated store
...
00:00 +7: All tests passed!

    → [3] test test/e2e/upgrade_migration_test.dart: ZÖLD
```

(A gate a KÖVETKEZŐ lépésen, `[4] test test/tooling/fixture_manifest_test.dart`-on
állt meg PIROS-sal — a mérgezett `legacy_v1_storage.json` sha256-ja már nem
egyezik a manifest bejegyzésével. Ez a mért, várt melléktermék, nem a próba
tárgya.)

**2. kimenet — visszaállított cella, UGYANAZON mérgezett fixture → PIROS**
(a `[3] test test/e2e/upgrade_migration_test.dart` lépés szó szerinti hiba-
kimenete):

```
Expected: {..., 'current': 5, ...}
  Actual: {'current': 0, 'longest': 0, 'last': -1, 'freezes': 0, 'total': 0}
     Which: at location ['current'] is <0> instead of <5>
  the XP/streak balance must be bit-for-bit unchanged

  test/e2e/upgrade_migration_test.dart 453:5  _LegacyContent.expectPreservedIn
  test/e2e/upgrade_migration_test.dart 54:16  main.<fn>.<fn>

Failing tests:
  .../test/e2e/upgrade_migration_test.dart: A1 — full run from a legacy snapshot: numeric no-loss invariants (ADR 0487 D1) legacy_v1_storage.json (...)

    → [3] test test/e2e/upgrade_migration_test.dart: PIROS (kilépési kód 1)
```

**Utána:** `git checkout -- test/fixtures/migrations/legacy_v1_storage.json`
(a mérgezett variáns eldobva, soha nem commitolva) és a streak-egyenleg
`expect` visszaállítva a forrásban — `git status --porcelain` és `git diff`
ezután üres a próba előtti állapothoz képest. A záró §7 gate futtatás
(lásd 10.6) a helyreállított fán fut, minden lépés ZÖLD.

### 10.6 A záró gate kimenete (a commitolt fán, a próba után)

```
tools/round-gate.sh test/e2e/upgrade_migration_test.dart test/tooling/fixture_manifest_test.dart test/ui/ui_inventory_test.dart
```

```
═══ Gate-összegzés
    format                                                     zöld
    analyze                                                    zöld
    test test/e2e/upgrade_migration_test.dart                  zöld
    test test/tooling/fixture_manifest_test.dart               zöld
    test test/ui/ui_inventory_test.dart                        zöld
    architecture                                               zöld
    secrets                                                    zöld
    l10n                                                       zöld

MINDEN GATE ZÖLD. A teljes suite + randomizált property gate + APK a CI-ban
fut (ADR 0053) — azt az orchestrátor indítja, te ne hívj gh-t.
```

(8/8 lépés ZÖLD; `test/e2e/upgrade_migration_test.dart` mind a 8 tesztje —
A1×2, A2×1, A3×1, A4×1, A5×2, plusz a fájlszintű `loading` bejegyzés —
zöld; `fixture_manifest_test.dart` mind a 23, `ui_inventory_test.dart` az 1
tesztje zöld.)

### 10.7 Javító kör (fix round, 2026-09-02) — MAJOR-1 és MINOR-1 zárása

A review (`docs/reviews/e12-r23-review.md`) egy mért, nem-mérce-fedett utat
talált: egy TÉNYLEGESEN sérült legacy dokumentum a migrációt csendben
„sikeresnek" jelenti (`report.failure == null`), miközben a termelési
olvasási út (`JsonDocumentStore.readBody()`) üres dokumentumot ad. Az eredeti
A3 cella ezt nem mérte, mert a hibáját egy injektált ÍRÁSI hibából nyerte,
nem a bemenet tartalmából.

**MINOR-1 feloldása (a briefben felkínált két opció közül az elsőt
választva):** a `corrupted_storage.json` fixture `user_setlists_v1` mezőjét
ténylegesen malformálttá tettem (csonkolt JSON:
`[{"id":"setlist-corrupt-solo","name":"Solo practice",`) — a fájl neve ezzel
igazat állít. Minden más mező (beleértve a meglévő A3 cella által olvasott
`songs` dokumentumot) érvényes maradt, ezért a meglévő A3 cella
VÁLTOZATLANUL zöld (az A3 hibáját az ELSŐ lépésen, `themeMode`-on injektált
írási hiba adja — az soha nem ér el a 19. lépésig, ahol a malformált mező
él). Indoklás a másik opció (fájlnév-átnevezés) ellen: az újrafelhasználás
egyetlen fixture-t igényel a két cellához, és a README/manifest egy helyen
dokumentálja mindkét felhasználást — kevesebb új felület, mint egy negyedik
fixture-fájl bevezetése lett volna.
Manifest-frissítés: `test/fixtures/migrations/corrupted_storage.json` —
`bytes: 1297 → 1261`, `sha256: dfa5ca40… → 463d89fa…` (a `source` mező
kiegészítve a szerepe pontos leírásával). A fájlszám (51) nem változott, a
`test/tooling/fixture_manifest_test.dart` cellák logikája és pinnelt száma
érintetlen.

**MAJOR-1 feloldása:** új `A3b` teszt-csoport a
`test/e2e/upgrade_migration_test.dart`-ban (az A3 után, az A4 előtt) — az
eredeti A3-at nem törölte, nem módosította. Az A3b UGYANAZT a fixture-t
tölti be, DE nem injektál írási hibát, így a teljes 22 lépés lefut a valódi
(a malformált `user_setlists_v1` mezőn elakadó) tartalommal. Amit a cella
pinnel:

1. **Fixture-önellenőrzés:** `jsonDecode(rawMalformedSetlists)` ténylegesen
   `FormatException`-t dob — a cella a VALÓDI korrupciós utat méri, nem az
   írás-hiba ágat.
2. **A silent-success mérés:** `report.failure == null`,
   `report.toVersion == appStorageMigrations.last.version` (22),
   `report.applied` mind a 22 lépést tartalmazza — mért tény, hogy
   `WrapJsonDocumentMigration.apply` a parse-hibát logolja és visszatér, nem
   dob.
3. **Az adatvesztés-őr:** `store.readString(LegacyStorageKeys.setlists)`
   bitre egyenlő a migráció előtti nyers értékkel
   (`legacyKeyPreserved=true`), és `store.contains(StorageKeys.setlists)`
   hamis (`newKeyWritten=false`) — pontosan a review mért terminológiája.
4. **Az ISMERT KORLÁT explicit pinnelése:** egy a termelési kóddal azonos
   paraméterezésű `JsonDocumentStore` (`key: StorageKeys.setlists,
   legacyKey: LegacyStorageKeys.setlists`) `readBody()`-ja `null`-t ad,
   `reason:`-ben „ISMERT KORLÁT (ADR 0487)" jelöléssel — ha egy jövőbeli kör
   ezt megjavítja vagy elrontja, a cella pirosra vált.
5. **Kontroll:** a `songs` dokumentum (jól formált mező, ugyanabban a
   fixture-ben) `readBody()`-ja továbbra is a fixture eredeti listáját adja
   — a korrupció a mért egy mezőre szűkül, nem az egész futásra.

**Melyik hibás implementációt fogja pirosra:** ha egy jövőbeli, `lib/**`-et
érintő kör a `WrapJsonDocumentMigration.apply`-t úgy módosítaná, hogy egy
parse-hibán is a `report.failure`-t állítsa, VAGY a `JsonDocumentStore` a
korrupt legacy blobot törölné ahelyett, hogy a legacy kulcson hagyná — az
A3b 2., 3. vagy 4. pontja pirosra vált (a §6.1 mátrix új sora).

**Dokumentáció-átvezetés:** `docs/release/client-migration.md` §6 kibővítve
— a szakasz cím és tartalom immár kimondja a frissítés-utáni üres
dokumentum korlátot (a nyers adat megmarad, a következő írás karanténba
menti), és a §0 „Mérce" sor felsorolja az A3b cellát.
`test/fixtures/migrations/README.md` `corrupted_storage.json` szakasza
átírva: a fájl immár EGY ténylegesen malformált mezőt tartalmaz, és a két
cella (A3 write-fault, A3b real-corruption) különálló forrásait a README
külön bekezdésben tárgyalja.

**Záró gate (a javító kör commitjai után, szó szerint):**

```
tools/round-gate.sh test/e2e/upgrade_migration_test.dart test/tooling/fixture_manifest_test.dart test/ui/ui_inventory_test.dart
```

```
═══ Gate-összegzés
    format                                                     zöld
    analyze                                                    zöld
    test test/e2e/upgrade_migration_test.dart                  zöld
    test test/tooling/fixture_manifest_test.dart               zöld
    test test/ui/ui_inventory_test.dart                        zöld
    architecture                                               zöld
    secrets                                                    zöld
    l10n                                                       zöld

MINDEN GATE ZÖLD.
```

(`test/e2e/upgrade_migration_test.dart` mostantól 9 teszt — A1×2, A2×1,
A3×1, **A3b×1 ÚJ**, A4×1, A5×2, plusz a fájlszintű `loading` bejegyzés —
mind zöld; a fixture-manifest és ui-inventory suite-ok változatlanul zöldek.)

**Tilos zóna, változatlanul:** `lib/**` (a migrátor és a `JsonDocumentStore`
viselkedése nem módosult), `test/support/**`, `tool/check_fixture_manifest.dart`
logikája.

### 10.8 Amit NEM érintett ez a kör (az eredeti kör ÉS a javító kör)

`lib/**`, `test/support/**`, `tool/check_fixture_manifest.dart` (a bejáró
LOGIKÁJA), `docs/adr/**` (az ADR 0487-et a pre-flight már megírta),
`test/ui/goldens/**`. A `test/tooling/fixture_manifest_test.dart`-ban
KIZÁRÓLAG a pinnelt szám és a teszt-reason szövege változott — a cellák
logikája nem; a javító kör ezt a fájlt egyáltalán nem érintette.

## 11. Review — a Claude tölti ki
