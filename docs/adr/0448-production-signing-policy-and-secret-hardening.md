# ADR 0448 — Production signing policy és secret hardening

- **Státusz:** elfogadva (2026-08-28, E12-R07 pre-flight)
- **Kontextus:** SDD Chapter 12, Kör 7;
  [`docs/rounds/e12-r07-production-signing-and-secret-hardening.md`](../rounds/e12-r07-production-signing-and-secret-hardening.md)
- **Kapcsolódó:** [ADR 0062](0062-ci-gate-chain-and-fail-closed-release-signing.md)
  (fail-closed release signing — a „debug-signing fallback, ha nincs secret"
  alternatívát MÁR elutasította), [ADR 0447](0447-release-manifest-provenance-and-sbom.md)
  (release manifest `schemaVersion: 1`, determinizmus, javaslat-fájl a védett
  workflow helyett), [ADR 0321](0321-gateguard-round-hold-not-chain-halt.md)
  (`PROTECTED_GLOBS` — `.github/workflows/**` védett), [ADR 0372](0372-gate-edit-policy.md)
  (a gate-szerkesztés álló felhatalmazásának FÁJLJA), [ADR 0444](0444-delivery-workflow-and-repository-policy.md)
  (D3: korlátozott YAML-részhalmaz saját parserrel), [ADR 0051](0051-strumsight-application-identifiers.md)
  (`applicationId` = a telepítés identitása), [L528](../LESSONS.md#l528)
  (egy szigorítást szolgáló ág maga szivárogtatott titkot a logba)

## Kontextus — mért tények (E12-R07 pre-flight, `main @ eccf89cf`)

1. `android/app/build.gradle.kts` (133 sor) a signing értékeket vagy a
   `android/key.properties` fájlból, vagy a négy `STRUMSIGHT_RELEASE_*`
   környezeti változóból veszi (36–56. sor). Hiányos konfigra
   `GradleException` („Incomplete release signing configuration"), üres vagy
   hiányzó keystore-fájlra szintén kivétel (65–70. sor).
2. `STRUMSIGHT_REQUIRE_RELEASE_SIGNING=true` mellett a hiányzó signing config
   kivétel (58–63. sor). **A tanúsítvány MIBENLÉTÉT ma semmi nem méri:** egy
   teljes, de a debug keystore-ra mutató `key.properties` minden mai ágon
   átmegy.
3. **A fán EGYETLEN `release` buildType van** (`buildTypes { release { … } }`,
   107–117. sor); `production` vagy `lab` nevű buildType, flavor vagy
   product dimenzió **nem létezik**. A `release` ág `releaseSigningValues == null`
   esetén explicit `signingConfigs.getByName("debug")`-re esik vissza.
4. Ebből következően a három APK-építő workflow **ugyanazt a `release`
   buildType-ot** építi, és kizárólag a környezetük különbözteti meg őket:
   - `.github/workflows/release-apk.yml:113–121` — a négy `STRUMSIGHT_RELEASE_*`
     env **és** `STRUMSIGHT_REQUIRE_RELEASE_SIGNING: 'true'` → production;
   - `.github/workflows/lab-apk.yml:36` — `flutter build apk --release
     --dart-define-from-file=lab_build.json`, signing env **nélkül** → debug
     fallback;
   - `.github/workflows/build-apk.yml:63` — `flutter build apk --release`,
     signing env **nélkül** → debug fallback.
5. `.github/workflows/release-apk.yml` `signing-prerequisites` jobja (9–36. sor)
   a négy secret meglétét `::error::`-rel kényszeríti a build ELŐTT; a
   `Materialize production keystore` lépés `umask 077` mellett a
   `$RUNNER_TEMP`-be dekódol, a `Remove production keystore` lépés `if: always()`
   mellett törli. **Jelszó vagy kulcsanyag `echo`-zása egyetlen lépésben sincs.**
6. `tool/generate_release_manifest.dart` (E12-R06) manifest-objektuma
   `schemaVersion`, `app{version,buildNumber,shortSha,channel}`,
   `modelPackage`, `knowledgePackage`, `artifacts[]` mezőkből áll — **certificate
   vagy signing mező NINCS benne**. A generátor CLI-je hét flaget ismer, köztük
   az ismételhető `--artifact <path>`-ot (57–58. sor), amely a megnevezett
   fájlt névvel, úttal és sha256-tal veszi fel az `artifacts[]` listába.
7. `.claude/gate-edit-policy` a fán **nem létezik** (`tools/gateguard-scan.py`),
   tehát a `.github/workflows/**` írása egy implementer-sessionben
   strukturálisan `H-GATEGUARD`-dal állna meg.
8. `docs/security/` két Community-dokumentumot tartalmaz
   (`community-access-matrix.md`, `community-threat-model.md`);
   `signing-key-runbook.md` nem létezik. `tool/release/` a
   `generate_sbom.py` és `verify_artifacts.py` fájlokat tartalmazza.
9. `test/tooling/check_secrets_test.dart` (a `tool/ci/check_secrets.dart`
   regresszió-őre) létezik, és a saját fájlját `strumsight:allow-secret-file`
   markerrel veszi ki a scan alól.

## Döntések

### D1 — A production ág megkülönböztetője a signing-mód kapcsoló, NEM egy „production buildType"

A kör-brief §3/§5.3 „production `buildType`" fordulata a fán **nem
értelmezhető** (Kontextus 3.): egyetlen `release` buildType van, és ugyanazt
építi a Lab és a kör-gate is. Egy buildType-alapú szigorítás ezért vagy
**semmit nem véd** (nincs ilyen buildType), vagy **a Lab APK-t is megállítja**
(ha a `release`-re mondjuk ki) — utóbbi pontosan a brief §5.3 által tiltott
gyengítés inverze, a user napi diagnosztikai eszközének elvesztése.

A production signing mód mérhető, létező jelzése a
`STRUMSIGHT_REQUIRE_RELEASE_SIGNING` környezeti kapcsoló (Kontextus 2., 4.):
ezt **kizárólag** a `release-apk.yml` állítja `true`-ra. A kör minden
szigorítása ehhez a kapcsolóhoz, illetve a ténylegesen megadott
`releaseSigningValues`-hoz kötődik — nem a buildType nevéhez.

### D2 — Production módban a TANÚSÍTVÁNY az elutasítás tárgya, nem a konfiguráció megléte

`STRUMSIGHT_REQUIRE_RELEASE_SIGNING=true` mellett `GradleException`-t kell
dobni, ha bármelyik teljesül:

- a `storeFile` a debug keystore-ra mutat — a fájlnév `debug.keystore`
  (kis/nagybetű-érzéketlen), vagy az út a felhasználó `~/.android/`
  könyvtárában lévő alapértelmezett debug keystore;
- a `keyAlias` `androiddebugkey` (kis/nagybetű-érzéketlen);
- a `release` buildType signing configja a `debug` signing configra esne
  vissza.

**NEM elfogadható gyengítés:** figyelmeztetés (`logger.warn`, `println`)
kivétel helyett; a meglévő „van-e konfig" ellenőrzés elegendőnek nyilvánítása.
A kivétel üzenete a **kulcs aliasát és a keystore útvonalát** megnevezheti,
**jelszót soha**.

### D3 — A Lab és a kör-gate ága érintetlen marad

`STRUMSIGHT_REQUIRE_RELEASE_SIGNING` hiányában és signing config nélkül a
`release` buildType **továbbra is** a debug configra esik vissza (Kontextus 3.,
4.) — ezt a kör nem változtatja meg. A `lab-apk.yml` és a `build-apk.yml`
parancssora változatlanul zöld marad.

**NEM elfogadható gyengítés:** globális tiltás, amely a signing env nélküli
`flutter build apk --release` hívást is megállítja.

### D4 — A certificate fingerprint SIDECAR fájlba megy, a manifest sémája nem változik

A fingerprintet a release manifestbe „a séma megfelelő mezőjébe" írni **nem
lehetséges** ebben a körben (Kontextus 6.): ilyen mező nincs, a generátor
(`tool/generate_release_manifest.dart`) pedig a kör tilos zónája, és a
`schemaVersion` emelése az E12-R06 determinizmus-szerződését érintené.

A javaslat-lépés ezért a fingerprintet külön, **titkot nem tartalmazó**
sidecar JSON-ba írja (`dist/signing-certificate.json`), és a MEGLÉVŐ,
ismételhető `--artifact dist/signing-certificate.json` flaggel köti a
manifesthez: a manifest `artifacts[]` listája a fájlt névvel, úttal és
sha256-tal hordozza. A provenance-lánc így teljes, a séma és a determinizmus
érintetlen.

### D5 — A fingerprint-kiolvasás egyetlen titkot sem tesz megfigyelhetővé

A javasolt lépésre kötelező:

- a keystore jelszava **nem lehet nyílt parancssori argumentum** (a
  process-lista megfigyelhető) — a `keytool` `-storepass[:env|:file]` alakját
  vagy stdin-t kell használni;
- a `keytool` kimenete **nyersen nem íródik ki** (sem `echo`, sem `cat`, sem
  `set -x`); kizárólag a kinyert SHA-256 fingerprint kerül a sidecarba;
- minden titok-értékre `::add-mask::` fut, mielőtt bárhol felhasználnák;
- a sidecar JSON **kizárólag** a fingerprintet és a kulcs-aliast hordozza,
  keystore-tartalmat, jelszót vagy privát kulcsot soha.

**NEM elfogadható gyengítés:** „csak debug célból" ideiglenesen kiírt érték.
Ez a kör közvetlen tanulsága [L528](../LESSONS.md#l528)-ból: ott egy
szigorítást szolgáló ág maga echózta a teljes settings-szótárat titkokkal a
boot-logba — a szigorítás nem mentesít a titok-fegyelem alól, hanem a
legkockázatosabb helye annak.

### D6 — A statikus audit fixture-vezérelt, és nem „string van-e a fájlban" alakú

`tool/release/verify_signing_policy.py` **kizárólag a Python standard
könyvtárára** támaszkodik (a runner-image nem garantál third-party csomagot),
és a mérendő fájlok útvonalát paraméterben kapja, hogy fixture-ön is futhasson.

A gate-cella **két irányban** mér:

- a **valós** `android/app/build.gradle.kts` és `.github/workflows/release-apk.yml`
  fölött az audit **exit 0**;
- egy **fixture** bemeneten, amelyből a D2 szerinti elutasító ág hiányzik
  (vagy amely `androiddebugkey`-t rendel a production ághoz), az audit
  **nem-nulla** kilépéssel, a megsértett szabály megnevezésével áll meg.

Egyirányú, csak a valós fájlt zöldnek találó cella **nem elfogadható** — az a
mérés hiányát mutatná zöldnek (a `check_secrets_test.dart`
[L220](../LESSONS.md#l220) hibaosztálya).

A Dart gate-cella a `python3`-at az E12-R06 mintája szerint hívja
(`Process.runSync`, [ADR 0447](0447-release-manifest-provenance-and-sbom.md) D5);
`python3` hiánya a cellát **PIROSRA** váltja, néma skip tilos. A javaslat-fájl
YAML-jét a tesztfájlban élő **korlátozott részhalmaz-parser** ellenőrzi
(`package:yaml` a fán csak tranzitív, ADR 0444 D3).

### D7 — Kulcsanyag a repóba soha, a fixture szintetikus

Sem keystore, sem jelszó, sem privát kulcs nem kerül a fába — a teszt-fixture
sem valódi JKS, hanem szintetikus szöveg. A `check_secrets` scan a kör után is
tiszta; a fixture, ha titok-alakú tokent tartalmazna, a
`strumsight:allow-secret-file` marker helyett inkább **ne** tartalmazzon ilyet.

## Következmények

- A production APK-t debug tanúsítvánnyal előállítani a Gradle-oldalon
  strukturálisan lehetetlen lesz; a védelem a CI secretjeitől függetlenül,
  lokálisan is él.
- A fingerprint tényleges bekötése (a javaslat beillesztése a védett
  `release-apk.yml`-be) **merge utáni orchesztrátor/emberi lépés** marad,
  ugyanúgy, ahogy az E12-R06 provenance-javaslaté (ADR 0447 D4).
- A kulcs-runbook a repó egyetlen dokumentált forrása a backup/rotáció/
  hozzáférés/elvesztés eljárásoknak; ADR-erővel köti a jövőbeli köröket.

## Alternatívák

- **A `release` buildType globális szigorítása** — elutasítva: a Lab és a
  kör-gate APK-ját is megállítaná (D3, brief §5.3).
- **A manifest `schemaVersion` emelése a fingerprint-mezőért** — elutasítva:
  `tool/generate_release_manifest.dart` a kör tilos zónája, és az E12-R06
  determinizmus-szerződését érintené (D4).
- **A workflow közvetlen szerkesztése** — strukturálisan lehetetlen
  (Kontextus 7.), és a mérce-zóna szerkesztése amúgy sem a kör dolga
  (ADR 0321).
- **A fingerprint kiolvasása az APK-ból (`apksigner verify --print-certs`)**
  — elutasítva ebben a körben: a `apksigner` elérhetősége a runner-image-en
  nem mért, a keystore-ból olvasás pedig a már materializált, `umask 077`-tel
  védett fájlból megy.
