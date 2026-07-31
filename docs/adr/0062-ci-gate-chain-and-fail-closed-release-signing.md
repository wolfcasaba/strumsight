# ADR 0062 — Teljes CI gate-sor és fail-closed release signing

- **Státusz:** elfogadva (2026-07-30, E01-R14)
- **Kontextus:** SDD Chapter 2, Kör 14; kör-brief
  `docs/rounds/e01-r14-flutter-ci-release-pipeline.md`
- **Kapcsolódó:** [ADR 0052](0052-ci-apk-automerge-session-per-round.md)
  (a `build-apk.yml` mint kör-gate, session/kör), [ADR 0053](0053-ci-full-test-suite.md)
  (a teljes suite CI-ben fut, nem a fejlesztői boxon),
  [ADR 0051](0051-strumsight-application-identifiers.md) (a `pubspec.yaml` az
  egyetlen verzió-forrás)

## Kontextus

A `build-apk.yml` az ADR 0052 óta a kör-gate: körönként a round-branchre
dispatcholva ez dönti el, hogy egy kör mergelhető-e. A gate-sor azonban lyukas
volt:

- **nincs format gate** — formázatlan kód zöld gate-en át bemehetett;
- **nincs architecture gate** — a `tool/check_architecture.dart` (R10) csak
  lokálisan és a teszt-suite-on keresztül futott, magában a CI-ben nem;
- a `flutter analyze lib/ test/` a **`tool/` könyvtárat kihagyta**, így a
  gate-eket megvalósító scriptek maguk analyzálatlanok voltak;
- **nincs asset-ellenőrzés** — egy hiányzó vagy 0 bájtos, pubspec-deklarált
  ML-bin csak futásidőben derült volna ki (a repóban van is 0 bájtos bináris:
  `ml/strum_direction.tflite`, igaz, nem bundle-asset);
- **nincs coverage-mérés** semmilyen formában;
- az artifact neve statikus `strumsight-apk` — két futás terméke
  megkülönböztethetetlen;
- a „release" APK a **debug keystore-ral** van aláírva
  (`android/app/build.gradle.kts`), és a repóban nincs release-keystore secret.

Vagyis a CI-ből hibás kód is kaphatott „kiadható" buildet, és a kiadott artifact
sem visszavezethető, sem valódi kiadásra alkalmas nem volt.

## Döntés

1. **Egy gate-workflow marad.** A `build-apk.yml` neve, triggerei és az
   „egy workflow tartalmazza az összes kör-gate-et" elve nem változik (ADR 0052);
   *(a trigger-részt 2026-07-31-én az [ADR 0086](0086-ci-dispatch-only-build-gate.md)
   felülírja: a workflow már csak `workflow_dispatch`-re fut. Az „egy
   gate-workflow" elv és a lépéssor változatlan.)*
   a kör kizárólag **bővíti** a lépéssort. Nem jön létre külön lint- vagy
   test-workflow, mert a kör-gate egyetlen zöld/piros jelzése az ADR 0052-es
   merge-szabály alapja.
2. **A gate-ek sorrendje olcsó → drága:** format → analyze (`lib/ test/ tool/`)
   → architecture → asset-check → test + coverage → property gate → APK-build.
   A tipikus hiba (formázás, lint) így percek alatt kiderül, nem a build után.
3. **Három, egymástól elkülönített build-típus:**
   | Típus | Workflow | Env | Signing |
   |---|---|---|---|
   | Development | `build-apk.yml` | development | debug keystore |
   | Lab | `lab-apk.yml` | lab (`--dart-define-from-file`) | debug keystore |
   | Production | `release-apk.yml` (csak `workflow_dispatch`) | production | valódi keystore, repo-secretből |
4. **Fail-closed production signing.** A `release-apk.yml` bármelyik
   signing-secret hiányában **kontrolláltan elhasal** az előfeltétel-lépésen.
   Debug-signingra visszaeső ág a production workflow-ban **nem létezik** — a
   secret hiánya hiba, nem fallback. Ezzel szemben a `build.gradle.kts` a
   `key.properties` hiányában megtartja a debug-signingot, hogy a **lokális**
   `flutter run/build --release` fejlesztői útja ne törjön; a különbség nem
   ellentmondás, hanem a felelősség helye: a production garanciát a workflow
   adja, nem a gradle-fájl.
5. **Asset-check Dart-scriptként** (`tool/ci/check_assets.dart`), nem bash-ben —
   a `check_architecture.dart` bevált mintája szerint: ugyanaz a logika hívható
   lokálisan CLI-ként és unit-tesztből. A bejárt útvonal-halmaz **kizárólag** a
   `pubspec.yaml` `flutter: assets:` és `fonts: … - asset:` bejegyzéseiből
   származik — nem a fájlrendszer söprése —, különben a tréning-fa nem-bundle
   binárisai (pl. a 0 bájtos `ml/strum_direction.tflite`) örökölt okból vinnék
   pirosra a gate-et.
6. **Az artifact neve a pubspec-ből származik** (verzió + build number), a rövid
   SHA-val és az env-vel kiegészítve. Kézzel beírt verzió a workflow-ban tilos
   (ADR 0051: egyetlen verzió-forrás).
7. **Coverage küszöb nélkül.** A `flutter test --coverage` lépés informatív: a
   report artifactként feltöltve, a baseline a kör-briefben rögzítve. Piros
   gate-et coverage-ből ez a kör **nem** csinál (SDD 14.8: előbb baseline, a
   küszöb külön döntés) — egy elhamarkodott küszöb teszt-írásra ösztönöz a
   viselkedés lefedése helyett.

## Következmények

- Formázatlan, lintelő, architektúra-szabályt sértő vagy hiányzó assetre
  hivatkozó kód **nem kaphat** zöld kör-gate-et, tehát az ADR 0052 szerint nem
  mergelhető.
- A `tool/` alatti gate-scriptek maguk is analyzálva és formázva vannak — a
  gate-infrastruktúra ugyanazon minőségi léc alatt van, mint a `lib/`.
- Minden artifact visszavezethető egy konkrét verzió+commit+env hármasra.
- Production release **csak** explicit dispatch-csal és valódi keystore-ral
  készülhet; keystore hiányában nem születik félrevezetően „release"-nek
  nevezett, debug-aláírású APK.
- **Nyitott follow-up:** a valódi release keystore generálása és a
  repo-secretek feltöltése user-döntés; addig a `release-apk.yml` a
  fail-closed ágon áll meg. Ez nem blokkolja a kört — az elfogadás bizonyítéka
  éppen a kontrollált elhasalás.
- A CI-idő a coverage-lépés miatt nő; ha a növekmény érdemben zavaró, a
  coverage külön job-ba emelése későbbi, önálló döntés.

## Alternatívák

- **Külön lint/test/build workflow-k** — elutasítva: az ADR 0052 merge-szabálya
  egyetlen kör-gate zöld futására épül; több workflow több, kézzel korrelálandó
  jelzést adna.
- **Bash-alapú asset-check a workflow YAML-ben** — elutasítva: lokálisan nem
  futtatható és nem tesztelhető, a hibás gate pedig csak CI-ben derülne ki.
- **Coverage-küszöb bevezetése már ebben a körben** — elutasítva: mért baseline
  nélkül a küszöb önkényes, és a szám hajszolása rossz teszteket termel.
- **Debug-signing fallback a `release-apk.yml`-ben, ha nincs secret** —
  elutasítva: pontosan ez a mai állapot csapdája; egy „release" nevű, debug
  kulcsú artifact rosszabb, mint a hiányzó artifact.
- **A release signing kikényszerítése a `build.gradle.kts`-ben** (keystore
  hiányában a build hibája) — elutasítva: eltörné a fejlesztői
  `flutter build apk --release` útját a boxon; a production garancia helye a
  workflow.
