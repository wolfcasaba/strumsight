# E06-R21 — Review

Brief: `docs/rounds/e06-r21-analysis-repository-v2-and-migration.md`
Diff: `20a4a474..bb817775`
Reviewer: Codex / gpt-5.6-terra (isolated `/tmp/e06-r21-review` clone)
Dátum: 2026-08-12
Verdikt: APPROVED

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 1

## Scope-audit

`python3 tools/scope-audit.py --repo /tmp/e06-r21-review --brief
docs/rounds/e06-r21-analysis-repository-v2-and-migration.md --base
20a4a474b19bfc562a2490e7fd6029489b6717df` → OK, 15 módosított útvonal,
engedélyezett fájlon kívüli implementer-diff nincs.

## Megállapítások

### F1 — MAJOR — A nem támogatott schema typed failure helyett kivételt dob

- **Fájl:** `lib/features/audio_analysis/data/local/file_analysis_repository.dart:489`
- **Probléma:** `_commitDocument()` `_UnsupportedSchemaException` kivételt dob,
  de `save()` és `replace()` csak `FileSystemException`-t kapnak el.
  Egy `schemaVersion > analysisDocumentSchemaVersion` érvényesen
  létrehozható `AnalysisDocument`, ezért a publikus repository contract
  aszinkron kivétellel sérül a dokumentált
  `analysis.repository.unsupported_schema` eredmény helyett.
- **Hatás:** a hívó nem kap stabil `AppResult` hibát; migrációban ez csak a
  túl tág `on Object` miatt rejtve marad.
- **Kötelező javítás:** `save` és `replace` a schema-elutasítást explicit
  `AppResult.failure(StorageFailure(code: unsupportedSchema))` eredményre
  képezzék, és legyen reprodukáló teszt mindkét metódusra.
- **Státusz:** FIXED (`bb817775`), közvetlen save/replace regressziós teszttel.

### F2 — MAJOR — Rename elveszíti az újraépített index-bejegyzést

- **Fájl:** `lib/features/audio_analysis/data/local/file_analysis_repository.dart:419-438`
- **Probléma:** ha a dokumentum létezik, de az indexből hiányzik, a kód
  `_rebuildFromDisk()` után az új summaryt csak az `existing` lokális listához
  adja. A `next` listát továbbra is az eredeti, hiányos `summaries` listából
  építi, ezért `rename()` success-t ad, de az indexbe nem írja vissza a
  dokumentumot.
- **Hatás:** következő `list()` nem tartalmazza az átnevezett dokumentumot;
  sérül a brief CRUD és index-recovery contractja.
- **Kötelező javítás:** a `next` listát a rebuildelt indexből képezd, és adj
  tesztet a hiányzó index-entry → rename → list új címmel esetre.
- **Státusz:** FIXED (`bb817775`), index-törlés → rename → list regressziós
  teszttel.

### F3 — NOTE — Implementer gate alakja nem hiteles

Az implementer saját státusza `gate_shape=VIOLATION`, mert a záró gate-et
átirányított outputtal indította. Ez önmagában nem kódhiba, de a green-gate
bizonylat nem fogadható el; a reviewer-gate-et a javítás után csővezeték
nélkül újra kell futtatni.

## Gate-bizonyíték ellenőrzése

| Gate | Ellenőrzés |
|---|---|
| scope audit | ✅ izolált klónban zöld |
| format | ✅ reviewer-gate `[1]` zöld |
| analyze | ✅ reviewer-gate `[2]` zöld |
| célzott tesztek és architecture | ✅ implementer `round-gate.sh` 9/9 zöld; független gate a végső SHA-n fut |
| CI | még nem dispatch-elt |

## Merge-döntés

Az F1 és F2 javítása és tesztje a `bb817775` commitban ellenőrizve. Merge csak
a végső SHA-n zöld független gate és exact-SHA CI után engedett.
