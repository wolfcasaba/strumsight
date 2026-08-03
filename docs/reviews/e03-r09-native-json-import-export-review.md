# E03-R09 — Natív StrumSight JSON import és export: review

- **Reviewer:** Codex/Terra, izolált `/tmp/review-e03-r09` klón
- **Reviewolt commit:** `1cec25d1118c5c3bbf0884cf6356849f7487f565`
- **Verdikt:** **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 0.

Az adapter a külső exchange envelope-ot a belső persistence codec-től
elkülönítve tartja. A forrásstream limitje deklarált és tényleges hosszon is
érvényesül, cancellation után nincs persistent write út, és a manifest a
document assets értékazonos tükre marad. A diff a kör pre-flightban engedett
útvonalain belül van; ADR 0118 a korábbi, kör-owned pre-flight commit része.

## Acceptance evidence

| Kritérium | Bizonyíték |
|---|---|
| Teljes V2 round-trip és asset manifest | importer/exporter fixture tesztek; canonical document equality |
| Root/version/corrupt/limit/cancel policy | importer-mátrix: 12 zöld teszt |
| Safe filename, determinisztikus és privacy-scrubbed export | exporter-mátrix: 4 zöld teszt |
| Repository-write tiltás | `NativeJsonImporter` csak in-memory `SongImportResult`-ot ad; nincs repository import vagy hívás |

## Gate és scope audit

Az izolált klón első gate-je a gitignore-olt Flutter localization output hiánya
miatt 625 analyzer hibával állt meg. Ez a dokumentált E03-R09/H6 klón-prereq
(L72), nem a diff regressziója. `flutter pub get` és `flutter gen-l10n` után
az előírt gate teljesen zöld volt:

```text
format: green
analyze: green
native_json_importer_test.dart: 12 passed
native_json_exporter_test.dart: 4 passed
architecture: green
```

`git diff --check origin/main...HEAD` tiszta. A `origin/main...1cec25d` diff
az ADR 0118 pre-flightot, a briefet és kizárólag a §4-ben felsorolt importer,
codec, teszt és fixture fájlokat tartalmazza.

## Adversariális próba

A reviewer az izolált klónban ideiglenesen eltávolította az
`assetManifest`/`document.assets` deep-equality őrt
(`native_json_importer.dart`). A célzott importer teszt azonnal piros lett:
`rejects a mismatched asset manifest before returning a document` várt
`songImport.native.assetManifestMismatch` failure helyett success-t kapott.
A próba után az eredeti őrt visszaállítottam; az izolált worktree production
diffje tiszta.

## Merge feltétel

A review nem helyettesíti az ADR 0052 zöld kapuját. Merge csak a végleges
branch-HEAD-hez kötött, zöld teljes CI-suite, randomizált property gate és APK
run után engedett.
