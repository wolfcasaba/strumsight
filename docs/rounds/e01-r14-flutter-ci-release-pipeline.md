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

- Fájlonkénti összefoglaló.
- Futtatott parancsok + TÉNYLEGES kimenet.
- Coverage-baseline számok (összesített + a kritikus core-modulok).
- Eltérések a tervtől és okuk.
- Nem futtatott ellenőrzések és okuk (várhatóan: a CI-dispatchek — Claude-oldal).
- Follow-up issue-k (várhatóan: keystore-generálás + secret-feltöltés).

## 11. Review — a Claude tölti ki

Link: `docs/reviews/e01-r14-review.md`
