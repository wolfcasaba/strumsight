# E06-R18 — Review

Brief: `docs/rounds/e06-r18-technique-proxy-experimental-module.md`  
Diff: `871ce472...09c20484`  
Reviewer: Codex / gpt-5.6-terra · Dátum: 2026-08-12  
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 1

Az isolated, GitHubról klónozott exact `8ecf6b34` gate zöld. A tartalmi
mutációs próba kezdetben megmutatta, hogy a claim-safety guard nem ellenőrzi
az analysis-eredetű ARB **kulcsokat**, csak az értékeket. Az F1 javítása ezt
egy shared helperrel és key-only regressziós teszttel lezárta; a friss,
GitHubról klónozott exact `ae11543c` review-gate is zöld. A kötelező security
review ezt követően új, Lab-kapu megkerülést talált (F2). A javítás a nyers
számítót priváttá tette, és egy új isolated exact `09c20484` review-gate,
valamint ismételt független security review is zöld.

## Acceptance criteria

| Kritérium | Állapot | Bizonyíték |
|---|---|---|
| Proxy-, Lab-, confidence- és küszöb-mátrix | ✅ | `technique_proxies_test.dart`, `transition_analysis_test.dart`; isolated gate zöld |
| Lab-only / document-purity / flag default OFF | ✅ | `technique_proxies.dart`, `technique_metric_catalog_test.dart` |
| Tiltott állítások gépi őre és valódi-sértés bizonyítása | ✅ | F1 key-only fake-map regressziós teszt zöld |
| Flag/Lab-only számítás minden public fogyasztónak | ✅ | F2 regressziós cellák + security re-review |
| ADR 0236 és öt PENDING eval sor | ✅ | ADR, eval-mátrix diff |

## Scope-audit

Az implementer gépi auditja: `scope_audit=ok`, base `871ce472`, 13 changed
allowed path. A review-jelentés a review-protokoll kötelező artefaktuma.

## Megállapítások

### F1 — MAJOR — a claim-safety guard nem fogja meg a tiltott ARB-kulcsot

- **Fájl:** `test/tooling/analysis_claim_safety_test.dart:58-63`
- **Probléma:** az őr csak `entry.value`-ra hívja a
  `forbiddenAnalysisClaimPattern`-t. A brief §5.2 és §6.1 testrészre utaló
  ARB-névet is tilt; egy későbbi `analysisTechniqueFingerPlacement` kulcs
  semleges fordítási értékkel ezért átcsúszik.
- **Mért reprodukció:** az isolated exact-SHA klón
  `lib/l10n/app_en.arb` fájljába ideiglenesen bekerült
  `"analysisTechniqueFingerPlacement": "A neutral label without a forbidden value"`.
  Ezután `flutter test test/tooling/analysis_claim_safety_test.dart` **zöld**
  lett (3 teszt), pedig a kulcs tiltott `finger` kifejezést tartalmaz.
- **Hatás:** a guard nem teljesíti azt a biztonsági szerződést, amely a
  kéz-/ujjdiagnózisra utaló ARB-nevek bejutását hivatott megakadályozni.
- **Kötelező javítás:** a guard minden releváns `entry.key`-t is ellenőrizzen
  mindkét ARB-ben, és a tesztben legyen dedikált, ideiglenes/fake-map mutáció,
  amelynek a `analysisTechniqueFingerPlacement` kulccsal pirosra kell váltania
  semleges érték mellett. A pattern szűkítése tilos.
- **Ellenőrzés:** előbb a kulcs-mutatáció legyen RED, majd
  `flutter test test/tooling/analysis_claim_safety_test.dart` és a teljes
  `tools/round-gate.sh test/features/audio_analysis test/tooling test/app`
  legyen zöld.
- **Státusz:** FIXED (`ae11543c`)

### F1 újraellenőrzése

`violatesClaimSafety(key, value)` már mindkét oldalt vizsgálja. A
`analysisTechniqueFingerPlacement` + semleges érték fake-map a javítás előtti
review-klónban zöld őrt produkált, az új tesztben pedig determinisztikusan
offence-et ad. A friss exact-SHA-n külön `flutter test
test/tooling/analysis_claim_safety_test.dart` (4 teszt) és a teljes review-gate
zöld.

### F2 — MAJOR — a public export megkerüli a Lab- és feature-flag kaput

- **Fájl:** `lib/features/audio_analysis/engine/metrics/technique_proxies.dart:177-196`, exportálva `lib/features/audio_analysis/public.dart:61`
- **Probléma:** a `computeTechniqueProxyMetrics` public top-level függvény
  `analysisTechniqueProxiesEnabled` és `labModeActive` bemenet nélkül ad
  `available` `technique.*` metricákat. A public contracton keresztül minden
  cross-feature fogyasztó meghívhatja, megkerülve a kizárólag
  `buildTechniqueProxyReport`-ban lévő kaput.
- **Bizonyíték:** a függvény közvetlenül elérhető a public exportból; a kör
  saját tesztje is közvetlenül hívja
  (`test/features/audio_analysis/engine/technique_proxies_test.dart:121-127`).
  Ma nincs production hívó, de ez nem zárja a public bypass-t.
- **Kötelező javítás:** a nyers számító legyen private implementation-detail,
  vagy a public felület minden útja kényszerítse ki a kétkapus
  `TechniqueProxyReport`-ot. A teszt seam ne tegye elérhetővé az ungated
  implementációt; legyen regressziós bizonyíték arra, hogy flag/Lab nélkül
  semmilyen public API nem ad ki available technique metricát.
- **Ellenőrzés:** célzott proxy teszt + teljes round-gate + ismételt security
  review.
- **Státusz:** FIXED (`09c20484`)

### F2 újraellenőrzése

A számító neve `_computeTechniqueProxyMetrics`; Dart library-private, ezért a
`public.dart` exporton át nem hívható. A public
`buildTechniqueProxyReport` maradt az egyetlen elérési pont, amely mindkét
feature/Lab kaput és a confidence feltételt ellenőrzi. Az isolated exact
`09c20484` klónban a proxy teszt a három tiltott flag/Lab cellát is méri, az
ismételt security review pedig PASS verdiktet adott (30 célzott teszt zöld).

## Gate-bizonyíték ellenőrzése

| Gate | Ellenőrzés |
|---|---|
| format / analyze | isolated exact `09c20484` gate: ✅ |
| audio-analysis / tooling / app tesztek | isolated exact `09c20484` gate: ✅ |
| architecture / secrets / l10n | isolated exact `09c20484` gate: ✅ |
| CI | a review-változat után exact-SHA dispatch elindult, de F2 miatt már nem merge-bizonyíték |

## Merge-döntés

Nincs nyitott BLOCKER vagy MAJOR. A teljes CI-t a review-artefaktumokat
tartalmazó végleges SHA-ra kell dispatch-elni; csak siker esetén merge-elhető.
