# E06-R18 — Review

Brief: `docs/rounds/e06-r18-technique-proxy-experimental-module.md`  
Diff: `871ce472...ae11543c`  
Reviewer: Codex / gpt-5.6-terra · Dátum: 2026-08-12  
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 1

Az isolated, GitHubról klónozott exact `8ecf6b34` gate zöld. A tartalmi
mutációs próba kezdetben megmutatta, hogy a claim-safety guard nem ellenőrzi
az analysis-eredetű ARB **kulcsokat**, csak az értékeket. Az F1 javítása ezt
egy shared helperrel és key-only regressziós teszttel lezárta; a friss,
GitHubról klónozott exact `ae11543c` review-gate is zöld.

## Acceptance criteria

| Kritérium | Állapot | Bizonyíték |
|---|---|---|
| Proxy-, Lab-, confidence- és küszöb-mátrix | ✅ | `technique_proxies_test.dart`, `transition_analysis_test.dart`; isolated gate zöld |
| Lab-only / document-purity / flag default OFF | ✅ | `technique_proxies.dart`, `technique_metric_catalog_test.dart` |
| Tiltott állítások gépi őre és valódi-sértés bizonyítása | ✅ | F1 key-only fake-map regressziós teszt zöld |
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

## Gate-bizonyíték ellenőrzése

| Gate | Ellenőrzés |
|---|---|
| format / analyze | isolated exact-SHA gate: ✅ |
| audio-analysis / tooling / app tesztek | isolated exact-SHA gate: ✅ |
| architecture / secrets / l10n | isolated exact-SHA gate: ✅ |
| CI | a review-változat után exact-SHA dispatch szükséges |

## Merge-döntés

Nincs nyitott BLOCKER/MAJOR/MINOR. Az ADR 0052 szerinti merge-hez még a review
jelentést is tartalmazó final SHA exact CI- és Router CI-evidencia szükséges.
