# E01-R14 review — Flutter CI és release pipeline

- **Kör:** E01-R14 · brief: `docs/rounds/e01-r14-flutter-ci-release-pipeline.md`
- **Branch:** `codex/epic-01-round-14-flutter-ci` · review-alap: `62adeef`
- **Implementáció:** Codex · **Review:** Claude (2026-07-30)
- **ADR:** [0062](../adr/0062-ci-gate-chain-and-fail-closed-release-signing.md)
  (Claude írta, a brief §5 döntései szerint)

BLOCKER: 0 · MAJOR: 0 · MINOR: 3 · NOTE: 4

## Scope-audit

`git diff --stat main...HEAD` a review-alapon, a brief §4 táblájával összevetve:

| Fájl | §4-ben | Megjegyzés |
|---|---|---|
| `.github/workflows/build-apk.yml` | ✅ | +69/−18 |
| `.github/workflows/release-apk.yml` | ✅ | ÚJ, 138 sor |
| `android/app/build.gradle.kts` | ✅ | +87 |
| `android/key.properties.example` | ✅ | ÚJ, 7 sor |
| `tool/ci/check_assets.dart` | ✅ | ÚJ, 201 sor |
| `test/tooling/check_assets_test.dart` | ✅ | ÚJ, 104 sor |
| `test/tooling/route_literal_guard_test.dart` | ✅ | +5/−2, csak a regex + `reason` |
| `docs/rounds/e01-r14-…md` | ✅ | csak a §10 |

`android/.gitignore` diff nélkül — a brief pre-flightja ezt előre jelezte
(a három szabály már megvolt). **`git diff --stat main...HEAD -- lib/` üres**
(függetlenül újramérve). Scope-túllépés nincs.

**Eljárási megjegyzés (Claude hibája, rendezve):** az induló `dbdef5a` planning
commit tartalmazta a `.claude/skills/round-brief-prep/SKILL.md`-t, ami NEM volt a
§4 listán. A Codex a kötelező scope-audit során ezt megtalálta, **helyesen megállt
és nem pusholt**, ahelyett hogy önhatalmúlag törölte vagy némán átengedte volna.
A §4-et utólag kitágítani a saját fájlom kedvéért önkiszolgáló szerződésmódosítás
lett volna, ezért a branch rebase-elve lett: a planning commitból a skill kikerült,
a végső diff pontosan a fenti tábla. A skill külön, kör-független committal megy
a `main`-re.

## Mit ellenőriztem és hogyan

### 1. A gate-sor (`build-apk.yml`) — a kör legkockázatosabb diffje

A sorrend a brief §5/6 szerinti olcsó → drága: `pub get` → format → analyze
(`lib/ test/ tool/`) → architecture → asset → `flutter test --coverage` →
coverage-artifact → property gate (friss `run_id` seed) → APK-metadata →
build → verziózott staging → upload.

Ellenőrzött részletek:

- A property gate `PROPERTY_SEED: ${{ github.run_id }}` **változatlanul megvan**
  — a HORIZON anti-reward-hacking szabály nem sérült a lépéssor átrendezésekor.
- A `flutter test` → `flutter test --coverage` csere nem szűkíti a suite-ot
  (nincs útvonal-szűkítés), tehát az ADR 0053 „teljes suite CI-ben" garanciája áll.
- Az artifact-név a pubspecből jön, `<version>+<build>` regex-validációval; kézzel
  írt verzió nincs (ADR 0051 ✔). A workflow a **fizikai fájlt** is átnevezi, nem
  csak az artifact-konténert — az `if-no-files-found: error` mindkét uploadon ott van.
- A staging lépés `[[ ! -s "$source_apk" ]]`-vel véd a 0 bájtos APK ellen.

### 2. Fail-closed production signing

Ez a kör lényegi biztonsági állítása, ezért soronként néztem:

- `release-apk.yml`: a signing-preflight az **első** lépés, még a `checkout` előtt
  — hiányzó secret esetén a job azonnal elhasal, kód lefutása nélkül. A hibaüzenet
  csak a secret **nevét** írja ki, értéket nem.
- **Debug-signing fallback ág a production workflow-ban nem létezik** (grep-pel
  ellenőrizve: se `signingConfigs`, se `debug` hivatkozás).
- Kettős védelem: a build lépés `STRUMSIGHT_REQUIRE_RELEASE_SIGNING=true`-t is ad,
  amire a Gradle `GradleException`-nel áll meg, ha a signing-értékek hiányoznak.
  Tehát a workflow-preflight megkerülése esetén is fail-closed marad.
- A keystore `RUNNER_TEMP`-be, `umask 077` alatt dekódolódik, üres dekódolt fájlra
  elhasal, és `if: always()` cleanup törli. Artifactba nem kerül.
- Lab-szivárgás nincs: a production workflow nem használ `--dart-define-from-file`-t,
  `lab_build.json`-t nem érint.
- `build.gradle.kts`: a forrás-precedencia `key.properties` → env; a két forrás
  mezőnként **nem keverhető** (részleges konfiguráció = `GradleException`), a
  keystore-fájl létezését és nem-ürességét is ellenőrzi. `key.properties` és env
  hiányában a release build debug kulcsot kap → a **lokális** dev-út él (a brief
  §6 kritériuma), miközben a production garanciát a workflow adja.

### 3. Asset-gate

A bejárás kizárólag a top-level `flutter.assets` és `flutter.fonts[*].fonts[*].asset`
útvonalait fogja — pontosan ahogy a brief §2 csapdája megkövetelte. A `main`-en
mérve: `Asset check OK (10 declared asset(s), 4 non-empty ML binary/binaries)` —
egyezik a pre-flight során számolt 4 ML-bin + 6 font halmazzal, és a **0 bájtos,
nem deklarált `ml/strum_direction.tflite` nem viszi pirosra** (a teszt explicit
esetként őrzi ezt).

Kiemelendő: a Codex TDD közben talált egy **false-green parser-hibát** (a nested
`dependencies.flutter` kulcsot összetévesztette a top-level blokkal → `0 declared
asset(s)`), és nem workaroundolta, hanem reprodukáló fixture után az `indent == 0`
feltétellel a gyökérokot javította. Ez a helyes eljárás — a hiba pont a gate
értelmét oltotta volna ki.

### 4. R11-review MINOR-1 lezárása — függetlenül újramérve

Nem elégedtem meg a zölddel, mert az önmagában nem bizonyítja a tágabb hatókört.
Injektáltam egy `router.go('/live')` literált
(`lib/features/onboarding/screens/onboarding_screen.dart`), majd **ugyanazon a
sértésen** futtattam mindkét guard-verziót:

| Guard | Eredmény az injektált `router.go('/live')`-ra |
|---|---|
| régi (`main`, `\bcontext\.(go\|push)`) | **zöld** — vak rá |
| új (`\.(go\|push\|replace\|pushReplacement\|goNamed)`) | **PIROS** |

A rontás visszavonva; `git status` tiszta, a guard ismét `1/1` zöld. Az R11
MINOR-1 ezzel bizonyítottan lezárva.

## Megállapítások

### MINOR-1 — az asset-gate üres deklarációs halmazon némán zöld

`tool/ci/check_assets.dart` nem állít alsó korlátot: ha a pubspec `assets:`
blokkja eltűnik vagy elgépelődik, a `declaredPaths` üres, `issues` üres, a report
`isClean` → **exit 0**.

**Mérve** (eldobható fixture, `flutter:` blokk `assets:` nélkül):

```
Asset check OK (0 declared asset(s), 0 non-empty ML binary/binaries).
EXIT=0
```

A gate célja épp az, hogy hiányzó ML-modell ne juthasson buildbe — a deklaráció
törlése viszont pontosan ez a hibamód, és a gate rá vak marad. A brief betűjének
megfelel („minden deklarált asset létezik"), ezért nem blokkol.

Javaslat: a gate követeljen meg egy minimális, névvel nevezett halmazt (a négy
`assets/ml/*.bin`), vagy a **Kör 15** checksum-manifestje vegye át ezt a szerepet
— a manifest természeténél fogva alsó korlát is. Follow-up: E01-R15.

### MINOR-2 — a gate-sor duplikálva van a két workflow között

A `release-apk.yml` szó szerint megismétli a `build-apk.yml` kilenc gate-lépését.
A Codex indoklása helyes és elfogadható (kézi dispatchnél tetszőleges ref se
kerülhesse meg a minőségi kapukat), de a duplikáció **drift-kockázat**: ha a
Kör 15 backend/ML gate-et ad a `build-apk.yml`-hez és a `release-apk.yml`-t
kihagyja, a production build **kevésbé** lesz gate-elve, mint a fejlesztői —
csendben, mert mindkét workflow zöld marad.

Javaslat: a közös lépéssort composite action-be (`.github/actions/quality-gates`)
kiemelni, vagy a `release-apk.yml`-t a `build-apk.yml` `workflow_call`-jára
építeni. Follow-up: E01-R15/R16. Nem blokkol, mert ma a két lista bizonyítottan
azonos.

### MINOR-3 — a CI-idő a brief §9-ben megadott küszöb fölé nőtt

A brief §9 előre kikötötte: ha a coverage-lépéstől a CI-idő érdemben (>~2 perc)
nő, az review-kérdés. **Mérve** (`gh run list`, sikeres futások):

| Futás | Branch | Idő |
|---|---|---|
| 30494875280 | `main` (R14 előtt) | 9m |
| 30494821089 | `main` (R14 előtt) | 9m |
| 30494147150 | R13 kör-branch | 9m |
| **30513701633** | **R14 kör-branch (ÚJ gate-sor)** | **11m** |

A növekmény ~2,5 perc, tehát a küszöb fölött van — a brief szerint tehát ki kell
mondanom. A növekmény döntő része a `flutter test --coverage` (a suite lényegében
kétszer fut le: teljes + property gate, most VM-coverage-dzsel az elsőn).

Nem blokkol: 11 perc még bőven a kör-ciklus alatt van, és a coverage-adat most
először áll elő. Ha a szám tovább nő (Kör 15 backend/ML gate-eket hoz),
a coverage-lépést külön, a merge-gate-tel párhuzamos jobba érdemes emelni —
akkor a gate-sor kritikus útja visszaesik ~9 percre. Follow-up: E01-R15/R16.

### NOTE-1 — a `STRUMSIGHT_ENV=development` define viselkedésileg no-op

`lib/app/config/app_environment.dart:36`: hiányzó/üres define → `development`.
Az új `--dart-define=STRUMSIGHT_ENV=development` tehát nem változtatja a
development APK viselkedését, csak explicitté teszi (és szimmetriát ad a
production workflow-val). Ez rendben van — jelzem, hogy a review megnézte, és
nem rejtett viselkedésváltozás.

### NOTE-2 — a guard metóduslistája aszimmetrikus

`goNamed` benne van, `pushNamed` / `pushReplacementNamed` nincs. A named-változatok
route-**nevet** várnak, nem útvonalat, így a `'/`-ra illesztő regex náluk amúgy is
ritkán fogna; a lista egyébként pontosan a brief §3-ban előírt. Nem hiba, csak
rögzítem, hogy tudatos-e: ha később named-route-ok jönnek, a listát érdemes
újranézni.

### NOTE-3 — a brief egyik acceptance criteriumát én írtam teljesíthetetlenre

A §6 elvárta a `release-apk.yml` secret nélküli dispatchének **futás-linkjét** még
a kör elfogadásához. A GitHub `workflow_dispatch` viszont csak akkor indítható,
ha a workflow-fájl már a **default branchen** van — merge előtt tehát technikailag
nem szerezhető run-link. Ez az én brief-hibám, nem implementációs hiány; a Codex
helyesen jelezte és lokálisan igazolta a preflight-script piros útját (üres env →
exit 1, csak a négy secret nevével).

**Kezelés:** a kritérium merge UTÁNI kötelezettséggé alakul — a merge után
azonnal dispatchelem a `release-apk.yml`-t secret nélkül, és a kontrollált piros
futás linkjét ide, a review aljára rögzítem. A merge-öt nem blokkolja, mert az
elhasalás mechanizmusa kódszinten és lokálisan is igazolt.

### NOTE-4 — hibás `key.properties` a debug buildet is megállítja

A signing-konfiguráció gradle **configuration time**-ban értékelődik, így egy
részleges vagy elgépelt `android/key.properties` a `GradleException`-nel a debug
buildet is megfogja. Ez a Flutter kanonikus mintájának velejárója és fail-fast
szempontból helyes; csak azért rögzítem, hogy ha valaki „hirtelen nem fordul a
debug build" hibát jelent, itt keresse.

## Gate-bizonyíték (függetlenül újrafuttatva ezen a boxon, `62adeef`-en)

| Gate | Eredmény |
|---|---|
| `dart format --output=none --set-exit-if-changed lib test tool` | `Formatted 448 files (0 changed)` |
| `flutter analyze lib/ test/ tool/` | `No issues found! (ran in 3.5s)` |
| `dart run tool/check_architecture.dart` | `OK (12 allowlisted deviation(s))` |
| `dart run tool/ci/check_assets.dart` | `OK (10 declared asset(s), 4 non-empty ML binary/binaries)` |
| `flutter test test/tooling` | `12/12` zöld |
| Route-guard valódi sértéssel | régi guard **zöld**, új guard **PIROS** ugyanarra a `router.go('/live')`-ra; visszaállítva |
| Asset-gate üres deklarációval | `exit 0` → **MINOR-1** |
| `git diff main...HEAD -- lib/` | üres |
| CI (teljes suite + property + coverage + APK, ÚJ gate-sorral) | [run 30513701633](https://github.com/wolfcasaba/strumsight/actions/runs/30513701633) **success**, 11m45s, `62adeef`-en |

### A CI-futás lépésenként (mind `success`)

`Format gate` → `Analyze gate` → `Architecture gate` → `Asset gate` →
`Test and coverage gate` → `Upload coverage report` →
`Property gate (randomized seed)` → `Read APK metadata from pubspec` →
`Build development APK` → `Stage versioned APK` → `Upload development APK`.

Mind a **négy új gate** (format, `tool/`-ra kiterjesztett analyze, architecture,
asset) élesben, a merge-gate workflow-ban futott le zölden — a kör elfogadásának
brief §6 szerinti fő bizonyítéka.

### Artifactok (az elnevezési kritérium bizonyítéka)

```
strumsight-1.0.0-1-62adeef-development.apk   (33 426 237 bytes)
strumsight-coverage-30513701633              (26 535 bytes)
```

Az APK neve tartalmazza a verziót (`1.0.0`), a build numbert (`1`), a rövid SHA-t
(`62adeef` = a review-alap commit) és az envet (`development`) — a §6 kritérium
teljesítve, a statikus `strumsight-apk` név megszűnt.

## Verdikt

**APPROVED.** BLOCKER és MAJOR nincs. A kör a fő állítását teljesíti: a
merge-gate immár format/analyze(`tool/`)/architecture/asset/coverage gate-eket is
futtat, az artifactok visszavezethetők, és a production release fail-closed
signinggal, debug-fallback nélkül különül el. Az R11-review MINOR-1 bizonyítottan
lezárva (a régi guard ugyanarra a sértésre zöld maradt, az új piros).

A három MINOR nem blokkol, és mindhárom természetes helye a Kör 15/16:

1. **MINOR-1** — asset-gate üres deklarációs halmazon zöld → a Kör 15
   checksum-manifestje adjon alsó korlátot is.
2. **MINOR-2** — gate-duplikáció a két workflow között → composite action /
   `workflow_call`.
3. **MINOR-3** — CI-idő 9m → 11m → ha tovább nő, a coverage külön jobba.

A merge az ADR 0052 zöld-kapus szabálya szerint mehet.

**Merge utáni kötelezettség (NOTE-3):** a `release-apk.yml` secret nélküli
dispatchének kontrollált piros futása csak a default branchre kerülés után
szerezhető meg. A merge után azonnal elvégzem, és a linket ide írom.

### Merge utáni bizonyíték — `release-apk.yml` fail-closed

_(a merge utáni dispatch után kitöltve)_
