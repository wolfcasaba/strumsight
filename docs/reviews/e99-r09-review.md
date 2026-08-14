# E99-R09 — Review

Brief: `docs/rounds/e99-r09-gov-30c-1-ingest-pipeline-composition.md`  
Diff: `a6ea5361...8af6f34b`  
Reviewer: Codex/Terra · Dátum: 2026-08-14  
Verdikt: APPROVED

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 0 · NOTE: 0

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | immutable work state | ✅ | `analysis_work_state_test.dart` + izolált gate |
| A2 | egynemű typed adapterek | ✅ | `ingest_stages.dart`, fordítás |
| A3 | meglévő preprocessing stage delegálása | ✅ | `ingest_stages_test.dart` A3 injektált stage-csere |
| A4 | PCM→timeline-alap teljes lánc | ✅ | F1 javítása: PCM-only, hétstage-es kompozíciós teszt |
| A5/A6 | degradálás/fatális szétválasztás | ✅ | mutációs próba és composition tesztek |
| A7/A8 | provider érintetlen, nincs adapter-DSP | ✅ | scope audit + diff |

## Scope-audit

`python3 tools/scope-audit.py --repo /tmp/review-e99-r09 --brief ... --base a6ea5361...` → OK, 6 engedélyezett útvonal, 0 scope-sértés.

## Megállapítások

### F1 — MAJOR — A teljes ingest lánc külső, előre elkészített V1 evidenciát követel

- **Fájl:** `lib/features/audio_analysis/engine/analysis_work_state.dart:55-60`, `lib/features/audio_analysis/engine/stages/ingest_stages.dart:205-225,255-275,300-322`, `test/features/audio_analysis/engine/ingest_pipeline_composition_test.dart:25-49`
- **Probléma:** A work state opcionális `legacyEvidence` bemenetet vár, amelyet egyik ingest stage sem állít elő. A harmony, rhythm és events stage csak ezt a kívülről beadott értéket fogyasztja; A4 ezért kézzel gyártott `LegacyEvidence`-szel tesztel, nem a validált PCM-ből induló valódi lánccal.
- **Hatás:** `AnalysisWorkState.seed(input: pcm)` önmagában degradált harmony/rhythm után az events stage-nél fatálisan leáll, így nem teljesíti a brief célját és A4 PCM→timeline contractját.
- **Kötelező javítás:** A brief §0.0 revíziója szerint az engedélyezett `ingest_stages.dart` fájlban adj hozzá vékony, a meglévő `ClipAnalyzerStage`-et hívó `legacy-evidence` adaptert. A `LegacyEvidence` a preprocessed audio-ból keletkezzen, legyen fatális classifier-ág, és az A4 kizárólag PCM inputból bizonyítsa a hétstage-es láncot. A manuális `legacyEvidence` seed-bemenetet távolítsd el.
- **Ellenőrzés:** `ingest_pipeline_composition_test.dart` A4 a hét stage ID/provenance és nem üres event/chord/rhythm artefaktumok mellett teljesüljön kész evidence nélkül; a legacy-evidence hibacella sikertelen, részérték nélküli futást bizonyítson.
- **Státusz:** FIXED (`8af6f34b`) — `LegacyEvidenceIngestStage` a meglévő `ClipAnalyzerStage`-et hívja a preprocessed audioból; `AnalysisWorkState.seed` nem fogad már külső evidence-et. A friss izolált `/tmp/review-e99-r09-fix1` gate A4 cellája kizárólag PCM inputtal zöld, a hét futott stage provenance-listáját is assertálja. A külön fatális legacy-evidence cella bizonyítja, hogy sikertelenségkor nincs részérték.

## Gate-bizonyíték

Az izolált `/tmp/review-e99-r09-fix1` klónban a kötelező `tools/round-gate.sh` a javított headen végig zöld volt. Valódi-sértés próba: a preprocessing classifier ideiglenes `degradable` mutációja az A6 tesztet pirosra vitte (`Expected: ['preprocessing']`, actual a teljes további lánc); visszaállítva maradt. A high-risk security re-review a `8af6f34b` headen APPROVED, 0 lelettel zárult (`docs/reviews/e99-r09-security.md`).

## Merge-döntés

Az F1 javítása független gate- és tartalmi review-val zárt. A mergehez még a végső commit exact-SHA Full Gate és Router CI bizonyítéka szükséges.
