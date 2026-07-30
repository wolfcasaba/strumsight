# E01-R14 — Flutter CI és release pipeline

Státusz: PLANNING (pre-flight 2026-07-30, kód újraolvasva: `main` @ `65b2014`)
SDD: docs/sdd/02-epic-01-core-platform.md § „Kör 14 — Flutter CI és release pipeline"
Branch: `codex/epic-01-round-14-flutter-ci`
Brief szerzője: Claude · Implementáció: Codex

> ✅ **Pre-flight elvégezve (2026-07-30, `main` @ `65b2014`)** — mért eredmények:
> (1) `build-apk.yml` az R12/R13 alatt **nem változott**, a §2 leírása érvényes;
> (2) `dart format --output=none --set-exit-if-changed tool` → **1 fájl, 0 változott**
> (a `tool/` MA formázott, tehát a §8/1 külön format-commit nem kell);
> (3) `flutter analyze lib/ test/ tool/` → **No issues found (3.3s)**;
> (4) `dart run tool/check_architecture.dart` → **OK (12 allowlisted deviation)**.
> Vagyis mind a négy új gate ZÖLD alappal indul — ha a Codexnál bármelyik piros,
> az az ő változtatásából jön, nem örökölt adósság.
> **Figyelem:** ez a kör magát a merge-gate workflow-t módosítja — a review-ban a
> workflow-diff a legfontosabb ellenőrzés, és az elfogadás bizonyítéka a kör-branchre
> dispatchelt ZÖLD futás az ÚJ gate-ekkel.

## 1. Cél

A `build-apk.yml` ma analyze + test + property gate + release APK — de **nincs
format gate, nincs architecture gate**, a `tool/` könyvtárat se formázás, se analyze
nem fedi, az artifact neve statikus, és a „release" APK **debug kulccsal** van
aláírva. A kör kimenete: a CI-ből hibás kód nem kaphat kiadható buildet — teljes
gate-sor (format/analyze/test/property/architecture), azonosítható artifactok,
és a production release elkülönítése fail-closed signing-szabállyal.

## 2. Jelenlegi állapot

Ténylegesen elolvasott kód (2026-07-29):

- **`.github/workflows/build-apk.yml`** — trigger: push main + `workflow_dispatch`
  (ADR 0052: körönként a round-branchre dispatchelve ez a merge-gate). Lépések:
  `flutter pub get` → `flutter analyze lib/ test/` (a **`tool/` kimarad**) →
  `flutter test` → property gate `PROPERTY_SEED=${{ github.run_id }}` (✓ megvan) →
  `flutter build apk --release` → artifact upload **statikus `strumsight-apk`**
  néven. **Nincs:** format gate, `dart run tool/check_architecture.dart`,
  asset-ellenőrzés, coverage.
- **`.github/workflows/lab-apk.yml`** — Lab-build `lab_build.json`
  `--dart-define-from-file`-lal; szándékosan gate-mentes (a build-apk fedi).
- **`android/app/build.gradle.kts`** — `release { signingConfig =
  signingConfigs.getByName("debug") }`, a kommentben előre rögzítve, hogy a
  production signing e kör (Kör 14) dolga. Release keystore-secret a repóban
  **nincs**.
- **App-oldal (R03):** `STRUMSIGHT_ENV` dart-define (development/lab/production),
  production fail-closed config-validáció már létezik (`lib/app/config/`).
- **`tool/`:** `check_architecture.dart` (R10) — lokálisan és tesztben fut, CI-ben nem.
- **Verzió:** `pubspec.yaml` `version: 1.0.0+1` (egyetlen forrás, ADR 0051).
- **Guard-tesztek** (l10n parity, legacy-identifier, dio-factory, prefs-import) a
  `flutter test` részeként már futnak CI-ben — a 14.7 „régi package név” és „l10n
  parity” pontja így már fedett. A `test/tooling/` ma 5 guardot tartalmaz
  (`diagnostics_storage_separation`, `dio_factory_guard`, `legacy_identifier_guard`,
  `preferences_plugin_import_guard`, `route_literal_guard`).
- **Asset-deklarációk (`pubspec.yaml` 48–80):** `assets:` alatt **4** ML-bin
  (`assets/ml/strum_crnn.bin`, `strum_crnn_live.bin`, `strum_crnn_live_3c.bin`,
  `chord_crnn.bin` — mind létezik, 0.87–1.46 MB), `fonts:` alatt **6** ttf
  (5× Poppins + Montserrat, mind létezik). Nincs `assets/` könyvtár-szintű
  (trailing-slash) deklaráció, tehát a check-nek elég a fájl-szintű felsorolás
  és a `fonts: … - asset:` bejegyzések bejárása.
- **⚠ Csapda:** `ml/strum_direction.tflite` **0 bájt**, de **NEM** pubspec-deklarált
  asset (a `ml/` a tréning-fa, nem a bundle). A check kizárólag a pubspec-ből
  olvasott útvonalakat vizsgálhatja — egy „minden `.bin`/`.tflite` a repóban nem
  üres” jellegű söprés azonnal pirosra vinné a gate-et örökölt okból.
- **R11-review MINOR-1 (nyitott follow-up, ide szólt):**
  `test/tooling/route_literal_guard_test.dart` regexe csak a
  `context.go|push('/…')` alakra illeszkedik, a `router.go('/…')`-ra vak — pont
  arra a hívásformára, amit az R11 bevezetett. **Mérve most (2026-07-30):** a
  javasolt szélesebb regex (`\.\s*(?:go|push|replace|pushReplacement|goNamed)\s*\(\s*['”]/`,
  a katalógusfájl kizárva) a MAI `lib/`-en **0 találat** → a szigorítás
  `lib/`-változtatás nélkül zöld. (A `_client.getJson('/settings')` típusú
  API-útvonalak nem illeszkednek, mert nem `go`/`push` metóduson vannak.)

## 3. Scope

**Benne:**

- `build-apk.yml` bővítése — új lépések a meglévők ELÉ/MELLÉ:
  - `dart format --output=none --set-exit-if-changed lib test tool`
  - `flutter analyze lib/ test/ tool/` (a mai lépés kiterjesztése)
  - `dart run tool/check_architecture.dart`
  - asset-ellenőrzés: minden pubspec-deklarált asset létezik (a 4 ML-bin ÉS a 6
    font is) + a 4 ML-bin nem üres (a checksum-manifest a Kör 15 dolga — itt csak
    létezés/nem-üres). A vizsgált útvonal-halmaz **kizárólag** a pubspec
    `flutter: assets:` + `fonts: … asset:` bejegyzéseiből jön (lásd §2 csapda).
  - coverage: `flutter test --coverage` a meglévő test-lépés helyett + a report
    artifactként feltöltve (**küszöb NÉLKÜL** — először baseline)
  - artifact-elnevezés: `strumsight-<version>-<buildNumber>-<sha7>-<env>.apk`
    (verzió a pubspec-ből parse-olva a workflow-ban).
- Új `release-apk.yml` (CSAK `workflow_dispatch`): production release —
  `STRUMSIGHT_ENV=production` dart-define, keystore a repo-secretekből
  (base64 keystore + jelszavak); **bármelyik secret hiánya → a workflow elhasal**
  (fail-closed), debug signingra visszaesés tilos; `lab_build.json` / Lab-konfig
  nem kerülhet az artifactba.
- `android/app/build.gradle.kts`: release signing a `key.properties`/env alapján,
  ha jelen van; ha nincs, a **lokális** `flutter run --release` továbbra is debug
  kulccsal megy (dev-élmény marad), de a production workflow a secretet követeli meg.
- `android/key.properties.example` minta + `.gitignore` bejegyzés a valódira.
- Coverage-baseline dokumentálása a §10-ben (a kritikus core-modulok — config,
  foundation, storage migrator, network mapper, audio coordinator — mért értékei).
- **R11-review MINOR-1 lezárása:** `test/tooling/route_literal_guard_test.dart`
  regexének szélesítése a receiver elhagyásával és a további navigációs metódusok
  bevonásával (`go|push|replace|pushReplacement|goNamed`), a katalógusfájl
  (`lib/app/routing/app_route.dart`) továbbra is kizárva. A guard **hatóköre és
  állítása** változik, a `lib/` NEM. Ha a szélesítés a mai `lib/`-en pirosra fordul
  (a §2 mérés szerint nem fordulhat), az **MEGÁLLÁS és jelentés** — a guardot
  visszagyengíteni vagy a `lib/`-et hozzáigazítani ebben a körben tilos.

**Kívül (ebben a körben TILOS):**

- Backend CI, ML-manifest/checksum gate (Kör 15).
- Verziószám-emelés, tényleges store-release, Play-konfiguráció.
- Globális coverage-küszöb bevezetése (SDD 14.8: előbb baseline).
- `lab-apk.yml` átalakítása (marad lean; csak akkor nyúlj hozzá, ha az
  artifact-elnevezést oda is kérné — nem kéri).
- Bármilyen `lib/`-viselkedésváltozás; a `tool/` alatt csak az asset-check script
  új fájlja + az esetleges format-diff megengedett.

## 4. Engedélyezett fájlok

Csak az alábbi útvonalak módosíthatók. Bármi más → **MEGÁLLÁS és jelentés**.

| Útvonal | Miért |
|---|---|
| `.github/workflows/build-apk.yml` | gate-sor + artifact-név + coverage |
| `.github/workflows/release-apk.yml` | ÚJ — production release, fail-closed signing |
| `android/app/build.gradle.kts` | release signing key.properties-ből, dev-fallback szabályozva |
| `android/key.properties.example` | ÚJ — minta |
| `android/.gitignore` | `key.properties` kizárása — **mérve: már benne van** (`key.properties`, `**/*.keystore`, `**/*.jks`), így itt várhatóan nincs diff |
| `tool/ci/check_assets.dart` | ÚJ — pubspec-asset létezés + ML-bin nem-üres |
| `test/tooling/check_assets_test.dart` | ÚJ — az asset-check logikájának tesztje |
| `test/tooling/route_literal_guard_test.dart` | R11-review MINOR-1: **csak a regex szélesítése** (+ a hozzá tartozó `reason`/komment); a bejárási logika és a katalógus-kizárás marad |
| `tool/**` (format-diff) | csak ha a format gate megköveteli — a pre-flight szerint MA nem kell |
| `docs/rounds/e01-r14-flutter-ci-release-pipeline.md` | **csak a 10. szekció** |

**Tilos zóna:** `lib/**`, `test/**` (a fenti két fájlon kívül), `backend/**`,
`ml/**`, `pubspec.yaml`, `lab_build.json`, `.github/workflows/{lab-apk,chord-train,ml-train,dsp-probe}.yml`,
`docs/**` (a fenti fájl §10-én kívül), `HANDOFF.md`, ADR-ek.

## 5. Kötött architekturális döntések

Előre kiosztott ADR-szám: **`0062`** — az ADR-t Claude írja.

1. **A `build-apk.yml` marad az ADR 0052-es kör-gate** — neve, triggerei és a
   „minden gate egy workflow-ban" elve nem változik; a kör CSAK bővíti.
2. **Három build-típus:** Development (build-apk.yml, debug signing),
   Lab (lab-apk.yml, debug signing, dart-define-from-file), Production
   (release-apk.yml, csak dispatch, valódi keystore). A production job
   **semmilyen ágon** nem eshet vissza debug signingra — a secret hiánya a
   workflow hibája, nem fallback.
3. **Asset-check Dart-scriptként** (`tool/ci/check_assets.dart`), nem bash-ben:
   így lokálisan futtatható és tesztelhető (a `check_architecture.dart` mintája —
   a CLI és a teszt ugyanazt a logikát hívja).
4. **Artifact-név a pubspec-ből** származik, kézzel beírt verzió a workflow-ban
   tilos (ADR 0051: a pubspec az egyetlen verzió-forrás).
5. **Coverage küszöb nélkül.** A lépés informatív (report-artifact + baseline a
   §10-ben); piros gate-et coverage-ből ez a kör nem csinál.
6. **A gate-ek sorrendje:** olcsó → drága (format → analyze → architecture →
   asset-check → test+coverage → property → build), hogy a tipikus hiba percek
   alatt derüljön ki.

## 6. Acceptance criteria

- [ ] A kör-branchre dispatchelt `build-apk.yml` futás ZÖLD az ÚJ gate-sorral
      (format, analyze `tool/`-lal, architecture, asset-check, coverage, property, build).
- [ ] Bizonyított piros út: egy szándékosan elrontott commit (pl. formázatlan fájl
      VAGY üresre truncate-elt ML-bin) a megfelelő gate-en elhasal — a §10-ben a
      futás linkjével dokumentálva, majd a rontás visszavonva.
- [ ] Az artifact neve tartalmazza a verziót, build numbert, rövid SHA-t és az
      env-et (a zöld futás artifact-listájával bizonyítva).
- [ ] `release-apk.yml` secret nélkül dispatchelve **kontrolláltan elhasal** a
      signing-előfeltétel lépésén (fail-closed bizonyíték — futás-link a §10-ben);
      debug-signing fallback ág a workflow-ban nem létezik.
- [ ] `flutter build apk --release` lokális/dev útja változatlanul működik
      (build.gradle.kts: key.properties hiányában dev-viselkedés).
- [ ] `dart run tool/ci/check_assets.dart` lokálisan zöld; teszttel fedett
      (létező asset, hiányzó asset, üres bin esetek).
- [ ] A szélesített route-literál guard **zöld a változatlan `lib/`-en**, ÉS
      valódi-sértés próbával bizonyítottan piros egy ideiglenesen beinjektált
      `router.go('/live')` literálra (§10-ben a két kimenettel dokumentálva,
      a rontás visszavonva) — ez a mai `context.go`-nál szélesebb hatókör
      bizonyítéka, nem elég a puszta zöld.
- [ ] `git diff --stat main...` kizárólag a §4 tábláját tartalmazza.

## 7. Kötelező ellenőrzések

Külön parancsokként (`AGENTS.md` §12):

```bash
~/flutter/bin/dart format --output=none --set-exit-if-changed lib test tool
~/flutter/bin/flutter analyze lib/ test/ tool/
~/flutter/bin/dart run tool/check_architecture.dart
~/flutter/bin/dart run tool/ci/check_assets.dart
~/flutter/bin/flutter test test/tooling
```

A pre-flight szerint az első három parancs a kör ELŐTT is zöld volt (fejléc) —
bármelyik piros a Codex változtatásából jön.

A workflow-változás valódi próbája a CI-dispatch — az **Claude-oldal** (ADR 0052,
a Codex ne hívjon `gh`-t): zöld út + a két piros bizonyíték-futás.

## 8. Implementációs sorrend

1. `tool/` format-rendezés — a pre-flight szerint **nem kell** (0 változott);
   ha a saját új fájl formázatlan, azt a saját commitjában rendezd.
2. `tool/ci/check_assets.dart` + teszt (lokálisan zöldre).
3. Route-literál guard regex szélesítése + valódi-sértés próba (R11 MINOR-1).
4. `build-apk.yml` gate-sor + artifact-név + coverage.
5. `build.gradle.kts` signing-átalakítás + `key.properties.example` + gitignore
   (**megjegyzés:** az `android/.gitignore` a `key.properties`-t, `**/*.keystore`-t
   és `**/*.jks`-t **már kizárja** — ott vélhetően nincs teendő, csak ellenőrzés).
6. `release-apk.yml` (fail-closed secret-ellenőrzéssel).
7. §10 kitöltése (baseline coverage-számokkal) — a dispatch-bizonyítékokat a
   Claude-oldal pótolja a review-ban.

## 9. Kockázatok

- **Az élő merge-gate módosítása.** Egy szintaktikailag hibás workflow minden
  további kört blokkol — a YAML-t kicsi, ellenőrizhető lépésekben kell bővíteni,
  és a kör el sem fogadható zöld dispatch nélkül.
- **`tool/` formázatlansága.** A pre-flight szerint a `tool/` ma formázott (0
  változott), tehát ez a kockázat elhárult; ha mégis diff keletkezik, az külön
  commit (lásd R02 mintáját), különben a review-diff olvashatatlan.
- **Asset-check túl-söprése.** A `ml/strum_direction.tflite` 0 bájtos a repóban;
  ha a check nem szigorúan a pubspec-deklarált halmazt járja be, a gate örökölt
  okból pirosra fordul, és a „megoldás" a tréning-fa megbontása lenne — ami tilos
  zóna. A bejárás forrása kizárólag a pubspec.
- **Guard-szélesítés visszahatása.** A szélesebb regex a `test/` fát nem járja
  (csak `lib/`), de ha valaki később `Directory('test')`-re is kiterjeszti, a
  guard-tesztek saját fixture-literáljai azonnal pirosra vinnék — a hatókör
  maradjon `lib/`.
- **Keystore még nincs.** A production release-hez valódi keystore kell — ez a
  kör CSAK a fail-closed mechanizmust szállítja; a keystore-generálás és a
  secret-feltöltés user-döntés, follow-upként rögzítendő (nem blokkolja a kört,
  mert az elfogadás a kontrollált elhasalás).
- **Coverage-lépés ideje.** `flutter test --coverage` lassabb a simánál; ha a
  CI-idő érdemben nő (>~2 perc), a §10-ben jelezni — a döntés (marad/külön job)
  review-kérdés.
- **Windows-vonal a gradle-ben nincs** — de a `key.properties`-olvasás Kotlin-DSL
  mintáját a Flutter-doksi szerinti kanonikus formában kell átvenni, kézzel
  fabrikált variáns helyett.

## 10. Implementation handoff — a Codex tölti ki

### Összefoglaló és commitok

Branch: `codex/epic-01-round-14-flutter-ci`.

Az implementáció olvasható, logikai commitjai:

1. `69b83af` — `ci(flutter): validate declared bundle assets`;
2. `6ab12ce` — `test(routing): widen route literal guard`;
3. `39dc26c` — `ci(flutter): enforce release build quality gates`;
4. `d1b8469` — `build(android): configure fail-closed release signing`;
5. `aaca916` — `ci(android): add fail-closed production APK workflow`.

### Fájlonkénti összefoglaló

- `.github/workflows/build-apk.yml` — a kötelező gate-sorrend:
  format → analyze (`tool/`-lal) → architecture → asset → teljes test coverage-dzsel
  → friss seedű property → development APK. A coverage LCOV külön artifact. A
  `pubspec.yaml` `version+buildNumber` mezőjéből és a rövid SHA-ból készül a
  `strumsight-<version>-<build>-<sha7>-development.apk` név; a workflow a fizikai
  APK-fájlt is erre nevezi át, nem csak az artifact-konténert.
- `.github/workflows/release-apk.yml` — új, kizárólag `workflow_dispatch`
  production pipeline. A négy signing secretet első lépésben, név szerint,
  értékkiírás nélkül ellenőrzi; a teljes gate-sor után temp-keystore-ból,
  `STRUMSIGHT_ENV=production` beállítással és kötelező release signinggal buildel.
  A keystore nem kerül outputba/artifactba, és az `always()` cleanup törli.
- `android/app/build.gradle.kts` — a Flutter kanonikus
  `android/key.properties` mintáját és egy CI-env forrást támogat. A két forrás
  mezőnként nem keverhető: részleges file vagy részleges env kontrollált
  `GradleException`. Konfiguráció nélkül a development/lab release-mode build
  továbbra is debug signingot kap; `STRUMSIGHT_REQUIRE_RELEASE_SIGNING=true`
  mellett nincs fallback.
- `android/key.properties.example` — secretmentes lokális minta, az
  `android/app`-hoz viszonyított `storeFile` út dokumentálásával.
- `android/.gitignore` — nem változott: a `key.properties`, `**/*.jks` és
  `**/*.keystore` kizárása már megvolt; ezt `git check-ignore -v` igazolta.
- `tool/ci/check_assets.dart` — dependency nélküli, tesztelhető Dart gate. Csak a
  top-level pubspec `flutter.assets` és `flutter.fonts[*].fonts[*].asset`
  útvonalait járja; minden deklarált út létezését és a deklarált
  `assets/ml/*.bin` fájlok nemürességét ellenőrzi.
- `test/tooling/check_assets_test.dart` — létező asset+font, minden hiányzó
  deklaráció, üres deklarált ML-bin, üres font és nem deklarált üres
  `ml/strum_direction.tflite` esetei. A valós pubspec-szerkezetet is őrzi, ahol
  a `dependencies.flutter` megelőzi a top-level `flutter:` blokkot.
- `test/tooling/route_literal_guard_test.dart` — a regex receiver-független és
  a `go|push|replace|pushReplacement|goNamed` hívásokat fedi; a katalógusfájl
  kizárása és a bejárási logika változatlan.
- Ez a brief — csak a jelen §10 implementation handoff szakasza változott.

### Futtatott parancsok és tényleges eredmények

Módosítás előtti baseline:

- `~/flutter/bin/flutter pub get` → `Got dependencies!`;
- `~/flutter/bin/dart format --output=none --set-exit-if-changed lib test tool`
  → `Formatted 446 files (0 changed)`;
- `~/flutter/bin/flutter analyze lib/ test/ tool/` → `No issues found`;
- `~/flutter/bin/dart run tool/check_architecture.dart` →
  `Architecture dependencies OK (12 allowlisted deviation(s)).`;
- `~/flutter/bin/flutter test test/tooling` → `9` teszt, mind zöld.

Asset-check TDD és valódi-sértés:

- első RED: az új teszt a még nem létező `tool/ci/check_assets.dart` import és
  `checkAssets` miatt compile-hibával állt meg;
- a valós pubspec első futása feltárt egy false-green parserhibát (`0 declared
  asset(s)`): a nested `dependencies.flutter` kulcsot tévesztette össze a
  top-level blokkal. A realisztikus fixture RED-je `Expected: [...] Actual: []`
  volt; az `indent == 0` root-cause fix után zöld;
- `~/flutter/bin/flutter test test/tooling/check_assets_test.dart` → `3` teszt,
  mind zöld;
- `~/flutter/bin/dart run tool/ci/check_assets.dart` →
  `Asset check OK (10 declared asset(s), 4 non-empty ML binary/binaries).`;
- eldobható fixture-sértés: a deklarált `assets/ml/model.bin` helyett más fájl
  létrehozásakor a pozitív teszt exit `1`, `Expected: true, Actual: false`;
  visszaállítás után a teljes asset-teszt ismét `3/3` zöld.

Route-literál valódi-sértés:

- változatlan `lib/` mellett
  `~/flutter/bin/flutter test test/tooling/route_literal_guard_test.dart` →
  `1/1` zöld;
- ideiglenesen az `app_router.dart` meglévő exception ágába került a tényleges
  `router.go('/live')`; a guard exit `1` és pontosan
  `lib/app/routing/app_router.dart:40` találatot adott;
- a visszaállítás után a fájl git-object hash-e ismét
  `99efa057ad29d5c452e3ea6ab15b0dfe3bbac0cb`, a `git diff -- lib` üres, a
  route-guard ismét `1/1` zöld.

Workflow- és signing-statikus ellenőrzések:

- PyYAML parse → `YAML syntax OK: 2 workflows`;
- checksum-ellenőrzött `actionlint 1.7.12` a két módosított workflow-n →
  exit `0`, megállapítás nélkül;
- a workflow pontos metadata-scriptje fake SHA-val:
  `strumsight-1.0.0-1-0123456-development.apk`, illetve
  `strumsight-1.0.0-1-0123456-production.apk`;
- a production signing-preflight üres envvel exit `1`, és kizárólag a négy
  hiányzó secret nevét írta ki; dummy nem-secret értékekkel csendes exit `0`;
- `git check-ignore -v` igazolta a `key.properties`, `.jks` és `.keystore`
  szabályokat; a `key.properties.example` nincs ignore-olva.

Végleges kötelező lokális gate-ek:

- `~/flutter/bin/dart format --output=none --set-exit-if-changed lib test tool`
  → `Formatted 448 files (0 changed)`;
- `~/flutter/bin/flutter analyze lib/ test/ tool/` →
  `No issues found! (ran in 3.5s)`;
- `~/flutter/bin/dart run tool/check_architecture.dart` →
  `Architecture dependencies OK (12 allowlisted deviation(s)).`;
- `~/flutter/bin/dart run tool/ci/check_assets.dart` →
  `Asset check OK (10 declared asset(s), 4 non-empty ML binary/binaries).`;
- `~/flutter/bin/flutter test test/tooling` → `12` teszt, mind zöld.

### Coverage baseline

A teljes suite lokálisan az ADR 0053 és a brief §7 szerint nem futott. A helyi
baseline ezért explicit célzott report: nyolc releváns tesztútvonal,
`--coverage-path=/tmp/e01-r14-critical-with-auth.lcov`; eredmény: `81` teszt,
mind zöld.

```bash
~/flutter/bin/flutter test --no-pub --coverage \
  --coverage-path=/tmp/e01-r14-critical-with-auth.lcov \
  test/app/app_bootstrap_test.dart \
  test/app/app_config_test.dart \
  test/core/foundation/app_result_test.dart \
  test/core/storage/storage_migrator_test.dart \
  test/core/storage/preference_migration_test.dart \
  test/core/network/network_failure_mapper_test.dart \
  test/features/auth/auth_repository_test.dart \
  test/core/audio/audio_session_coordinator_test.dart
```

- célzott report összesen: **432 / 901 = 47,95%**;
- az öt kijelölt kritikus modul együtt: **214 / 243 = 88,07%**;
- config (`lib/app/config/`): **47 / 59 = 79,66%**;
- foundation result/failure: **32 / 42 = 76,19%**;
- storage migrator: **64 / 68 = 94,12%**;
- network failure mapper (az auth fogyasztói tesztjével): **31 / 34 = 91,18%**;
- audio session coordinator: **40 / 40 = 100,00%**.

A `config` és `foundation` a Chapter 2 §14.8 90%-os célja alatt van. Ebben a
körben nincs coverage-küszöb, és e modulok tesztfájljai nincsenek az
engedélyezett fájllistán, ezért az eredményt baseline-ként rögzítettük, nem
scope-on kívüli tesztbővítéssel „javítottuk”. A teljes-repo összesített baseline
a Claude-oldali teljes CI `coverage/lcov.info` artifactból pótlandó.

### Eltérések a tervtől és okuk

- `android/.gitignore` nem kapott diffet, mert a brief pre-flightjának megfelelő
  mindhárom szükséges szabály már létezett.
- A dependency nélküli parser első változata a valós pubspecen false-green lett
  a `dependencies.flutter` miatt. Nem workaround készült: reprodukáló fixture
  után a parser kizárólag top-level `flutter:` blokkot fogad el.
- A production workflow megismétli a teljes gate-sort. Így kézi dispatchnél egy
  tetszőleges ref sem kerülhet közvetlenül signing/build lépésre a minőségi
  gate-ek megkerülésével.

### Nem futtatott ellenőrzések és ok

- Teljes `flutter test`, randomizált property gate és APK-build: kizárólag a
  Claude-oldali, branchre dispatch-elt CI feladata (ADR 0052/0053/0055).
- `flutter build apk --release` és Gradle Android build lokálisan: a boxon nincs
  Android SDK, és a brief kifejezetten tiltja a próbát is.
- `build-apk.yml` zöld run, verziózott artifact-lista és CI-s teljes coverage:
  nincs Codex-oldali dispatch; Claude pótolja a push után.
- `release-apk.yml` secret nélküli piros run-link: az új
  `workflow_dispatch` workflow a GitHub platformszabálya szerint csak azután
  indítható, hogy a fájl már a default branchen létezik. Ezért a merge előtti
  branchről technikailag nem szerezhető run-link; post-merge/default-branch
  bizonyíték szükséges. Helyben a pontos preflight-script piros útja igazolt.
- Valódi production signing-success: nincs keystore és nincsenek feltöltött
  signing secretek; ez a kör szándékos fail-closed állapota.

### Kockázatok és follow-upok

1. A tulajdonos generálja/őrzi a production upload keystore-t, majd feltölti a
   `ANDROID_KEYSTORE_BASE64`, `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_ALIAS` és
   `ANDROID_KEY_PASSWORD` repo secreteket; egyik érték sem kerülhet commitba.
2. Claude a push után dispatch-eli a `build-apk.yml`-t, begyűjti a zöld teljes
   suite/property/APK/coverage bizonyítékot és a verziózott artifact-nevet.
3. A `release-apk.yml` default-branchre kerülése után külön secret nélküli
   dispatch igazolja a signing-preflight kontrollált piros útját.
4. Következő coverage-körben a config és foundation hiányzó ágai célzott
   teszteket igényelnek a 90%-os modulcél eléréséhez; globális küszöb továbbra
   sem vezethető be a teljes CI-baseline review-ja előtt.

## 11. Review — a Claude tölti ki

Link: `docs/reviews/e01-r14-review.md`
