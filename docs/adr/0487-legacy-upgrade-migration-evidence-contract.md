# ADR 0487 — Legacy upgrade migration evidence contract: numeric no-loss invariants, checkpoint resume and the measured failure surface

- **Státusz:** Elfogadva
- **Dátum:** 2026-09-01
- **Kör:** E12-R23 (Chapter 12 — Release Roadmap, Sprint Planning & Final Integration)
- **Kontextus-ADR-ek:** [0117](0117-song-storage-migrator-boundary.md) (song storage
  migrátor: legacy olvasási út, checkpoint), [0239](0239-analysis-document-storage.md)
  (részleges hiba utáni folytatás, ID-alapú nem-duplikálás),
  [0350](0350-legacy-practice-backfill-identity-zero-xp-and-checkpoint.md) (stabil
  identitás, nulla XP, perzisztált checkpoint), [0473](0473-release-fixture-corpus-manifest.md)
  (release fixture-korpusz manifest), [0472](0472-e2e-flow-harness-runs-in-the-flutter-test-host.md) (e2e folyam-harness)

## Kontextus

A StrumSight release-jelöltje előtt bizonyítani kell, hogy egy **korábbi verzióról
frissítő** felhasználó adata nem vész el. A fán 12+ migrátor és legacy adapter él, saját
tesztekkel, de **egységes, verzió szerinti legacy fixture-készlet nincs**, és nincs egyetlen
olyan mérce sem, amely a teljes frissítési utat — legacy tárolási állapot → migráció →
olvasható profil — végigméri.

A kör pre-flightja (E12-R23 §0.0) a fán ÚJRAMÉRTE a feltételezett hibautat, és három
megdöntött állítást talált. Ez az ADR ezeket a mért tényeket rögzíti szerződésként, hogy
a következő körök ne egy réteg-diagramból induljanak ki:

1. **`StorageMigrator.migrate()` soha nem dob.** Migrációnként `try/catch`, és hiba esetén
   `StorageMigrationReport(failure: …)`-t ad vissza; a `schemaVersion` a bukott lépés
   ELŐTTI értéken marad. A szándék a doc-commentben kimondott: *„a broken migration must
   never be a broken app"*.
2. **`AppBootstrap.run` eldobja a riportot** (`await StorageMigrator(…).migrate();`), ezért
   sérült migrációs bemenet mellett is `BootstrapSuccess` keletkezik. `BootstrapFailure`-t
   mérve kizárólag három input produkál: ismeretlen environment define, `openStore` →
   `Failure`, és a try-blokk váratlan kivétele.
3. **A `RecoveryScreen` nem a bootstrap-hiba felülete.** `main.dart` `BootstrapFailure`
   esetén a `BootstrapFailureApp`-ot futtatja; a `RecoveryScreen`-t egyedül az
   `AppRoutes.recovery` GoRoute építi, és a `lib/` fában semmi nem navigál rá.

Ebből következik, hogy a „sérült bemenet → `RecoveryScreen`" elvárás a mai fán nem
teljesíthető `lib/**` módosítás nélkül — a bizonyítékot tehát nem ott kell keresni, ahol a
brief eredetileg feltételezte.

## Döntés

### D1 — A „nincs adatvesztés" invariáns SZÁMSZERŰ, nem viselkedési

A frissítési mérce migráció előtt/után **három** dolgot hasonlít össze kulcsonként: a
felhasználói dokumentumok **rekordszámát**, az **azonosító-halmazt** és az
**XP/streak-egyenleget**. Az „elindul, tehát rendben" típusú cella nem elfogadható
bizonyíték: a néma adatvesztés pontosan úgy néz ki, mint egy sikeres indulás.

### D2 — A megszakítás után FOLYTATÁS van, nem újrakezdés

A `schemaVersion` migrációnként, a lépés UTÁN íródik (ADR 0117/0239/0350 checkpoint-mintája),
ezért egy félbeszakadt futás a következő induláskor a soron következő lépésnél folytatódik.
A mérce ezt a megszakított és a megszakítás nélküli futás **azonos végállapotával**
bizonyítja: azonos rekordszám, duplikátum-mentes azonosító-halmaz.

### D3 — A hibás migráció fail-safe, nem fail-closed — és soha nem üres profil

Sérült legacy bemeneten a szerződés: `report.failure != null`, `toVersion == fromVersion`,
a **nyers legacy adat bitre érintetlen**, és a rákövetkező indulás a már meglévő értékeken
fut. Tiltott gyengítés: „tiszta lappal indulás" fallback, néma kulcs-törlés, vagy sikeresnek
jelentett bukás. A megnyithatatlan store ezzel szemben **fail-closed**: `BootstrapFailure`
a storage-unavailable indokkal, írás nélkül.

### D4 — A safe-mode felület a MÉRT elérhetőségén pinnelendő

A `RecoveryScreen` létezik és route-olható, de nincs production navigáció rá, a
bootstrap-hiba felülete pedig a `BootstrapFailureApp`. A mérce ezt a mért állapotot
rögzíti; a felület átkötése önálló, review-zott kör tárgya `lib/**` érintéssel. Ez az ADR
NEM rendel a `RecoveryScreen`-hez migrációs hibautat.

### D5 — A frissítési mérce nem módosítja sem a `lib/**`-ot, sem az e2e harnesst

A bizonyíték-teszt maga hívja az `AppBootstrap.run(openStore:, migrations:, loadVersion:,
loadOnboardingSeen:)` már létező, injektálható belépőjét a fixture-ből feltöltött
`InMemoryKeyValueStore` fölött, és csak azután bootol appot ugyanazon a store-on a meglévő
`bootE2eApp` harnesszel. Új fake, új harness-áthidalás és production-módosítás nélkül.

### D6 — Minden ÚJ fixture az ADR 0473 manifest-szerződése alá esik

A `test/fixtures/**` alatt keletkező minden nem-`.dart`, nem-`README.md` fájl
manifest-bejegyzést kap (`bytes`, `sha256`, `license`, `source`, `containsUserData`), és a
fa-bejáró pinnelt darabszáma ugyanabban a körben mozdul. A regisztráció a kör MÉRCÉJÉNEK
része (gate-test), nem adminisztratív utómunka.

## Következmények

**Pozitív.** A frissítési út bizonyítéka számszerű és falszifikálható: egy adatvesztő vagy
duplikáló migrátor pirosra vált, nem „zölden elindul". A pre-flight mérése rögzítve van,
így a következő körök nem tervezik újra a nem létező „migráció → RecoveryScreen" utat. A
mérce nulla production-kockázattal fut: `lib/**` és `test/support/**` érintetlen.

**Ár és korlát.**

- A mérce a **boot-úti** `appStorageMigrations` láncot hajtja; a gamification-, song-storage-,
  library- és practice-plan-migrátorok provider/use-case úton indulnak, és továbbra is a saját
  tesztjeik mérik őket. A kör NEM állítja, hogy mind a 12 migrátor végig van hajtva.
- A D3 fail-safe szerződés következménye, hogy a felhasználó egy bukott migráció után
  **nem kap figyelmeztetést** — csak a régi értékein fut tovább. Ez tudatos, mért állapot;
  a felhasználói jelzés (safe-mode belépő) nyitott kérdés, a D4 szerint külön kör tárgya.
- A fixture-ök szintetikusak; a README rögzíti a származásukat és a sémájuk körét. Egy
  kitalált legacy formátum semmit nem bizonyítana, ezért a fixture-kulcsok forrása a
  `LegacyStorageKeys` a fán, nem szabad kézzel írt találgatás.
