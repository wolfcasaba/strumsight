# E06-R03 — Review

Brief: `docs/rounds/e06-r03-codec-schema-and-legacy-adapter.md` (§0.0 pre-flight
revízió + [ADR 0221](../adr/0221-legacy-analysis-v2-migration-mapping.md) —
olvasd el mindkettőt a §5/§6 elé, mert az eredeti, 2026-08-07-i brief-szöveg
több acceptance-cellája elavult a tényleges E06-R02 domainhez képest, és a
lentiek MÁR a revideált verzió szerint ítélnek).
Diff: `git diff 172d2621...5ad89073` (12 kódfájl, `main` ág `172d2621`-től)
Reviewer: Claude Sonnet 5 (orchesztrátor — ugyanaz a session, amely a
pre-flightot írta; a független szemet egy dedikált `security-reviewer`
subagent és egy `flutter-devil-advocate` subagent adja, lásd lent)
Dátum: 2026-08-11
Verdikt: **CHANGES REQUESTED — javító kör szükséges (1 MAJOR + 1 MINOR)**

## Összegzés

BLOCKER: 0 · MAJOR: 1 (F0, javító körben) · MINOR: 2 (F1 follow-up R21-re,
F1b javító körben) · NOTE: 4 (F2, F3 + a security review 2 NOTE-ja, ld. lent)

### F0 — MAJOR — `LegacyAnalyzeAdapter` uncaught `ArgumentError`-t dob VALÓS, mentett V1 sessionökön (a „veszteségmentes" / „minden mentett session" ígéret sérül)

**Ezt a leletet a `flutter-devil-advocate` független subagent találta**, és
saját, futtatott próbákkal igazolta — a fő review (ez a jelentés) ELSŐ
körben nem találta meg, mert a pre-flight ADR 0221 csak az EGYIK irányban
mérte a V1↔V2 eltérést (V2 mér olyat, amit V1 nem — fabrikáció-kockázat), és
kihagyta a fordítottját: **a V1 decode-kontraktja LAZÁBB, mint a V2
konstruktor-invariánsai**, tehát léteznek V1-ben teljesen érvényes,
elmentett rekordok, amelyeken a V2 domain-konstruktor eldob.

- **Fájl:** `lib/features/audio_analysis/data/legacy_analyze_adapter.dart:106`
  (`TempoPoint(time: Duration.zero, bpm: session.result.bpm)` — a
  `TempoPoint` konstruktor `analysis_timeline.dart:6` `bpm <= 0` esetén
  `ArgumentError`-t dob)
- **Konkrét, VALÓS, reprodukálható lánc (a review saját, független
  megerősítésével):**
  1. `lib/features/analyze/engine/clip_analyzer.dart:229-240` —
     `_bpmFromStrums` **pontosan `0`-t ad vissza**, ha `strums.length < 2`,
     VAGY ha minden egymást követő strumpár 50 ms-on belülre esik
     (`intervals.isEmpty`). Ez NEM ritka szélsőérték — bármely rövid, kevés
     pengetésű (de akkorddal rendelkező) klip ide esik.
  2. `lib/features/analyze/screens/analyze_screen.dart:291` —
     `hasContent = result.chords.isNotEmpty || result.strums.isNotEmpty`;
     a session **menthető, ha VAN akkord VAGY VAN strum** — a `bpm > 0` NEM
     feltétele a mentésnek. Tehát egy „csak akkordok, alig pengetés" klip
     ma is simán elmenthető `bpm: 0`-val a Libraryba.
  3. Ez pontosan az az eset, amit a brief §1 („hogy a Library **minden**
     meglévő mentett sessionje V2-ként is olvasható legyen") és a §6
     „Veszteségmentesség" cellája garantálni ígér — és amit ez a diff MA
     megsértene: az ilyen session migrációja **crash-el**.
- **Hatás:** ma NULLA production hívó (a devil's-advocate és a review is
  megerősítette: nincs wiring), DE ez nem egy jövőbeli-hívó-függő kockázat,
  mint F1/F1b — ez a kör SAJÁT §1/§6 ígéretének MEGSÉRTÉSE a kör SAJÁT
  scope-ján belül, mihelyt bármi ezt az adaptert éles adaton hívja (R21).
- **Rokon, ALACSONYABB sürgősségű, de UGYANEBBŐL A GYÖKÉROKBÓL fakadó rések**
  (a devil's-advocate is felsorolta; a review saját ellenőrzése szerint EGYIK
  SEM reprodukálható a MAI valós DSP-pipeline-ból, csak V1 laza
  decode-kontraktusából — tehát elméleti/védekező jellegűek, de a bpm-fixszel
  egy mechanizmusban olcsón zárhatók):
  - `ChordSegment` eldob `start > end` esetén (`analysis_segment.dart:11`);
    a review megmérte: a mai `clip_analyzer.dart:199-224` chord-építő ciklusa
    monoton növekvő `centers[i]`-vel dolgozik, tehát `start <= end`
    STRUKTURÁLISAN garantált a valós pipeline-ból — ez a rés csak
    kézzel-szerkesztett/korrupt JSON-ból érhető el.
  - `StrumEvent` eldob `confidence ∉ [0,1]` esetén (`analysis_event.dart:11`);
    a review megmérte: `TimelineStrum.fromJson` `requireDouble(j, 'conf')`-ot
    használ **explicit min/max nélkül**, ami a `json_validation.dart:90-95`
    default-ja szerint `min: 0, max: double.maxFinite` — tehát a FELSŐ korlát
    (`<= 1`) sosem volt kikényszerítve decode-on. A forrás `Strum`
    (`core/music/strum.dart:15`) `assert(confidence >= 0 && confidence <= 1)`-t
    ír elő, de a Dart `assert` **release buildben nem fut** — tehát egy
    lebegőpontos kerekítési szélsőérték (pl. softmax-kimenet 1.0000000002)
    elméletileg átcsúszhatna éles buildben is.
- **Kötelező javítás (javító kör, ugyanaz a motor — Terra):**
  1. **`bpm <= 0`** → NE hozzon létre `TempoPoint`-ot, a `tempoPoints` maradjon
     üres lista. Ez NEM adatvesztés: a `LegacyViewAdapter` már ma is kezeli
     az üres `tempoPoints`-ot (`bpm = 0` fallback), tehát a kör-trip
     (`bpm: 0 → tempoPoints: [] → bpm: 0`) bitre helyreáll — ÉS ez az
     ŐSZINTÉBB reprezentáció (V1 maga is „nem tudtuk kiszámolni" jelentéssel
     használja a 0-t, nem egy valódi tempóértékkel).
  2. **Chord-szegmens és strum-esemény építése legyen ellenálló** a V2
     konstruktor által elutasított, de V1-ből (elvileg, laza kontraktus
     miatt) érkező szélsőértékekre — a `JsonCollectionStore` már bevált
     mintáját követve (**egy hibás bejegyzést kihagy, a többit megtartja**,
     `analyzed_session.dart:46-54`), NE az egész dokumentum migrációját
     buktassa el egyetlen hibás chord/strum. Javasolt irány (nem kötelező
     pontos forma): a confidence-t `[0,1]`-re szorítsd (`clamp`) — ez
     definíció szerinti korrekció, nem kitalált adat —, egy chord/strum
     konstrukciós hibát pedig fogj el és hagyj ki, a kihagyott darabszámot
     egyetlen összesítő `AnalysisWarning`-ban jelezd.
  3. **NE tedd fallible-lé az `adapt` metódust** (ne `AppResult`-ot adjon
     vissza) — a fenti „szorítás/kihagyás + warning" minta mellett az
     adapter továbbra is mindig sikeresen visszaad egy dokumentumot, csak
     nem feltétlenül veszteségmentesen a SZÉLSŐ esetekre (amit a warning
     jelez).
  4. Új teszt: egy fixture/session, ahol `bpm == 0` (a valós
     `_bpmFromStrums` &lt;2-strums esetét szimulálva) — bizonyítsa, hogy NEM
     dob, és a `LegacyViewAdapter` kör-trip `bpm: 0`-t ad vissza.
- **Ellenőrzés:** a fenti új teszt + a meglévő teljes suite újra zöld.
- **Státusz:** OPEN — **javító körben KÖTELEZŐEN javítandó, ez blokkolja a
  merge-et** (MAJOR, ADR 0052/09-review-report.md szerint).

## Acceptance criteria

| # | Kritérium | Teljesült | Bizonyíték |
|---|---|---|---|
| 1 | Round-trip minden mezőre, üres lista/null/1 µs is | ✅ | `analysis_document_codec_test.dart:10-24`, saját futtatás zöld (`/tmp/review-e06-r03`) |
| 2 | Bájtazonos encode | ✅ | ugyanott `expect(first, second)`; kódszinten `Map`-literál rögzített kulcssorrenddel (`analysis_document_codec.dart:39-55` stb.), nincs dinamikus `Map`-mutáció encode előtt |
| 3 | `schemaVersion` mátrix (0/1/2/hiányzó/nem-szám) | ✅ | `analysis_document_codec_test.dart:26-44` — 0/2/hiányzó/`'1'` (string) mind Failure; `1` a round-trip tesztben Success. **Valódi-sértés próba elvégezve** (lásd lent), a guard PIROSRA vált kikommentelve. |
| 4 | Ismeretlen kötelező enum → Failure; ismeretlen extra mező → Success | ✅ | `analysis_document_codec_test.dart:46-59` (`completion.status='future'`), `:42-43` (`futureField`) |
| 5 | NaN/Infinity mátrix (confidence + value, 6 cella) | ✅ | `analysis_document_codec_test.dart:60-97` — capability `confidence` és metric `value` mindkettő NaN/Infinity/-Infinity-re Failure; property-teszt `_expectFiniteJson` minden kimenetre |
| 6 | Legacy fixture mátrix (a/b/c) | ✅ | három fixture, mindegyik saját teszt-iterációval (`legacy_analyze_adapter_test.dart:12-104`); (b) `beatsPerBar` fallback külön tesztelve (`:106-114`); (c) `diagnostics` az adapter-lokális típusban, `document.metrics` üres (`:99-102`) |
| 7 | Veszteségmentesség (chord/strum darabszám+idő, title/customTitle/id/createdAt) | ✅ | `legacy_analyze_adapter_test.dart:36-44` (darabszám+bpm), `:70-97` (idő+cím), `:22-25` (id/createdAt/title/customTitle) |
| 8 | Nincs kitalált mérés (`metrics` üres, 3 capability `available`, 11 `unavailable`/`modelUnavailable`) | ✅ | `legacy_analyze_adapter_test.dart:46-68`; kódszinten `legacy_analyze_adapter.dart:127-145` |
| 9 | Oda-vissza az UI felé | ✅ | `legacy_analyze_adapter_test.dart:70-97`, `legacy_view_adapter.dart` teljes fájl |
| 10 | `SignalQualityReport.measured` | ✅ | migrált: `legacy_analyze_adapter_test.dart:27`; natív default `true`: `signal_quality_report_test.dart` + `analysis_document_codec_test.dart:22` |
| 11 | V1 érintetlen | ✅ | `git diff --stat 172d2621..5ad89073 -- lib/features/analyze lib/features/library` → üres |

## Scope-audit

Engedélyezett fájlokon kívüli változás: **nincs.**

Kétszer, két különböző módszerrel függetlenül mérve:
1. `git diff --name-status 59aa9424..a103724e` (a pre-flight commit → Terra
   végső commitja) — 12 fájl, mindegyik szó szerint a brief §4 listáján.
2. `python3 tools/scope-audit.py --repo /tmp/review-e06-r03 --brief
   docs/rounds/e06-r03-codec-schema-and-legacy-adapter.md --base
   172d26212b2eea08a3e5e2e065e6a2ea87ebe5ce` (origin/main-től mérve, a
   pre-flight ADR+brief-revíziót is beleértve) → `Legacy scope audit OK
   (172d26212b2e..5ad89073844a, 14 changed path(s), 0 generated/ignored)` —
   14 = a 12 kódfájl + a 2 doc fájl (ADR 0221, brief-revízió), pontosan a
   teljes engedélyezett lista.

A `signal_quality_report.dart` (az egyetlen érintett, MÁR MERGE-ELT R02
domain-fájl) diffje kizárólag additív: `git diff 172d2621..5ad89073 --
lib/features/audio_analysis/domain/signal_quality_report.dart` → 4 beszúrt
sor (egy opcionális `measured` paraméter + doc-comment), nulla törlés, nulla
meglévő sor módosítva.

## Valódi-sértés próba (brief §6.1, kötelező cella)

`/tmp/review-e06-r03`-ban (izolált klón, nem a megosztott munkafa) a
`_documentFromJson` `schemaVersion`-ellenőrzését ideiglenesen kikapcsoltam
(`if (false && _int(json, 'schemaVersion') != schemaVersion)`), majd
lefuttattam `flutter test test/features/audio_analysis/data/analysis_document_codec_test.dart`-ot:

```
00:00 +1 -1: accepts only schema version one and ignores future extra fields [E]
  Expected: <Instance of 'Failure<AnalysisDocument>'>
    Actual: Success<AnalysisDocument>:<Success<AnalysisDocument>(Instance of 'AnalysisDocument')>
```

A várt cella PIROSRA vált. Ezután a mutációt visszaállítottam
(`git diff --stat` → üres), és a teszt újra zöld. A klón egyébként is
eldobható; a mutáció nem került a megosztott munkafába vagy a branch-re.

## Fixture-hűség próba (eldobható, törölve)

A brief §8.1 szerint a három legacy fixture-nek a MAI `toJson()` kimenetének
kell lennie, nem kézzel kitaláltnak. Írtam egy eldobható tesztet
(`_scratch_fixture_fidelity_test.dart`, törölve a próba után), amely mindhárom
fixture-t `AnalyzedSession.fromJson` → `.toJson()` kör-úton futtatta, és a
kimenetet a nyers fixture-tartalommal vetette össze:

- `legacy_session_v1.json` — bájtra (dekódolt-JSON-ra) egyezik ✅
- `legacy_session_lab_diag.json` — egyezik ✅
- `legacy_session_pre_bpb.json` — **eltér**: a kör-úton `'bpb': 4` MEGJELENIK,
  a nyers fixture-ben nincs `bpb` kulcs. **Ez NEM hiba** — ez a fixture
  SZÁNDÉKOSAN egy `round 118` ELŐTTI rekordot szimulál (amikor a `bpb` mező
  még nem létezett); a mai `AnalyzeResult.toJson()` MINDIG kiírja a `bpb`-t
  (`optionalInt` csak a `fromJson`-on ad defaultot), tehát egy friss encode
  természetesen hozzáadja — pontosan ez a fixture CÉLJA (a hiányzó mezőt a
  betöltési oldalon kell kezelni, amit a `beatsPerBar` fallback-teszt külön
  bizonyít). A másik két fixture bájtra-egyező eredménye igazolja, hogy nem
  elírásról van szó.

## Megállapítások

### F1 — MINOR — `AnalysisDocumentCodec.decode` nem korlátozza a listák/mapek méretét

- **Fájl:** `lib/features/audio_analysis/data/analysis_document_codec.dart:602-606`
  (`_list`), `:661-672` (`_stringMap`/`_boolMap`)
- **Probléma:** a V1 kódban (`analyze_result.dart`) minden lista `requireList(maxLength:)`-szel
  védett (`maxTimelineChords = 5000`, `maxTimelineStrums = 20000`) egy sérült/
  kézzel szerkesztett rekord elleni védelemként. A V2 codec `_list`/`_stringMap`/
  `_boolMap` helperei NEM kapnak hasonló felső korlátot — egy nagyon nagy
  `events`/`chordSegments`/`metrics`/`hotspots` tömb elfogyaszthatja a
  memóriát dekódoláskor.
- **Hatás:** ma NULLA — ehhez a codechoz még nincs hívó (nincs repository/
  perzisztencia-bekötés, R21 dolga), tehát nincs olyan út, ahol tényleges
  fájlból/hálózatból jönne be korlátlan méretű JSON. Amint R21 fájlból
  betöltő hívót ad ehhez, a kockázat valóssá válik (sérült/hibás lokális
  fájl → OOM dekódoláskor, ugyanaz a hibaosztály, amit a V1 `maxLength`
  védelme kifejezetten kizár).
- **Független megerősítés:** a dedikált `security-reviewer` subagent
  UGYANEZT a lelet önállóan, TŐLEM FÜGGETLENÜL, egy tiszta pure-Dart
  reprodukciós próbával mérte meg: `events` tömb `N=10000` → Success 61ms,
  `N=100000` → Success 278ms, `N=500000` → Success 1331ms (mind sikeresen
  dekódolva, lineáris skálázódással) — a V1 5000/20000-es korlátjához képest
  100×-500×-es túllépés is átment. „MUST-fix before R21" minősítéssel.
- **Kötelező javítás:** NEM ebben a körben — a brief nem írt elő ilyen
  acceptance-cellát, és a `lib/features/audio_analysis/data/**` fájlok már
  lezártak erre a körre; a helyes korlát-érték minden mezőre (events,
  chordSegments, beats, bars, tempoPoints, pitchSegments, dynamicPoints,
  capabilities, metrics, hotspots, insights, warnings, evidence, factIds,
  metricIds, evidenceIds, distribution/timeSeries pontok) külön megfontolást
  igényel — ez inkább R21 (repository) saját, dedikált briefjébe való, amikor
  a tényleges fájlból-betöltés valós adatméretei ismertek lesznek. Follow-up:
  R21 brief vegye fel a `_list`/`_stringMap`/`_boolMap` felső korlátozását, a
  V1 `maxTimelineChords`/`maxTimelineStrums` mintájára.
- **Ellenőrzés:** egy jövőbeli property-teszt egy túlméretezett tömbbel.
- **Státusz:** OPEN (follow-up R21-re, nem blokkoló — mindkét független
  review ugyanerre a döntésre jutott)

### F1b — MINOR — decode/encode aszimmetria: `_ensureFiniteJson` csak encode-on fut, a `CapabilityReport.details` nyitott bag-en NEM

- **Fájl:** `lib/features/audio_analysis/data/analysis_document_codec.dart:23`
  (`_ensureFiniteJson` csak `encode`-ban hívva), `:673-674` (`_details` → puszta
  `_object`, nincs rekurzív véges-szám ellenőrzés)
- **Probléma (a security-reviewer subagent mérte, valódi reprodukcióval):** egy
  sérült/kézzel szerkesztett persistált dokumentum `"details":{"x":1e999}`
  tartalmat hordoz egy `capabilities[].details` mezőben. A `jsonDecode` a
  `1e999`-et `Infinity`-vé alakítja; a `_details` helper ezt VÁLTOZATLANUL
  átveszi (nincs finiteness-ellenőrzés az útban) → **`decode` `Success`-t ad**,
  a dekódolt `AnalysisDocument`-ben egy `Infinity` érték él a `details`
  bag-ben — ez megsérti a „kimenetbe soha nem jut nem véges szám" invariánst
  a DEKÓDOLÁS oldalán (a kódolás oldalán ezt kifejezetten `_ensureFiniteJson`
  védi). Egy KÉSŐBBI újra-kódolás (`encode(decodedDoc)`) ezután **elkapatlan
  `ArgumentError`-ral eldob** — a decode fail-closed, az encode nem, tehát az
  aszimmetria egy crash-útvonalat nyit a persist-újraírás pillanatában.
- **Hatás:** ma NULLA (nincs hívó, ugyanaz az „unwired" indoklás, mint F1-nél),
  de ez nem egy HIÁNYZÓ jövőbeli védelem, hanem egy MEGLÉVŐ, a kör SAJÁT
  kódjában lévő aszimmetria két, ugyanabban a fájlban élő függvény között.
- **Kötelező javítás:** `_documentFromJson`-ban, a gyökér `_object(root)`
  sikere UTÁN, MÉG a domain-objektumok építése ELŐTT hívd meg
  `_ensureFiniteJson(json)`-t (vagy ekvivalens rekurzív véges-szám
  ellenőrzést) a teljes dekódolt JSON-fán — ez szimmetrikussá teszi a
  decode/encode véges-szám-védelmet egyetlen, kis, célzott diffel, nem
  igényel új mezőt vagy tervezési döntést.
- **Ellenőrzés:** egy teszt, amely `details`-be `1e999`/`NaN`-reprezentáló
  JSON-t tesz és `decode`-ot `Failure`-t vár.
- **Státusz:** OPEN — **javító körben javítandó** (kicsi, célzott diff, nem
  hizlalja érdemben a kört; ld. a review-jelentés Merge-döntés szakaszát)

### F2 — NOTE — `AnalysisCompletionStatus.complete` migrált dokumentumon, nem `degraded`

- **Fájl:** `lib/features/audio_analysis/data/legacy_analyze_adapter.dart:113-115`
- **Megfigyelés:** a migrált dokumentum `completion.status = complete`,
  jóllehet 11/14 capability `unavailable`. Az ADR 0221 nem írt elő konkrét
  értéket erre a mezőre (szándékosan nyitva hagyva implementer-döntésként),
  és a `complete` védhető olvasat (a V1-futás ténylegesen lefutott, nem
  szakadt meg) — az SDD §9.2 mindkét értéket „menthetőnek" (`complete` VAGY
  `degraded`) minősíti. Nem hiba, csak egy jövőbeli UI-kör (amely a
  `completion.status`-ra épít egy „teljesség" jelzést) döntse el tudatosan,
  melyiket várja migrált dokumentumon.
- **Státusz:** NOTE, nem blokkoló.

### F3 — NOTE — `analysis.migration.legacy_v1` `messageKey` egyelőre nincs ARB-bejegyzésben

- **Fájl:** `lib/features/audio_analysis/data/legacy_analyze_adapter.dart:27`
- **Megfigyelés:** a `messageKey`/`messageArgs` minta (ADR 0219, `AnalysisInsight`
  precedens) szándékosan NEM kész mondatot hordoz — a lokalizáció a UI-rétegé,
  ami ebben a körben még nem létezik. A `l10n` gate-lépés (`check_l10n_parity.dart`)
  ezért jogosan zöld (nincs hívó, ami ezt a kulcsot renderelné). Amikor az
  első UI-kör ezt a warningot megjeleníti, akkor kell az ARB-bejegyzés — nem
  most.
- **Státusz:** NOTE, nem blokkoló.

## Gate-bizonyíték ellenőrzése

| Gate | Állított eredmény (implementer) | Ellenőrizve (reviewer, izolált `/tmp/review-e06-r03` klón) |
|---|---|---|
| format | zöld | ✅ zöld |
| analyze | zöld | ✅ zöld |
| test test/features/audio_analysis | zöld | ✅ zöld |
| test test/property | zöld | ✅ zöld |
| test test/features/analyze | zöld | ✅ zöld (V1 regresszió-bizonyíték) |
| test test/features/library | zöld | ✅ zöld (V1 regresszió-bizonyíték) |
| architecture | zöld | ✅ zöld |
| secrets | zöld | ✅ zöld (0 lelet, 2160 fájl) |
| l10n | zöld | ✅ zöld (en→hu, 1019 üzenet) |
| CI — Router CI (kör-branch) | — | ✅ `success` — [31487700415](https://github.com/wolfcasaba/strumsight/actions/runs/31487700415) |
| CI — Full Gate (no APK, kör-branch) | — | ✅ `success` (mindkét job: `full-gate` 8m34s, `Coverage` 11m35s) — [31487713723](https://github.com/wolfcasaba/strumsight/actions/runs/31487713723), `headSha` egyezik a lokális HEAD-del (`5ad89073`) |

## Független második vélemény

Két, ettől a review-tól elkülönített subagent-pass — mindkettő azért, mert ez
a review-jelentés ugyanabból a sessionből származik, amely a pre-flight
ADR-t írta.

1. **Dedikált biztonsági review** (`security-reviewer` agent, a brief
   `risk = "high"` miatt kötelező, AGENTS.md §15.1) — **KÉSZ.** Verdikt:
   **PASS, 0 CRITICAL/BLOCKER/MAJOR, 2 MINOR, 4 NOTE.** A két MINOR pontosan
   ez a jelentés F1-je (független, saját mérésű megerősítéssel, ld. F1
   szövege) és az itt F1b-ként felvett, ÚJ lelet (decode/encode
   véges-szám-aszimmetria a `CapabilityReport.details` bag-en) — a
   security-reviewer maga is ezt találta meg elsőként, valódi
   reprodukcióval (`1e999` → `Infinity` a `details`-ben decode után Success,
   majd újra-encode elkapatlan `ArgumentError`-ral). A 4 NOTE mind a security
   review saját megfigyelése (fabrikált `confidence:1` migrált chordokon —
   dokumentált, mitigált; `measured:false` + nulla-placeholder csak
   advisory; hiányzó-kulcs `measured` decode-defaultja `true`; a decode
   failure-kód nincs a központi `FailureCode` katalógusban) — mindegyik NOTE
   szintű, nem blokkoló, jövőbeli R07/R21 számára hasznos. A subagent a
   harness-instrukciója szerint a jelentést a válaszába írta (nem fájlba) —
   a teljes szöveg ennek a review-nak a session-történetében él, a fenti F1/F1b
   a lényegi tartalmát idézi.
2. **`flutter-devil-advocate`** — folyamatban, eredménye a merge ELŐTT
   bekerül ide.

## Merge-döntés

ADR 0052 szerint: minden gate zöld ÉS nincs nyitott BLOCKER/MAJOR → merge.
**Jelen állás: 1 nyitott MAJOR (F0) → merge TILOS, amíg nyitva.** Javító kör
indítva ugyanazzal a motorral (Terra), a findings-listával (F0 + F1b) a
promptban — ez a lánc NORMÁL útja (user-döntés 2026-07-31), nem megállási ok.
F1 (lista/map felső korlát) follow-up-ra téve R21-hez (mindhárom független
review — ez, a security, a devil's-advocate — egyetért: unwired, a helyes
korlátok csak a tényleges perzisztencia-bekötéskor dönthetők el felelősen).
Javítás után: a gate-eket ÚJRA, függetlenül lefuttatom egy friss `/tmp`
klónban, a két új teszt (bpm=0 kör-trip, decode-side finiteness) tényleg
piros lett volna-e a fix előtt (retroaktív ellenőrzés a javító commit előtti
állapoton), majd a CI-t újra-dispatch-elem az új SHA-ra, és ez a jelentés
APPROVED-ra frissül.
