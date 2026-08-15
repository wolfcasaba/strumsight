# E99-R12 (GOV-30c-4) — Review

Brief: docs/rounds/e99-r12-gov-30c-4-document-assembly-and-insights.md
Diff: `git diff origin/main..codex/e99-r12-gov-30c-4-document-assembly-and-insights` (`8ece7327`..`b376dbe9`)
Reviewer: Claude (Sonnet 5) · Dátum: 2026-08-15
Verdikt: **APPROVED**

## Összegzés

BLOCKER: 0 · MAJOR: 0 · MINOR: 1 · NOTE: 2

Independens `/tmp` klónban (`/tmp/review-e99-r12`, GitHub origin-ról klónozva,
nem a hub lokális útvonaláról) újrafuttatott gate mind zöld; a scope-audit
saját kézzel is `OK` (7 megváltozott útvonal, 0 generated/ignored); az A3
„same instance" invariánst **saját, ideiglenes rontással** (a
`InsightsStage` kontextus-dokumentumát egy másik példányra cserélve)
függetlenül újramértem — a célzott teszt pontosan a várt módon, kizárólag az
A3/A4 esetben ment pirosra, a rontás visszaállítva, a fa tiszta.

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| A1 | Ép bemenetből a lánc végén VAN `AnalysisDocument` a munkaállapotban | ✅ | `full_pipeline_composition_test.dart`: `expect(value.document, isNotNull)` — zöld |
| A2 | Az előzetes dokumentum `insights`/`hotspots` mezője ÜRES, minden más végleges | ✅ | `document_stages_test.dart` „A2" — zöld, mezőnkénti `expect` |
| A3 | Az insight-szabályok a PUBLIKÁLANDÓ dokumentumot kapják kontextusként | ✅ | `document_stages_test.dart` „A3/A4": `expect(first.context!.document, same(assembled.document))` — zöld; **saját valódi-sértés próbával függetlenül is megerősítve** (lásd lent) |
| A4 | A végleges dokumentum `insights` és `hotspots` mezője rangsorolt | ✅ (ld. N1) | ugyanaz a teszt: `['second','first']` prioritás szerint, hotspot `['high','low']` severity szerint |
| A5 | A 20 stage MINDEGYIKE szerepel a fázis-térképen | ✅ | `analysis_stage_phases_test.dart` „A5": `hasLength(20)` + halmaz-egyezés — zöld |
| A6 | Degradált futásnál a hiányzó mező ÜRES marad, nem kitalált | ✅ | `document_stages_test.dart` „A6": üres pitch-frames → `metrics` üres, `monophonicPitch` capability `unavailable` — zöld |
| A7 | 20 stage elfogadható az élő pipeline-ban | ✅ | `full_pipeline_composition_test.dart` — `AnalysisPipeline(stages: buildFullAnalysisStages())` nem dob, zöld |
| A8 | A publikált fázisok nem csökkennek a bővült lánc mellett sem | ✅ | ugyanaz a teszt: `publishedPhases` a fázis-térkép szerinti, monoton (`AnalysisPipeline` konstruktor-őre, ld. pre-flight) |
| A9 | `analysisV2RunnerProvider` a kör után is `StateError`-t dob | ✅ | `git diff --stat origin/main..HEAD -- lib/features/audio_analysis/application` — üres |
| A10 | A `domain/**` érintetlen | ✅ | `git diff --stat origin/main..HEAD -- lib/features/audio_analysis/domain lib/core/flags` — üres |

## Scope-audit

Engedélyezett fájlokon kívüli változás: **nincs**.

```
$ python3 tools/scope-audit.py --repo /tmp/review-e99-r12 \
    --brief docs/rounds/e99-r12-gov-30c-4-document-assembly-and-insights.md \
    --base 8ece7327c84618063caf16c60ad74801031e6c4b
Legacy scope audit OK (8ece7327c846..b376dbe9b001, 7 changed path(s), 0 generated/ignored)
```

Pontosan a 7 `allowed_paths` fájl változott (`analysis_work_state.dart`,
`stages/document_stages.dart` [ÚJ], `stages/analysis_stage_phases.dart`,
3 teszt, a brief §10 handoff). Implementer saját jelzése (`scope_audit=ok`,
`scope_audit_changed=7`) egyezik a független méréssel.

## Valódi-sértés próba (A3, saját kézzel megismételve)

A brief §6.1 kötelezővé teszi: az insight-kontextus dokumentumát egy másik
(nem publikálandó) példányra cserélve az A3 cellának pirosnak kell lennie.
Az implementer a §10 handoffban ezt állította; **függetlenül
megismételtem**, nem fogadtam el bemondásra:

1. `/tmp/review-e99-r12/lib/features/audio_analysis/engine/stages/document_stages.dart`
   `InsightsStage.run`-jában az `AnalysisInsightContext(document: preliminary)`
   hívást ideiglenesen egy `_withInsightOutputs(preliminary, insights: [],
   hotspots: [])` új példányra cseréltem.
2. `flutter test test/features/audio_analysis/engine/stages/document_stages_test.dart`
   → az „A3/A4" teszt **pirosra váltott** (`Expected: same instance … Actual: …`),
   a másik három teszt (A2, A6, „minden degradálható elbukott") **zöld maradt**
   — a rontás pontosan a célzott invariánst találta el, semmi mást.
3. `git checkout -- …/document_stages.dart` — visszaállítva, `git status --porcelain`
   üres.

## Megállapítások

### N1 — NOTE — az insight-lista sorrendje csak azonos-kind esetre van tesztelve

- **Fájl:** `lib/features/audio_analysis/engine/stages/document_stages.dart:172-177`
- **Megfigyelés:** a végleges `insights` lista `[...visibleInsights,
  ...additionalInsights]` konkatenáció — a 4 „slot" (improvement/strength/
  nextAction/qualityWarning) mindig MEGELŐZI az `additionalInsights`
  prioritás-rendezett farkát, függetlenül attól, hogy egy adott slot-elem
  prioritása alacsonyabb-e egy additional-elemnél. A meglévő A3/A4 teszt csak
  AZONOS kind (mindkettő `improvement`) két szabályát használja, ahol ez a
  különbség nem látszik.
- **Hatás:** ma nulla production hívó, nem viselkedésváltozás — csak azt
  jelzem, hogy a „rangsorolt" (A4) állítás vegyes-kind esetre nincs
  falszifikálva. Nem sérti a brief egyetlen mérhető celláját sem (a §6.1
  mérce-mátrix nem ír elő szigorú globális prioritás-sorrendet).
- **Javasolt irány:** egy jövőbeli körben (amikor lesz élő hívó) egy vegyes
  kind/prioritás teszt-eset hozzáadása, ami megkülönbözteti a „slot-sorrend"
  és a „szigorú prioritás-sorrend" szemantikát.
- **Státusz:** OPEN (nem blokkol).

### N2 — NOTE — `_fingerprint` duplikálja a meglévő `AudioFingerprint.compute`-ot

- **Fájl:** `lib/features/audio_analysis/engine/stages/document_stages.dart:273-295`
- **Megfigyelés:** `lib/features/audio_analysis/data/cache/audio_fingerprint.dart`
  (E06-R28) már tartalmaz egy azonos célú, tesztelt, privacy-preserving
  SHA-256 PCM-fingerprint függvényt (`AudioFingerprint.compute(samples:
  sampleRate: channelCount: preprocessingVersion:)`). A `document_stages.dart`
  ÚJRA implementálja ugyanazt (colon-join header + SHA-256), más bájt-elrendezéssel.
  A `data/cache/**` NEM tiltott zóna ebben a briefben, tehát az újrafelhasználás
  nem ütközött volna a scope-pal.
- **Hatás:** két párhuzamos, egymástól függetlenül karbantartandó
  implementációja ugyanannak a privacy-kritikus kontraktusnak („sose PCM,
  csak hash") — ha az egyiket egy jövőbeli kör javítja/hangolja, a másik
  csendben lemarad. Ma nincs funkcionális eltérés (mindkettő SHA-256 fölött
  16 bites kvantált PCM-en). **A független security review ugyanezt a
  duplikációt önállóan is megtalálta** (NOTE-2,
  `e99-r12-security.md`) — a két
  review egymástól függetlenül konvergált ugyanarra a megfigyelésre, ami
  megerősíti, hogy valódi, follow-up-ra érdemes tétel, plusz egy precíz
  correctness-részletet is hozzátesz: a header-kódolás (string-join vs.
  bináris `ByteData(20)`) ÉS a minta-forrás (nyers vs. kanonikus PCM) is
  eltér, tehát a két fingerprint SOSEM fog egyezni, nem csak elméletileg
  térhet el.
- **Javasolt irány:** follow-up körben cserélni `AudioFingerprint.compute(...)`
  hívásra (`preprocessingVersion: input.preprocessedAudio?.preprocessingVersion
  ?? 'unavailable'`), ami ~15 sort törölne.
- **Státusz:** OPEN, MINOR-ra minősítve (nem blokkol, a diffet NEM hizlalná —
  follow-up, mert a review-fázisban új implementer-kört indítani egyetlen
  MINOR-ért nem arányos, ld. `docs/execution/09-review-report.md` súlyossági
  tábla: „javítható a körben, ha nem hizlalja a diffet; egyébként follow-up").

## Architektúra + termékhatárok

- Minden import feature-lokális (`../../domain/...`, `../analysis_context.dart`,
  `../insights/...`, `../metrics/timing_hotspots.dart`) vagy megosztott core
  (`core/foundation/**`) — nincs cross-feature import, nincs UI↔plugin.
  `tool/check_architecture.dart` zöld, **12 allowlisted deviation** — a
  `git diff origin/main..HEAD -- tool/` üres, tehát ez a szám a kör ELŐTTI
  baseline, a kör nem adott hozzá újat.
- Nyers PCM sosem hagyja el a stage-et: `_fingerprint` kizárólag egy SHA-256
  digestet ad vissza (ld. N2 — más a duplikáció, nem a szivárgás). Az
  `AnalysisInputSummary` doc-comment szerinti „never PCM" kontraktus tartva.
- Hiányzó nyersanyag `unavailable`/üres marad, nincs `?? 0`-stílusú metrika-
  fabrikáció (`_capabilityFor`, `_capabilities` — csak a `dspConfigHash`/
  `modelManifestIds` provenance-mezőknél van `??` fallback, ott a helyettesítő
  érték egy explicit „unavailable" string vagy üres lista, nem hihető hamis adat).

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény (implementer) | Ellenőrizve (saját, izolált `/tmp` klón) |
|---|---|---|
| format | zöld | ✅ zöld |
| analyze | zöld | ✅ zöld (`No issues found!`) |
| test full_pipeline_composition_test.dart | zöld | ✅ zöld |
| test document_stages_test.dart | zöld | ✅ zöld (4/4) |
| test analysis_stage_phases_test.dart | zöld | ✅ zöld (6/6, A5 a 20-stage-re) |
| architecture | zöld | ✅ zöld |
| secrets | (nem jelentve) | ✅ zöld (2524 fájl, 0 lelet) |
| l10n | (nem jelentve) | ✅ zöld (1276 üzenet, en↔hu) |
| CI (teljes suite + property + APK) | — | dispatch alatt, ld. round-status |

Biztonsági/adatvédelmi review (kötelező, `risk = "high"`): külön, izolált
klónban futtatott dedikált pass — lásd
`e99-r12-security.md` — **PASS**,
0 CRITICAL/BLOCKER/MAJOR/MINOR, 2 NOTE (előretekintő, egyik a fenti N2-vel
konvergál).

`full-gate.yml` az implementer-commit SHA-ján (`b376dbe9`, run
[31875103848](https://github.com/wolfcasaba/strumsight/actions/runs/31875103848))
**success**. A két review-commit hozzáadása után a gate-et a végleges SHA-n
újra kell dispatch-elni (ADR 0086 §2 exact-SHA szabály) — ez az orchesztrátor
következő lépése.

## Merge-döntés

ADR 0052 szerint: minden gate zöld ÉS nincs nyitott BLOCKER/MAJOR → merge.
Ez a review 0 BLOCKER/MAJOR-t talált, a security review is 0
CRITICAL/BLOCKER/MAJOR/MINOR-t (PASS). A merge a végleges SHA-n újra
dispatch-elt `full-gate.yml` + `router-ci.yml` zöld futására vár.
